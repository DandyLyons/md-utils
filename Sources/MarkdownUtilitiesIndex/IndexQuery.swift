import Foundation
import GRDB

/// One SQLite value returned by a read-only index query.
public enum IndexQueryValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    init(_ value: DatabaseValue) {
        switch value.storage {
        case .null: self = .null
        case .int64(let value): self = .integer(value)
        case .double(let value): self = .real(value)
        case .string(let value): self = .text(value)
        case .blob(let value): self = .blob(value)
        }
    }
}

/// Column names and typed rows from one bounded SQL statement.
public struct IndexQueryResult: Equatable, Sendable {
    public var columns: [String]
    public var rows: [[IndexQueryValue]]
    /// True when at least one additional row existed beyond the requested limit.
    public var truncated: Bool

    public init(columns: [String], rows: [[IndexQueryValue]], truncated: Bool) {
        self.columns = columns
        self.rows = rows
        self.truncated = truncated
    }
}

/// A managed expression index projected into generated type views.
public struct IndexField: Equatable, Sendable {
    public var name: String
    public var jsonPath: String
    public var columnName: String

    public init(name: String, jsonPath: String, columnName: String) {
        self.name = name
        self.jsonPath = jsonPath
        self.columnName = columnName
    }

    /// The exact expression queries must use for SQLite to select this index.
    public var queryExpression: String { "json_extract(metadata, \(Self.literal(jsonPath)))" }

    static func literal(_ value: String) -> String { "'\(value.replacingOccurrences(of: "'", with: "''"))'" }
}

/// Persisted refresh state suitable for humans and automation.
public struct IndexFreshness: Equatable, Sendable {
    public struct Scope: Equatable, Sendable {
        public var definition: IndexScope
        public var state: String
        public var error: String?
        public var fingerprint: String
    }

    public var generation: Int
    public var lastStartedAt: Double?
    public var lastCompletedAt: Double?
    public var runtimeVersion: String?
    public var scopes: [Scope]
    public var hasFailures: Bool

    /// True only when scopes exist, every scope completed, and no candidate failure remains.
    public var isCurrent: Bool {
        !scopes.isEmpty && !hasFailures && scopes.allSatisfy { $0.state == "complete" }
    }
}

extension SQLiteIndexDatabase {
    /// Executes exactly one result-producing, read-only SQL statement.
    ///
    /// SQLite's own statement classifier rejects writes, while `readOnly` also
    /// enables `PRAGMA query_only` for defense in depth. The cursor reads at most
    /// `limit + 1` rows from one serialized database snapshot.
    public func query(_ sql: String, limit: Int = 1_000) throws -> IndexQueryResult {
        guard (1...10_000).contains(limit) else {
            throw SQLiteIndexError(message: "Query limit must be between 1 and 10000 rows.")
        }
        do {
            return try databaseQueue.read { database in
                try database.readOnly {
                    let statement = try database.makeStatement(sql: sql)
                    guard statement.isReadonly else {
                        throw SQLiteIndexError(message: "Index queries are read-only; SQL mutations are not allowed.")
                    }
                    guard !statement.columnNames.isEmpty else {
                        throw SQLiteIndexError(message: "Index query must produce rows.")
                    }
                    let cursor = try Row.fetchCursor(statement)
                    var rows: [[IndexQueryValue]] = []
                    while rows.count <= limit, let row = try cursor.next() {
                        rows.append(row.map { IndexQueryValue($0.1) })
                    }
                    let truncated = rows.count > limit
                    if truncated { rows.removeLast() }
                    return IndexQueryResult(columns: statement.columnNames, rows: rows, truncated: truncated)
                }
            }
        } catch let error as SQLiteIndexError {
            throw error
        } catch {
            throw SQLiteIndexError(message: "Index query failed: \(error)")
        }
    }

    /// Creates an explicit JSON expression index and projects it into type views.
    ///
    /// Scalar JSON values retain SQLite's native integer, real, text, or null
    /// storage class. Objects and arrays are JSON text; indexing an array as a
    /// whole does not accelerate membership queries through `json_each`.
    @discardableResult
    public func addField(jsonPath: String, columnName requestedName: String? = nil) throws -> IndexField {
        guard jsonPath.hasPrefix("$") else {
            throw SQLiteIndexError(message: "Field path must be a SQLite JSON path beginning with '$'.")
        }
        return try databaseQueue.write { database in
            // Bind here to validate syntax without interpolating user input.
            _ = try DatabaseValue.fetchOne(database, sql: "SELECT json_extract('{}', ?)", arguments: [jsonPath])
            if let existing = try field(database, jsonPath: jsonPath) { return existing }
            let base = requestedName ?? Self.fieldSlug(jsonPath)
            try Self.validateIdentifier(base, label: "Field column")
            guard !["path", "metadata", "body"].contains(base) else {
                throw SQLiteIndexError(message: "Field column '\(base)' conflicts with a standard type-view column. Supply a unique --name.")
            }
            let collision = try String.fetchOne(database,
                sql: "SELECT json_path FROM index_fields WHERE column_name=?", arguments: [base])
            guard collision == nil else {
                throw SQLiteIndexError(message: "Field column '\(base)' is already used for \(collision ?? "another path"). Supply a unique --name.")
            }
            let indexName = "idx_documents_\(base)"
            let definition = IndexField(name: indexName, jsonPath: jsonPath, columnName: base)
            try database.execute(sql: "CREATE INDEX \(Self.identifier(indexName)) ON documents(\(definition.queryExpression))")
            try database.execute(sql: "INSERT INTO index_fields(name,json_path,column_name) VALUES(?,?,?)",
                arguments: [indexName, jsonPath, base])
            try refreshTypeViews(database)
            return definition
        }
    }

    /// Drops one managed field index selected by JSON path or projected column.
    @discardableResult
    public func removeField(_ pathOrName: String) throws -> Bool {
        try databaseQueue.write { database in
            guard let row = try Row.fetchOne(database,
                sql: "SELECT name,json_path,column_name FROM index_fields WHERE json_path=? OR column_name=?",
                arguments: [pathOrName, pathOrName]) else { return false }
            let field = IndexField(name: row["name"], jsonPath: row["json_path"], columnName: row["column_name"])
            try database.execute(sql: "DROP INDEX \(Self.identifier(field.name))")
            try database.execute(sql: "DELETE FROM index_fields WHERE name=?", arguments: [field.name])
            try refreshTypeViews(database)
            return true
        }
    }

    /// Lists managed field indexes in projected-column order.
    public func fields() throws -> [IndexField] {
        try databaseQueue.read { database in
            try Row.fetchAll(database, sql: "SELECT name,json_path,column_name FROM index_fields ORDER BY column_name").map {
                IndexField(name: $0["name"], jsonPath: $0["json_path"], columnName: $0["column_name"])
            }
        }
    }

    /// Reports generations, timestamps, runtime provenance, and every saved scope.
    public func freshness() throws -> IndexFreshness {
        try databaseQueue.read { database in
            let metadata = Dictionary(uniqueKeysWithValues: try Row.fetchAll(database,
                sql: "SELECT key,value FROM index_metadata").map { ($0["key"] as String, $0["value"] as String) })
            let scopes = try Row.fetchAll(database,
                sql: "SELECT definition,state,error,fingerprint FROM scopes ORDER BY id").map { row in
                IndexFreshness.Scope(
                    definition: try JSONDecoder().decode(IndexScope.self, from: Data((row["definition"] as String).utf8)),
                    state: row["state"], error: row["error"], fingerprint: row["fingerprint"])
            }
            let hasFailures = try Bool.fetchOne(database, sql: """
                SELECT EXISTS(SELECT 1 FROM files WHERE state!='ok')
                  OR EXISTS(SELECT 1 FROM assessments WHERE status='evaluation-error')
                """) ?? false
            return IndexFreshness(generation: Int(metadata["generation"] ?? "0") ?? 0,
                lastStartedAt: metadata["last_started_at"].flatMap(Double.init),
                lastCompletedAt: metadata["last_completed_at"].flatMap(Double.init),
                runtimeVersion: metadata["runtime"], scopes: scopes, hasFailures: hasFailures)
        }
    }

    func refreshTypeViews(_ database: Database) throws {
        let typeNames = try String.fetchAll(database, sql: """
            SELECT DISTINCT json_extract(definition, '$.name') FROM scopes
            WHERE json_extract(definition, '$.kind')='type' ORDER BY 1
            """)
        let fields = try Row.fetchAll(database,
            sql: "SELECT name,json_path,column_name FROM index_fields ORDER BY column_name").map {
            IndexField(name: $0["name"], jsonPath: $0["json_path"], columnName: $0["column_name"])
        }
        for typeName in typeNames {
            let base = "type_\(Self.identifierSlug(typeName))"
            let prior = try String.fetchOne(database,
                sql: "SELECT view_name FROM type_views WHERE type_name=?", arguments: [typeName])
            let baseOwner = try String.fetchOne(database,
                sql: "SELECT type_name FROM type_views WHERE view_name=?", arguments: [base])
            let baseExists = try Bool.fetchOne(database,
                sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name=?)", arguments: [base]) ?? false
            let viewName: String
            if let prior { viewName = prior }
            else if (!baseExists && baseOwner == nil) || baseOwner == typeName { viewName = base }
            else {
                let candidate = "\(base)_\(IndexFingerprint.hash(Data(typeName.utf8)).prefix(8))"
                let candidateExists = try Bool.fetchOne(database,
                    sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name=?)", arguments: [candidate]) ?? false
                guard !candidateExists else {
                    throw SQLiteIndexError(message: "Cannot create type view for '\(typeName)': SQL object '\(candidate)' already exists.")
                }
                viewName = candidate
            }
            if let prior, prior != viewName {
                try database.execute(sql: "DROP VIEW IF EXISTS \(Self.identifier(prior))")
            }
            try database.execute(sql: "INSERT INTO type_views(type_name,view_name) VALUES(?,?) ON CONFLICT(type_name) DO UPDATE SET view_name=excluded.view_name",
                arguments: [typeName, viewName])
            if prior != nil { try database.execute(sql: "DROP VIEW IF EXISTS \(Self.identifier(viewName))") }
            let projections = fields.map {
                ", json_extract(d.metadata, \(IndexField.literal($0.jsonPath))) AS \(Self.identifier($0.columnName))"
            }.joined()
            try database.execute(sql: """
                CREATE VIEW \(Self.identifier(viewName)) AS
                SELECT d.path,d.metadata,d.body\(projections) FROM current_documents d
                WHERE EXISTS(SELECT 1 FROM assessments a JOIN scopes s ON s.id=a.scope_id
                  WHERE a.path=d.path AND a.selected=1 AND a.status='conforms' AND s.state='complete'
                    AND json_extract(s.definition, '$.kind')='type'
                    AND json_extract(s.definition, '$.name')=\(IndexField.literal(typeName)))
                """)
        }
    }

    private func field(_ database: Database, jsonPath: String) throws -> IndexField? {
        guard let row = try Row.fetchOne(database,
            sql: "SELECT name,json_path,column_name FROM index_fields WHERE json_path=?", arguments: [jsonPath]) else { return nil }
        return IndexField(name: row["name"], jsonPath: row["json_path"], columnName: row["column_name"])
    }

    static func fieldSlug(_ path: String) -> String {
        let trimmed = path.drop(while: { $0 == "$" || $0 == "." })
        let slug = identifierSlug(String(trimmed))
        return slug.isEmpty ? "field_\(IndexFingerprint.hash(Data(path.utf8)).prefix(8))" : slug
    }

    static func identifierSlug(_ value: String) -> String {
        var result = ""
        var previousUnderscore = false
        for scalar in value.lowercased().unicodeScalars {
            let allowed = CharacterSet.alphanumerics.contains(scalar)
            if allowed {
                result.unicodeScalars.append(scalar)
                previousUnderscore = false
            } else if !previousUnderscore && !result.isEmpty {
                result.append("_")
                previousUnderscore = true
            }
        }
        while result.hasSuffix("_") { result.removeLast() }
        if result.first?.isNumber == true { result = "field_\(result)" }
        return result
    }

    static func validateIdentifier(_ value: String, label: String) throws {
        guard !value.isEmpty, value == identifierSlug(value), value.first?.isNumber != true else {
            throw SQLiteIndexError(message: "\(label) must contain lowercase letters, numbers, and underscores, and must not start with a number.")
        }
    }

    static func identifier(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
}
