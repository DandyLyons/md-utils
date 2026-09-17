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

struct IndexScopeChange {
    var scope: IndexScope
    var seen: Set<String>
    var changes: [IndexFileChange]
    var error: String?
}

struct IndexCacheSnapshot {
    var generation: Int
    var files: [String: CachedIndexFile]
    var assessments: [String: Set<String>]
}

extension SQLiteIndexDatabase {
    /// Upgrades an empty runtime-probe database without dropping user field indexes or views.
    ///
    /// ``CollectionIndexer/init(database:root:)`` calls this automatically.
    /// - Parameter root: Canonical absolute project directory, matching future opens.
    /// - Throws: A root mismatch, a newer unsupported migration, or a SQLite migration error.
    public func prepareCollection(root: String) throws {
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
                  metadata TEXT NOT NULL CHECK(json_valid(metadata)), body TEXT NOT NULL);
                CREATE VIRTUAL TABLE documents_fts USING fts5(path UNINDEXED, body);
                CREATE TRIGGER documents_insert AFTER INSERT ON documents BEGIN
                  INSERT INTO documents_fts(rowid,path,body) VALUES(new.rowid,new.path,new.body);
                END;
                CREATE TRIGGER documents_delete AFTER DELETE ON documents BEGIN
                  DELETE FROM documents_fts WHERE rowid=old.rowid;
                END;
                CREATE TRIGGER documents_update AFTER UPDATE ON documents BEGIN
                  DELETE FROM documents_fts WHERE rowid=old.rowid;
                  INSERT INTO documents_fts(rowid,path,body) VALUES(new.rowid,new.path,new.body);
                END;
                CREATE INDEX assessments_path ON assessments(path);
                CREATE VIEW current_documents AS SELECT d.* FROM documents d JOIN files f USING(path)
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

    /// Marks old results unavailable before scanning, including when the process is interrupted.
    func begin(scopes: [IndexScope], fingerprint: String = "") throws -> IndexCacheSnapshot {
        try databaseQueue.write { db in
            let files = Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT * FROM files").map { row in
                (row["path"] as String, CachedIndexFile(mtime: row["mtime"], size: row["size"], hash: row["hash"], state: row["state"]))
            })
            var assessments: [String: Set<String>] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT a.scope_id,a.path FROM assessments a JOIN scopes s ON s.id=a.scope_id
                WHERE s.fingerprint=? AND s.state='complete' AND a.status!='evaluation-error'
                """, arguments: [fingerprint]) {
                assessments[row["scope_id"], default: []].insert(row["path"])
            }
            let generation = (try Int.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='generation'") ?? 0) + 1
            try db.execute(sql: "UPDATE index_metadata SET value=? WHERE key='generation'", arguments: [String(generation)])
            try db.execute(sql: "INSERT INTO index_metadata VALUES('last_started_at',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [String(Date().timeIntervalSince1970)])
            for scope in scopes {
                let definition = String(decoding: try JSONEncoder().encode(scope), as: UTF8.self)
                try db.execute(sql: """
                    INSERT INTO scopes(id,definition,state) VALUES(?,?,'updating')
                    ON CONFLICT(id) DO UPDATE SET state='updating', error=NULL
                    """, arguments: [scope.id, definition])
            }
            return IndexCacheSnapshot(generation: generation, files: files, assessments: assessments)
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

    func commit(_ scopes: [IndexScopeChange], fingerprint: String, generation: Int) throws {
        try databaseQueue.write { db in
            guard try Int.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='generation'") == generation else {
                throw SQLiteIndexError(message: "Another index update started during this scan; retry the update.")
            }
            for result in scopes {
                let scopeID = result.scope.id
                // Failed enumeration never prunes membership, even during rebuild.
                if result.error == nil {
                    let old = try String.fetchAll(db, sql: "SELECT path FROM assessments WHERE scope_id=?", arguments: [scopeID])
                    for path in old where !result.seen.contains(path) {
                        try db.execute(sql: "DELETE FROM assessments WHERE scope_id=? AND path=?", arguments: [scopeID, path])
                    }
                }
                for file in result.changes {
                    let assessment = file.evaluation.assessment
                    try db.execute(sql: """
                        INSERT INTO files VALUES(?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET
                          mtime=excluded.mtime,size=excluded.size,hash=excluded.hash,state=excluded.state
                        """, arguments: [file.path, file.mtime, file.size, file.hash, file.evaluation.parseState])
                    try db.execute(sql: "DELETE FROM assessments WHERE scope_id=? AND path=?", arguments: [scopeID, file.path])
                    try db.execute(sql: "INSERT INTO assessments VALUES(?,?,?,?,?)",
                        arguments: [scopeID, file.path, assessment.selected, assessment.status, assessment.detail])
                    for diagnostic in assessment.diagnostics {
                        try db.execute(sql: "INSERT INTO diagnostics VALUES(?,?,?,?,?,?,?)", arguments: [scopeID, file.path,
                            diagnostic.category, diagnostic.severity, diagnostic.code, diagnostic.location, diagnostic.message])
                    }
                    // Refresh a retained document even when this particular scope no longer selects it.
                    try db.execute(sql: """
                        INSERT INTO documents(path,metadata,body) VALUES(?,?,?) ON CONFLICT(path) DO UPDATE SET
                          metadata=excluded.metadata,body=excluded.body
                        """, arguments: [file.path, file.evaluation.metadata, file.evaluation.body])
                }
                try db.execute(sql: "UPDATE scopes SET state=?,error=?,fingerprint=? WHERE id=?",
                    arguments: [result.error == nil ? "complete" : "incomplete", result.error, fingerprint, scopeID])
            }
            try db.execute(sql: "DELETE FROM documents WHERE NOT EXISTS(SELECT 1 FROM assessments a WHERE a.path=documents.path AND a.selected=1)")
            try db.execute(sql: "DELETE FROM files WHERE NOT EXISTS(SELECT 1 FROM assessments a WHERE a.path=files.path)")
            try db.execute(sql: "INSERT INTO index_metadata VALUES('runtime',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [IndexFingerprint.runtimeVersion])
            let completed = scopes.allSatisfy { result in
                result.error == nil && result.changes.allSatisfy {
                    $0.evaluation.parseState == "ok" && $0.evaluation.assessment.status != "evaluation-error"
                }
            }
            if completed {
                try db.execute(sql: "INSERT INTO index_metadata VALUES('last_completed_at',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                    arguments: [String(Date().timeIntervalSince1970)])
            }
            try refreshTypeViews(db)
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
}
