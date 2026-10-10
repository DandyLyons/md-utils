import Foundation
import GRDB

/// User-owned index setup, independent of disposable SQLite content.
///
/// The JSON file remembers scope declarations and storage choices across full
/// rebuilds. It contains neither document content nor observation history.
public struct IndexConfiguration: Codable, Equatable, Sendable {
    /// The JSON configuration format version, currently `1`.
    public var version = 1
    /// The collection selections to restore when opening a fresh cache.
    public var scopes: [IndexScope] = []
    /// The saved evaluator configuration path, when one was explicitly selected.
    public var configurationPath: String?
    /// Whether the cache stores only metadata or also bodies for full-text search.
    public var bodyMode: IndexBodyMode = .metadataOnly
    /// The requested SQLite metadata representation, or `nil` for runtime selection.
    public var metadataEncoding: IndexMetadataEncoding?
    /// The managed field indexes to recreate from authoritative metadata.
    public var fields: [IndexField] = []

    /// Creates empty declarations with metadata-only storage and runtime-selected encoding.
    public init() {}

    /// Returns the JSON settings location beneath a project root.
    /// - Parameter root: The project root's filesystem path.
    /// - Returns: The URL of `.md-utils/md-utils.indexconfig.json` within the root.
    public static func url(root: String) -> URL {
        URL(fileURLWithPath: root).appendingPathComponent(".md-utils/md-utils.indexconfig.json")
    }

    /// Loads saved declarations, returning defaults when the file does not exist.
    /// - Parameter root: The project root's filesystem path.
    /// - Throws: File-reading or decoding errors, or an index error if the file
    ///   exceeds 1 MiB or declares an unsupported format version.
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

    /// Atomically replaces the saved JSON declarations, creating their parent directory.
    /// - Parameter root: The project root's filesystem path.
    /// - Throws: Encoding or filesystem errors, or an index error if encoded
    ///   declarations exceed 1 MiB. This operation does not rebuild SQLite.
    public func save(root: String) throws {
        let url = Self.url(root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= 1_048_576 else { throw SQLiteIndexError(message: "Index configuration exceeds 1 MiB.") }
        try data.write(to: url, options: .atomic)
    }

    var fingerprint: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return IndexFingerprint.hash(try encoder.encode(self))
        }
    }
}

extension SQLiteIndexDatabase {
    /// Saves only declarations. Bodies, assessments and observation history stay disposable.
    ///
    /// Unchanged declarations are not rewritten. In-memory databases and private
    /// rebuild staging databases do not save settings.
    /// - Throws: An index error if JSON settings changed outside this cache,
    ///   or a database, encoding, or filesystem error. Rebuild to apply external
    ///   configuration changes before saving declarations from this cache.
    public func saveConfiguration() throws {
        guard path != ":memory:", !path.contains("/.md-utils/rebuild/") else { return }
        try validateSavedConfiguration()
        let root = try databaseQueue.read {
            try String.fetchOne($0, sql: "SELECT value FROM index_metadata WHERE key='root'")
        }
        guard let root else { return }
        let settings = try configuration()
        // Avoid a self-triggering FSEvents loop: unchanged refreshes must not
        // rewrite the settings file watched alongside project definitions.
        if try settings == IndexConfiguration.load(root: root) { return }
        try settings.save(root: root)
        try recordConfigurationFingerprint(settings)
    }

    /// Never overwrite manually edited declarations from a stale cache or watcher.
    package func validateSavedConfiguration() throws {
        guard path != ":memory:", !path.contains("/.md-utils/rebuild/") else { return }
        let values = try databaseQueue.read { db in
            (try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='root'"),
             try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='configuration_fingerprint'"))
        }
        guard let root = values.0 else { return }
        guard try IndexConfiguration.load(root: root).fingerprint == values.1 else {
            throw SQLiteIndexError(message: "Index JSON settings changed. Run index update --rebuild to apply them; saved settings were not overwritten.")
        }
    }

    func recordConfigurationFingerprint(_ settings: IndexConfiguration) throws {
        let fingerprint = try settings.fingerprint
        try databaseQueue.write {
            try $0.execute(sql: "INSERT OR REPLACE INTO index_metadata VALUES('configuration_fingerprint',?)", arguments: [fingerprint])
        }
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
