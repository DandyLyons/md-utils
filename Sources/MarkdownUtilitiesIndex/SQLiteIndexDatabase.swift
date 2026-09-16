import GRDB
import GRDBSQLite

/// A native SQLite connection reserved for the rebuildable file index.
/// GRDB serializes access to the connection. Indexing operations will be added here.
public final class SQLiteIndexDatabase {
    private let databaseQueue: DatabaseQueue

    /// The system SQLite runtime used by GRDB, not a bundled version.
    public static var sqliteVersion: String { String(cString: sqlite3_libversion()) }

    /// Checks the linked runtime in memory before creating or opening an index file.
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

    /// Exercises JSON queries, JSON expression indexes, and FTS5 reads and writes.
    /// No index file is touched by this probe.
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
                        throw SQLiteIndexError(message: "System SQLite \(sqliteVersion) failed the required \(capability) check: \(error). Use a supported OS or distribution SQLite package with JSON, expression indexes, and FTS5 enabled. Updating GRDB alone does not update SQLite. The index was not opened.")
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
        ("FTS5", """
        CREATE VIRTUAL TABLE search USING fts5(body);
        INSERT INTO search VALUES ('hello indexing');
        INSERT INTO assertions SELECT count(*) = 1 FROM search WHERE search MATCH 'indexing';
        """),
    ]
}

public struct SQLiteIndexError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public var description: String { message }
}
