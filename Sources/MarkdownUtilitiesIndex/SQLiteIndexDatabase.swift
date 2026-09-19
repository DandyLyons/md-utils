import GRDB
import GRDBSQLite

/// A native SQLite connection reserved for the rebuildable file index.
/// GRDB serializes access and commits collection changes transactionally.
/// Its only stored state is GRDB's thread-safe serialized queue.
public final class SQLiteIndexDatabase: Sendable {
    let databaseQueue: DatabaseQueue

    /// Synchronous native adapter access. The closure cannot suspend a read transaction.
    package func serverRead<T>(_ body: (Database) throws -> T) throws -> T {
        try databaseQueue.read(body)
    }

    /// Publishes one bounded native adapter staging batch transactionally.
    package func serverWrite<T>(_ body: (Database) throws -> T) throws -> T {
        try databaseQueue.write(body)
    }

    /// Filesystem path used to exclude the cache and sidecars from native watching.
    public var path: String { databaseQueue.path }

    /// The system SQLite runtime used by GRDB, not a bundled version.
    public static var sqliteVersion: String { String(cString: sqlite3_libversion()) }

    /// Checks baseline JSON support before creating or opening an index file.
    ///
    /// The parent directory must already exist. Collection tables are created by
    /// ``prepareCollection(root:)``, which ``CollectionIndexer`` calls automatically.
    /// - Parameter path: SQLite database file path, or `:memory:` for an ephemeral cache.
    /// - Throws: ``SQLiteIndexError`` if required capabilities or file access are unavailable.
    public convenience init(path: String) throws {
        try self.init(path: path, probe: Self.checkCapabilities)
    }

    internal init(path: String, probe: () throws -> Void) throws {
        try probe()
        do {
            databaseQueue = try DatabaseQueue(path: path)
        } catch {
            throw SQLiteIndexError(message: "Cannot open SQLite index at \(path): \(error). Check the parent directory and permissions.")
        }
    }

    /// Exercises baseline JSON queries and expression indexes. FTS5 is checked
    /// only for an index whose recorded policy enables body search.
    ///
    /// - Throws: ``SQLiteIndexError`` identifying the failed capability and linked runtime.
    public static func checkCapabilities() throws {
        try checkCapabilities(probes: capabilityProbes)
    }

    internal static func checkCapabilities(probes: [(String, String)]) throws {
        do {
            let queue = try DatabaseQueue()
            try queue.write { database in
                for (capability, sql) in probes {
                    do {
                        try database.execute(sql: sql)
                    } catch {
                        throw SQLiteIndexError(message: "System SQLite \(sqliteVersion) failed the required \(capability) check: \(error). Use a supported OS or distribution SQLite package with JSON and expression indexes enabled. Updating GRDB alone does not update SQLite. The index was not opened.")
                    }
                }
            }
        } catch let error as SQLiteIndexError {
            throw error
        } catch {
            throw SQLiteIndexError(message: "Cannot probe system SQLite \(sqliteVersion): \(error). Check the OS or distribution SQLite installation. The index was not opened.")
        }
    }

    internal static let capabilityProbes: [(String, String)] = [
        ("JSON queries and expression indexes", """
        CREATE TABLE records(document TEXT);
        CREATE INDEX record_title ON records(json_extract(document, '$.title'));
        INSERT INTO records VALUES ('{"title":"hello"}');
        CREATE TABLE assertions(ok INTEGER CHECK(ok = 1));
        INSERT INTO assertions SELECT count(*) = 1 FROM records
          INDEXED BY record_title WHERE json_extract(document, '$.title') = 'hello';
        """),
    ]
}

/// An index failure with a human-readable explanation and recovery context.
public struct SQLiteIndexError: Error, CustomStringConvertible, Sendable {
    /// Explains the runtime, filesystem, scope, or cache-state problem.
    public let message: String
    /// The same actionable explanation exposed through `CustomStringConvertible`.
    public var description: String { message }
}
