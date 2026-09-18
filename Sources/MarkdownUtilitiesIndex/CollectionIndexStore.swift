import Foundation
import GRDB

/// A persisted selection whose membership is independent of other scopes.
///
/// A candidate can belong to multiple scopes. Directory paths are project-relative
/// and end with a slash; an empty path scans the project root.
/// See <doc:RefreshingCollections> for refresh and rebuild behavior.
public struct IndexScope: Codable, Equatable, Sendable {
    /// Determines how an evaluator turns candidates into collection members.
    public enum Kind: String, Codable, Sendable {
        /// Select every eligible text file under the scope directory.
        case directory
        /// Select only candidates that conform to the named type.
        case type
        /// Select rule matches even when their validation fails.
        case rule
    }
    /// The selection policy applied by the host evaluator.
    public var kind: Kind
    /// Project-relative directory with a trailing slash, or an empty string for the root.
    public var path: String
    /// Case-sensitive type or rule name; unused for directory selections.
    public var name: String
    /// Whether scanning includes regular files beyond `.md` and `.markdown`.
    public var includeNonMarkdown: Bool

    /// Declares a recursive scope without creating or updating a database.
    ///
    /// Paths are validated when passed to ``CollectionIndexer``. Non-Markdown
    /// inclusion changes scope identity, so enabling it registers a separate scope.
    public init(kind: Kind = .directory, path: String = "", name: String = "", includeNonMarkdown: Bool = false) {
        self.kind = kind
        self.path = path
        self.name = name
        self.includeNonMarkdown = includeNonMarkdown
    }

    /// Deterministic cache identity derived from all selection settings.
    public var id: String { IndexFingerprint.hash(Data("\(kind.rawValue)\u{0}\(path)\u{0}\(name)\u{0}\(includeNonMarkdown)".utf8)) }
}

/// Selection is independent of validation; unknown selection is never a membership.
public struct IndexAssessment: Sendable {
    /// Whether this scope selects the candidate, independently of validation status.
    public var selected: Bool
    /// Evaluator outcome; `evaluation-error` forces a retry on the next refresh.
    public var status: String
    /// Valid JSON text preserving evaluator evidence, including failed expression branches.
    public var detail: String
    /// Separate findings written alongside this scope's candidate assessment.
    public var diagnostics: [IndexDiagnostic]

    /// Records selection and validation without conflating nonconformance with evaluation failure.
    ///
    /// - Parameters:
    ///   - selected: Whether the scope selects this candidate.
    ///   - status: Validation outcome, or `evaluation-error` to require a retry.
    ///   - detail: Valid JSON evidence. Invalid JSON makes the update transaction fail.
    ///   - diagnostics: Findings to persist separately from collection membership.
    public init(selected: Bool, status: String, detail: String = "{}", diagnostics: [IndexDiagnostic] = []) {
        self.selected = selected
        self.status = status
        self.detail = detail
        self.diagnostics = diagnostics
    }
}

/// A persisted finding associated with one candidate and selection scope.
public struct IndexDiagnostic: Codable, Sendable {
    /// Finding class: parse, selection, validation, evaluation, or advisory.
    public var category: String
    /// Original evaluator severity, such as `error` or `advisory`.
    public var severity: String
    /// Stable machine-readable identifier supplied by the evaluator.
    public var code: String
    /// Evaluator-defined location, such as a metadata field or expression branch.
    public var location: String
    /// Human-readable explanation of the finding.
    public var message: String

    /// Preserves a finding without imposing a new diagnostic vocabulary on the evaluator.
    public init(category: String, severity: String, code: String, location: String, message: String) {
        self.category = category
        self.severity = severity
        self.code = code
        self.location = location
        self.message = message
    }
}

/// Extracted source body and metadata, using the caller's existing parser/evaluator.
public struct IndexEvaluation: Sendable {
    /// Parsed metadata serialized as valid JSON text, usually an object.
    public var metadata: String
    /// Source text body after metadata extraction; used directly for full-text indexing.
    public var body: String
    /// `ok` enables current-document reads; other values mark parsing unavailable and force retry.
    public var parseState: String
    /// This scope's selection, validation outcome, and diagnostic findings.
    public var assessment: IndexAssessment

    /// Supplies parsed content and an independent scope assessment for transactional storage.
    ///
    /// - Parameters:
    ///   - metadata: Valid JSON text. Serialization errors fail the entire commit.
    ///   - body: Extracted source body for storage and full-text indexing.
    ///   - parseState: `ok` for current parsed content; other values require a retry.
    ///   - assessment: Independent selection and validation results for this scope.
    public init(metadata: String, body: String, parseState: String = "ok", assessment: IndexAssessment) {
        self.metadata = metadata
        self.body = body
        self.parseState = parseState
        self.assessment = assessment
    }
}

struct CachedIndexFile {
    var mtime: Double
    var size: Int64
    var hash: String
    var state: String
}

struct IndexFileChange {
    var path: String
    var mtime: Double
    var size: Int64
    var hash: String
    var evaluation: IndexEvaluation
}

extension SQLiteIndexDatabase {
    /// Upgrades an empty runtime-probe database without dropping user field indexes or views.
    ///
    /// ``CollectionIndexer/init(database:root:)`` calls this automatically.
    /// - Parameter root: Canonical absolute project directory, matching future opens.
    /// - Throws: A root mismatch, a newer unsupported migration, or a SQLite migration error.
    public func prepareCollection(root: String) throws {
        try prepareCollection(root: root, checkFTSCapability: Self.checkFTSCapability)
    }

    func prepareCollection(root: String, checkFTSCapability: (Database) throws -> Void) throws {
        let existingCollection = try databaseQueue.read { database in
            try Bool.fetchOne(database,
                sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='index_metadata')") ?? false
        }
        let recordedPolicy: (encoding: IndexMetadataEncoding?, bodyMode: IndexBodyMode?) = try databaseQueue.read { database in
            guard existingCollection else { return (nil, nil) }
            let rows = try Row.fetchAll(database,
                sql: "SELECT key,value FROM index_metadata WHERE key IN ('metadata_encoding','body_mode')")
            let values = Dictionary(uniqueKeysWithValues: rows.map { ($0["key"] as String, $0["value"] as String) })
            let encoding = values["metadata_encoding"].flatMap(IndexMetadataEncoding.init(rawValue:))
            let bodyMode = values["body_mode"].flatMap(IndexBodyMode.init(rawValue:))
            if values["metadata_encoding"] != nil && encoding == nil {
                throw SQLiteIndexError(message: "Index has an unsupported metadata encoding. Upgrade md-utils before opening it.")
            }
            if values["body_mode"] != nil && bodyMode == nil {
                throw SQLiteIndexError(message: "Index has an unsupported body mode. Upgrade md-utils before opening it.")
            }
            return (encoding, bodyMode)
        }
        let jsonbAvailable = try databaseQueue.read { supportsJSONB($0) }
        if recordedPolicy.encoding == .jsonb && !jsonbAvailable {
            throw SQLiteIndexError(message: "This cache stores SQLite JSONB, but linked SQLite \(Self.sqliteVersion) cannot read JSONB. Rebuild the cache explicitly as JSON text with a JSONB-capable md-utils runtime.")
        }
        let selectedEncoding = recordedPolicy.encoding ?? (existingCollection ? .text : (jsonbAvailable ? .jsonb : .text))
        // A collection without a recorded mode predates the storage-policy
        // migration and retained searchable bodies. Migrated collections must
        // honor their persisted policy so metadata-only reopen never needs FTS5.
        let selectedBodyMode = recordedPolicy.bodyMode ?? (existingCollection ? .fts : .metadataOnly)
        if selectedBodyMode == .fts {
            try databaseQueue.write { try checkFTSCapability($0) }
        }
        var migrator = DatabaseMigrator()
        migrator.registerMigration("collection-v1") { db in
            try db.execute(sql: """
                CREATE TABLE index_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                INSERT INTO index_metadata VALUES ('generation', '0');
                CREATE TABLE scopes(id TEXT PRIMARY KEY, definition TEXT NOT NULL,
                  state TEXT NOT NULL, error TEXT, fingerprint TEXT NOT NULL DEFAULT '');
                CREATE TABLE files(path TEXT PRIMARY KEY, mtime REAL NOT NULL, size INTEGER NOT NULL,
                  hash TEXT NOT NULL, state TEXT NOT NULL);
                CREATE TABLE assessments(scope_id TEXT NOT NULL REFERENCES scopes(id) ON DELETE CASCADE,
                  path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
                  selected INTEGER NOT NULL, status TEXT NOT NULL, detail TEXT NOT NULL CHECK(json_valid(detail)),
                  PRIMARY KEY(scope_id, path));
                CREATE TABLE diagnostics(scope_id TEXT NOT NULL, path TEXT NOT NULL,
                  category TEXT NOT NULL, severity TEXT NOT NULL, code TEXT NOT NULL,
                  location TEXT NOT NULL, message TEXT NOT NULL,
                  FOREIGN KEY(scope_id, path) REFERENCES assessments(scope_id, path) ON DELETE CASCADE);
                CREATE TABLE documents(path TEXT PRIMARY KEY REFERENCES files(path) ON DELETE CASCADE,
                  metadata TEXT NOT NULL CHECK(json_valid(metadata)), body TEXT);
                CREATE INDEX assessments_path ON assessments(path);
                CREATE VIEW current_documents AS SELECT d.path,json(d.metadata) AS metadata,d.body
                  FROM documents d JOIN files f USING(path)
                  WHERE f.state='ok' AND EXISTS(SELECT 1 FROM assessments a JOIN scopes s ON s.id=a.scope_id
                    WHERE a.path=d.path AND a.selected=1 AND s.state='complete');
                """)
        }
        migrator.registerMigration("collection-v2-query-schema") { db in
            try db.execute(sql: """
                CREATE TABLE index_fields(
                  name TEXT PRIMARY KEY,
                  json_path TEXT NOT NULL UNIQUE,
                  column_name TEXT NOT NULL UNIQUE);
                CREATE TABLE type_views(
                  type_name TEXT PRIMARY KEY,
                  view_name TEXT NOT NULL UNIQUE);
                """)
        }
        migrator.registerMigration("collection-v3-storage-policy") { database in
            let preservedViews = try Row.fetchAll(database, sql: """
                SELECT name,sql FROM sqlite_master
                WHERE type='view' AND name!='current_documents' AND sql IS NOT NULL ORDER BY name
                """).map { ($0["name"] as String, $0["sql"] as String) }
            let preservedIndexes = try String.fetchAll(database, sql: """
                SELECT sql FROM sqlite_master
                WHERE type='index' AND tbl_name='documents' AND sql IS NOT NULL ORDER BY name
                """)
            for (name, _) in preservedViews {
                try database.execute(sql: "DROP VIEW \(Self.identifier(name))")
            }
            try database.execute(sql: "DROP VIEW current_documents")
            try Self.dropFTS(database)
            try database.execute(sql: "ALTER TABLE documents RENAME TO documents_legacy")
            try database.execute(sql: """
                CREATE TABLE documents(
                  path TEXT PRIMARY KEY REFERENCES files(path) ON DELETE CASCADE,
                  metadata BLOB NOT NULL CHECK(json_valid(json(metadata))),
                  body TEXT);
                """)
            let metadataExpression = selectedEncoding == .jsonb ? "jsonb(metadata)" : "json(metadata)"
            let bodyExpression = selectedBodyMode == .fts ? "body" : "NULL"
            try database.execute(sql: """
                INSERT INTO documents(path,metadata,body)
                SELECT path,\(metadataExpression),\(bodyExpression) FROM documents_legacy;
                DROP TABLE documents_legacy;
                """)
            try database.execute(sql: "INSERT INTO index_metadata VALUES('body_mode',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [selectedBodyMode.rawValue])
            try database.execute(sql: "INSERT INTO index_metadata VALUES('metadata_encoding',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [selectedEncoding.rawValue])
            try Self.createCurrentDocumentsView(database, bodyMode: selectedBodyMode)
            for sql in preservedIndexes { try database.execute(sql: sql) }
            for (_, sql) in preservedViews { try database.execute(sql: sql) }
            if selectedBodyMode == .fts { try Self.createFTS(database) }
        }
        migrator.registerMigration("collection-v4-refresh-staging") { database in
            try database.execute(sql: """
                CREATE TABLE refresh_seen(
                  generation INTEGER NOT NULL, scope_id TEXT NOT NULL, path TEXT NOT NULL,
                  PRIMARY KEY(generation,scope_id,path));
                CREATE INDEX refresh_seen_path ON refresh_seen(generation,path);
                CREATE TABLE refresh_scopes(
                  generation INTEGER NOT NULL, scope_id TEXT NOT NULL, reusable INTEGER NOT NULL,
                  PRIMARY KEY(generation,scope_id));
                CREATE TABLE refresh_files(
                  generation INTEGER NOT NULL, path TEXT NOT NULL, mtime REAL NOT NULL,
                  size INTEGER NOT NULL, hash TEXT NOT NULL, state TEXT NOT NULL,
                  metadata TEXT NOT NULL CHECK(json_valid(metadata)), body TEXT,
                  PRIMARY KEY(generation,path));
                CREATE TABLE refresh_assessments(
                  generation INTEGER NOT NULL, scope_id TEXT NOT NULL, path TEXT NOT NULL,
                  selected INTEGER NOT NULL, status TEXT NOT NULL,
                  detail TEXT NOT NULL CHECK(json_valid(detail)),
                  PRIMARY KEY(generation,scope_id,path));
                CREATE TABLE refresh_diagnostics(
                  generation INTEGER NOT NULL, scope_id TEXT NOT NULL, path TEXT NOT NULL,
                  category TEXT NOT NULL, severity TEXT NOT NULL, code TEXT NOT NULL,
                  location TEXT NOT NULL, message TEXT NOT NULL);
                """)
        }
        guard try databaseQueue.read({ try migrator.hasBeenSuperseded($0) }) == false else {
            throw SQLiteIndexError(message: "Index schema was created by a newer md-utils version. Upgrade md-utils before updating this index.")
        }
        try migrator.migrate(databaseQueue)
        try databaseQueue.write { db in
            let existing = try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='root'")
            guard existing == nil || existing == root else {
                throw SQLiteIndexError(message: "Index belongs to a different project root: \(existing ?? "").")
            }
            try db.execute(sql: "INSERT OR IGNORE INTO index_metadata VALUES ('root', ?)", arguments: [root])
            try refreshTypeViews(db)
        }
    }

    /// Returns saved declarations, including incomplete scopes, in stable identifier order.
    ///
    /// - Throws: SQLite read errors or invalid stored scope JSON.
    public func scopes() throws -> [IndexScope] {
        try databaseQueue.read { db in
            try String.fetchAll(db, sql: "SELECT definition FROM scopes ORDER BY id").map {
                try JSONDecoder().decode(IndexScope.self, from: Data($0.utf8))
            }
        }
    }

    /// Reads the saved config path, optionally replacing it with an explicit selection.
    ///
    /// - Parameter supplied: Absolute config file path, or `nil` for a read-only lookup.
    /// - Returns: The persisted path, or `nil` when the host should use its default.
    /// - Throws: SQLite read or write errors. This method does not load the config file.
    public func configurationPath(_ supplied: String? = nil) throws -> String? {
        try databaseQueue.write { db in
            if let supplied {
                try db.execute(sql: "INSERT INTO index_metadata VALUES('config',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                    arguments: [supplied])
            }
            return try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='config'")
        }
    }

    /// Makes every scope unavailable and supersedes active scans after a host-level failure.
    ///
    /// Use this when configuration cannot be loaded. Existing content and membership
    /// remain available for diagnosis, but ``selectedPaths(scope:)`` excludes them.
    /// - Parameter message: Failure explanation stored on every scope.
    /// - Throws: SQLite write errors.
    public func invalidate(message: String) throws {
        try databaseQueue.write { db in
            try db.execute(sql: "UPDATE scopes SET state='incomplete', error=?", arguments: [message])
            try db.execute(sql: "UPDATE index_metadata SET value=CAST(value AS INTEGER)+1 WHERE key='generation'")
        }
    }

    /// Only fresh members of successfully enumerated scopes are returned.
    ///
    /// Ordinary rule nonconformance does not exclude a selected, successfully parsed
    /// document. Parse failures and incomplete scopes do. Results are sorted by path.
    /// - Parameter scope: Restrict to this selection, or `nil` for the union of current scopes.
    /// - Returns: Project-relative file paths, without duplicates.
    /// - Throws: SQLite read errors.
    public func selectedPaths(scope: IndexScope? = nil) throws -> [String] {
        try databaseQueue.read { db in
            if let scope {
                return try String.fetchAll(db, sql: """
                    SELECT d.path FROM current_documents d JOIN assessments a ON a.path=d.path
                    JOIN scopes s ON s.id=a.scope_id WHERE a.scope_id=? AND a.selected=1 AND s.state='complete' ORDER BY d.path
                    """, arguments: [scope.id])
            }
            return try String.fetchAll(db, sql: "SELECT path FROM current_documents ORDER BY path")
        }
    }

    /// Counts current documents without materializing their paths.
    public func selectedCount() throws -> Int {
        try databaseQueue.read {
            try Int.fetchOne($0, sql: "SELECT count(*) FROM current_documents") ?? 0
        }
    }
}
