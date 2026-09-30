import Foundation
import GRDB

extension SQLiteIndexDatabase {
    /// Recreates a disposable cache from JSON settings and authoritative files.
    public func rebuild(root: String, configuration: IndexConfiguration? = nil,
        writerLease: CollectionWriterLease? = nil,
        refresh: (SQLiteIndexDatabase, CollectionWriterLease) async throws -> Void,
    ) async throws {
        let lease: CollectionWriterLease
        if let writerLease { lease = writerLease }
        else { lease = try await CollectionWriterLease.acquire(root: URL(fileURLWithPath: root)) }
        guard lease.root.path == root else { throw SQLiteIndexError(message: "Writer lease belongs to another collection.") }
        defer { withExtendedLifetime(lease) {} }
        let settings = try configuration ?? IndexConfiguration.load(root: root)
        try await databaseQueue.read { db in
            if try db.tableExists("index_metadata"),
                let savedRoot = try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='root'"),
                savedRoot != root {
                throw SQLiteIndexError(message: "Index belongs to a different project root.")
            }
        }
        let directory = URL(fileURLWithPath: root).appendingPathComponent(".md-utils/rebuild/\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let previousMode = try await databaseQueue.writeWithoutTransaction { db in
            let mode = try String.fetchOne(db, sql: "PRAGMA locking_mode") ?? "normal"
            try db.execute(sql: "PRAGMA locking_mode=EXCLUSIVE")
            try db.inTransaction(.exclusive) { .commit }
            return mode
        }
        defer {
            try? databaseQueue.writeWithoutTransaction {
                try $0.execute(sql: "PRAGMA locking_mode=\(previousMode)")
                _ = try Int.fetchOne($0, sql: "SELECT count(*) FROM sqlite_master")
            }
        }
        let hasDrafts = try await databaseQueue.read {
            try Bool.fetchOne($0, sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='pending_edits')") ?? false
        }
        guard !hasDrafts else { throw SQLiteIndexError(message: "Move pending_edits out of the disposable index before rebuilding.") }
        let fresh = try SQLiteIndexDatabase(path: directory.appendingPathComponent("index.sqlite").path)
        try fresh.createCollection(root: root, configuration: settings)
        try await refresh(fresh, lease)
        try Task.checkCancellation()
        guard try fresh.freshness().isCurrent else {
            throw SQLiteIndexError(message: "Rebuild incomplete; original cache and settings retained.")
        }
        let effective = try fresh.configuration()
        // Backup publishes through the existing connection instead of renaming a live SQLite file.
        try fresh.databaseQueue.backup(to: databaseQueue)
        try effective.save(root: root)
    }

    public func rebuildAsText(root: String, scratchDirectory: URL,
        refresh: (SQLiteIndexDatabase, CollectionWriterLease) async throws -> Void,
    ) async throws {
        var settings = try IndexConfiguration.load(root: root)
        settings.metadataEncoding = .text
        try await rebuild(root: root, configuration: settings, refresh: refresh)
    }
}
