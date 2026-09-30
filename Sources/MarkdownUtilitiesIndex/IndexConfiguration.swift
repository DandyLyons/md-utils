import Foundation
import GRDB

/// User-owned index setup, independent of disposable SQLite content.
public struct IndexConfiguration: Codable, Equatable, Sendable {
    public var version = 1
    public var scopes: [IndexScope] = []
    public var configurationPath: String?
    public var bodyMode: IndexBodyMode = .metadataOnly
    public var metadataEncoding: IndexMetadataEncoding?
    public var fields: [IndexField] = []

    public init() {}

    public static func url(root: String) -> URL {
        URL(fileURLWithPath: root).appendingPathComponent(".md-utils/md-utils.indexconfig.json")
    }

    public static func load(root: String) throws -> Self {
        let url = url(root: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw SQLiteIndexError(message: "Index configuration exceeds 1 MiB.") }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1 else { throw SQLiteIndexError(message: "Unsupported index configuration version.") }
        return result
    }

    public func save(root: String) throws {
        let url = Self.url(root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

extension SQLiteIndexDatabase {
    /// Saves only declarations. Bodies, assessments and observation history stay disposable.
    public func saveConfiguration() throws {
        guard path != ":memory:", !path.contains("/.md-utils/rebuild/") else { return }
        let root = try databaseQueue.read {
            try String.fetchOne($0, sql: "SELECT value FROM index_metadata WHERE key='root'")
        }
        guard let root else { return }
        try configuration().save(root: root)
    }

    func configuration() throws -> IndexConfiguration {
        var result = IndexConfiguration()
        result.scopes = try scopes()
        result.configurationPath = try configurationPath()
        let policy = try storagePolicy()
        result.bodyMode = policy.bodyMode
        result.metadataEncoding = policy.metadataEncoding
        result.fields = try fields()
        return result
    }

    func installConfiguration(_ configuration: IndexConfiguration) throws {
        try databaseQueue.write { db in
            for scope in configuration.scopes {
                let definition = String(decoding: try JSONEncoder().encode(scope), as: UTF8.self)
                try db.execute(sql: "INSERT OR IGNORE INTO scopes(id,definition,state) VALUES(?,?,'incomplete')",
                    arguments: [scope.id, definition])
            }
            if let path = configuration.configurationPath {
                try db.execute(sql: "INSERT OR REPLACE INTO index_metadata VALUES('config',?)", arguments: [path])
            }
        }
        for field in configuration.fields { try addField(jsonPath: field.jsonPath, columnName: field.columnName) }
    }
}
