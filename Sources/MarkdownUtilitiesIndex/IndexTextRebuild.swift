import Foundation
import GRDB

extension SQLiteIndexDatabase {
    /// Rebuilds a private disk-backed copy as JSON text, publishing only on success.
    ///
    /// The callback must refresh every saved scope from authoritative files and
    /// throw on incomplete results. Unrelated tables, including pending edits,
    /// survive because the entire database is copied. Use a project-local scratch
    /// directory. Recovery holds an exclusive SQLite lock to prevent other
    /// connections from modifying pending edits or declarations during the copy.
    public func rebuildAsText(
        root: String, scratchDirectory: URL,
        refresh: (SQLiteIndexDatabase, CollectionWriterLease) async throws -> Void
    ) async throws {
        let lease = try await CollectionWriterLease.acquire(root: URL(fileURLWithPath: root))
        defer { withExtendedLifetime(lease) {} }
        let previousLockingMode = try acquireRecoveryLock()
        defer { releaseRecoveryLock(previousLockingMode) }
        let directory = scratchDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (copy, version, generation) = try prepareTextCopy(root: root, directory: directory)
        try await refresh(copy, lease)
        try Task.checkCancellation()
        try publishTextCopy(copy, version: version, generation: generation)
    }

    private func acquireRecoveryLock() throws -> String {
        try databaseQueue.writeWithoutTransaction { database in
            let previous = try String.fetchOne(database, sql: "PRAGMA locking_mode") ?? "normal"
            do {
                try database.execute(sql: "PRAGMA locking_mode=EXCLUSIVE")
                // GRDB owns transaction setup, commit, and rollback. Exclusive
                // locking mode retains the acquired lock after this transaction,
                // across async refresh and SQLite backup (which requires that
                // the destination have no open transaction).
                try database.inTransaction(.exclusive) { .commit }
                return previous
            } catch {
                try? database.execute(sql: "PRAGMA locking_mode=\(previous)")
                throw SQLiteIndexError(message: "Cannot acquire exclusive access for text rebuild: \(error). Stop other index connections and retry.")
            }
        }
    }

    private func releaseRecoveryLock(_ mode: String) {
        try? databaseQueue.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA locking_mode=\(mode)")
            // SQLite releases a retained exclusive lock on the next database access.
            _ = try Int.fetchOne(database, sql: "SELECT count(*) FROM sqlite_master")
        }
    }

    private func prepareTextCopy(root: String, directory: URL) throws -> (SQLiteIndexDatabase, Int?, String?) {
        let copy = try SQLiteIndexDatabase(path: directory.appendingPathComponent("index.sqlite").path)
        let version = try databaseQueue.read { try Int.fetchOne($0, sql: "PRAGMA data_version") }
        try databaseQueue.backup(to: copy.databaseQueue)
        let generation = try copy.databaseQueue.read { database in
            guard try String.fetchOne(database, sql: "SELECT value FROM index_metadata WHERE key='root'") == root else {
                throw SQLiteIndexError(message: "Index belongs to a different project root.")
            }
            return try String.fetchOne(database, sql: "SELECT value FROM index_metadata WHERE key='generation'")
        }
        try copy.databaseQueue.write { database in
            let policy = try copy.storagePolicy(database)
            // Discard binary metadata without asking the old runtime to decode it.
            // DROP TABLE also removes expression indexes without evaluating them.
            let views = try Row.fetchAll(database, sql: "SELECT name,sql FROM sqlite_master WHERE type='view' AND sql IS NOT NULL")
            let indexes = try String.fetchAll(database, sql: "SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name='documents' AND sql IS NOT NULL")
            for row in views { try database.execute(sql: "DROP VIEW \(Self.identifier(row["name"]))") }
            try Self.dropFTS(database)
            try database.execute(sql: """
                DROP TABLE documents;
                CREATE TABLE documents(
                  path TEXT PRIMARY KEY REFERENCES files(path) ON DELETE CASCADE,
                  metadata BLOB NOT NULL CHECK(typeof(metadata)='text' AND json_valid(metadata)), body TEXT);
                UPDATE index_metadata SET value='text' WHERE key='metadata_encoding';
                UPDATE scopes SET state='incomplete',error='Text rebuild requires authoritative refresh';
                """)
            for sql in indexes { try database.execute(sql: sql) }
            for row in views { let sql: String = row["sql"]; try database.execute(sql: sql) }
            if policy.bodyMode == .fts { try Self.createFTS(database) }
        }
        try copy.prepareCollection(root: root)
        try copy.databaseQueue.write { database in
            try database.execute(sql: "DROP TRIGGER IF EXISTS metadata_encoding_insert; DROP TRIGGER IF EXISTS metadata_encoding_update")
            try Self.createMetadataValidation(database)
        }
        return (copy, version, generation)
    }

    private func publishTextCopy(_ copy: SQLiteIndexDatabase, version: Int?, generation: String?) throws {
        try copy.databaseQueue.read { source in
            let incomplete = try Bool.fetchOne(source, sql: """
                SELECT EXISTS(SELECT 1 FROM scopes WHERE state!='complete')
                  OR EXISTS(SELECT 1 FROM files WHERE state!='ok')
                  OR EXISTS(SELECT 1 FROM assessments WHERE status='evaluation-error')
                """) ?? true
            guard !incomplete else { throw SQLiteIndexError(message: "Text rebuild was incomplete; original cache retained.") }
            try databaseQueue.writeWithoutTransaction { destination in
                guard try Int.fetchOne(destination, sql: "PRAGMA data_version") == version,
                    try String.fetchOne(destination, sql: "SELECT value FROM index_metadata WHERE key='generation'") == generation else {
                    throw SQLiteIndexError(message: "Index changed during text rebuild; original cache retained. Retry with exclusive access.")
                }
                try source.backup(to: destination)
            }
        }
    }
}
