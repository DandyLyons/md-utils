import Foundation
import GRDB

/// Whether an index retains source bodies and exposes FTS5 search.
public enum IndexBodyMode: String, Codable, Sendable {
    /// Persist metadata and assessments only. Document bodies are unavailable.
    case metadataOnly = "metadata-only"
    /// Persist one body per document and maintain external-content FTS5.
    case fts
}

/// SQLite representation used by the raw `documents.metadata` column.
public enum IndexMetadataEncoding: String, Codable, Sendable {
    /// Ordinary UTF-8 JSON text.
    case text
    /// SQLite's internal JSONB blob representation.
    case jsonb
}

/// Persisted storage capabilities for one index file.
public struct IndexStoragePolicy: Equatable, Sendable {
    public var bodyMode: IndexBodyMode
    public var metadataEncoding: IndexMetadataEncoding

    public init(bodyMode: IndexBodyMode, metadataEncoding: IndexMetadataEncoding) {
        self.bodyMode = bodyMode
        self.metadataEncoding = metadataEncoding
    }
}

extension SQLiteIndexDatabase {
    /// Returns the recorded per-index body and metadata policy.
    public func storagePolicy() throws -> IndexStoragePolicy {
        try databaseQueue.read { database in try storagePolicy(database) }
    }

    /// Changes body retention and FTS availability atomically.
    ///
    /// Enabling search creates an empty external-content FTS index and marks all
    /// scopes incomplete. The caller must perform a rebuild to populate bodies.
    /// Disabling search removes FTS objects and clears every cached body.
    public func setBodyMode(_ mode: IndexBodyMode) throws {
        try databaseQueue.write { database in
            let policy = try storagePolicy(database)
            guard policy.bodyMode != mode else { return }
            switch mode {
            case .metadataOnly:
                try Self.dropFTS(database)
                try database.execute(sql: "UPDATE documents SET body=NULL")
            case .fts:
                try Self.checkFTSCapability(database)
                try Self.createFTS(database)
                try database.execute(sql: "UPDATE scopes SET state='incomplete', error='FTS enabled; rebuild required'")
            }
            try database.execute(sql: "INSERT INTO index_metadata VALUES('body_mode',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [mode.rawValue])
            try Self.createCurrentDocumentsView(database, bodyMode: mode)
            try refreshTypeViews(database)
        }
    }

    /// Rewrites the database file so pages freed by disabling FTS can be returned.
    public func vacuum() throws {
        try databaseQueue.writeWithoutTransaction { try $0.execute(sql: "VACUUM") }
    }

    func storagePolicy(_ database: Database) throws -> IndexStoragePolicy {
        let body = try String.fetchOne(database,
            sql: "SELECT value FROM index_metadata WHERE key='body_mode'") ?? IndexBodyMode.metadataOnly.rawValue
        let encoding = try String.fetchOne(database,
            sql: "SELECT value FROM index_metadata WHERE key='metadata_encoding'") ?? IndexMetadataEncoding.text.rawValue
        guard let bodyMode = IndexBodyMode(rawValue: body), let metadataEncoding = IndexMetadataEncoding(rawValue: encoding) else {
            throw SQLiteIndexError(message: "Index has an unsupported storage policy. Upgrade md-utils before opening it.")
        }
        return IndexStoragePolicy(bodyMode: bodyMode, metadataEncoding: metadataEncoding)
    }

    func supportsJSONB(_ database: Database) -> Bool {
        (try? Bool.fetchOne(database, sql: """
            SELECT typeof(jsonb('{"value":42}'))='blob'
              AND json_extract(jsonb('{"value":42}'),'$.value')=42
              AND json_valid(jsonb('{"value":42}'),8)=1
            """)) == true
    }

    static func createMetadataValidation(_ database: Database) throws {
        let encoding = try String.fetchOne(database, sql: "SELECT value FROM index_metadata WHERE key='metadata_encoding'")
        let validation = encoding == "jsonb" ? "json_valid(new.metadata,8)" : "json_valid(new.metadata)"
        for operation in ["INSERT", "UPDATE OF metadata"] {
            let suffix = operation == "INSERT" ? "insert" : "update"
            try database.execute(sql: """
                CREATE TRIGGER metadata_encoding_\(suffix) BEFORE \(operation) ON documents
                WHEN typeof(new.metadata) != CASE
                  (SELECT value FROM index_metadata WHERE key='metadata_encoding')
                  WHEN 'jsonb' THEN 'blob' ELSE 'text' END
                  OR NOT \(validation)
                BEGIN SELECT RAISE(ABORT,'Metadata does not match recorded encoding'); END;
                """)
        }
    }

    static func checkFTSCapability(_ database: Database) throws {
        do {
            try database.execute(sql: "CREATE VIRTUAL TABLE temp.__md_utils_fts_probe USING fts5(body)")
            try database.execute(sql: "DROP TABLE temp.__md_utils_fts_probe")
        } catch {
            throw SQLiteIndexError(message: "This index has FTS enabled, but system SQLite \(Self.sqliteVersion) does not provide FTS5: \(error). Disable search with a compatible md-utils runtime or install a system SQLite package with FTS5.")
        }
    }

    static func createFTS(_ database: Database) throws {
        let exists = try Bool.fetchOne(database,
            sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='documents_fts')") ?? false
        guard !exists else { return }
        try database.execute(sql: """
            CREATE VIRTUAL TABLE documents_fts USING fts5(body, content='documents', content_rowid='rowid');
            CREATE TRIGGER documents_fts_insert AFTER INSERT ON documents WHEN new.body IS NOT NULL BEGIN
              INSERT INTO documents_fts(rowid,body) VALUES(new.rowid,new.body);
            END;
            CREATE TRIGGER documents_fts_delete AFTER DELETE ON documents WHEN old.body IS NOT NULL BEGIN
              INSERT INTO documents_fts(documents_fts,rowid,body) VALUES('delete',old.rowid,old.body);
            END;
            CREATE TRIGGER documents_fts_update_delete AFTER UPDATE OF body ON documents
              WHEN old.body IS NOT NULL AND old.body IS NOT new.body BEGIN
              INSERT INTO documents_fts(documents_fts,rowid,body) VALUES('delete',old.rowid,old.body);
            END;
            CREATE TRIGGER documents_fts_update_insert AFTER UPDATE OF body ON documents
              WHEN new.body IS NOT NULL AND old.body IS NOT new.body BEGIN
              INSERT INTO documents_fts(rowid,body) VALUES(new.rowid,new.body);
            END;
            INSERT INTO documents_fts(documents_fts) VALUES('rebuild');
            """)
    }

    static func dropFTS(_ database: Database) throws {
        try database.execute(sql: """
            DROP TRIGGER IF EXISTS documents_fts_insert;
            DROP TRIGGER IF EXISTS documents_fts_delete;
            DROP TRIGGER IF EXISTS documents_fts_update_delete;
            DROP TRIGGER IF EXISTS documents_fts_update_insert;
            DROP TRIGGER IF EXISTS documents_insert;
            DROP TRIGGER IF EXISTS documents_delete;
            DROP TRIGGER IF EXISTS documents_update;
            DROP TABLE IF EXISTS documents_fts;
            """)
    }

    static func createCurrentDocumentsView(_ database: Database, bodyMode: IndexBodyMode) throws {
        try database.execute(sql: "DROP VIEW IF EXISTS current_documents")
        let bodyColumn = bodyMode == .fts ? ",d.body" : ""
        try database.execute(sql: """
            CREATE VIEW current_documents AS
            SELECT d.path,json(d.metadata) AS metadata\(bodyColumn)
            FROM documents d JOIN files f USING(path)
            WHERE f.state='ok' AND EXISTS(SELECT 1 FROM assessments a JOIN scopes s ON s.id=a.scope_id
              WHERE a.path=d.path AND a.selected=1 AND s.state='complete')
            """)
    }
}
