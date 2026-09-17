import MarkdownUtilitiesIndex
import GRDBSQLite

// A consumer can use the system C API in the same executable as the GRDB facade.
// Both resolve to the system SQLite library; there is no second bundled runtime.
enum SmokeError: Error { case systemConnectionFailed }
var consumer: OpaquePointer?
guard sqlite3_open(":memory:", &consumer) == SQLITE_OK, let connection = consumer else {
    if let consumer { sqlite3_close(consumer) }
    throw SmokeError.systemConnectionFailed
}
defer { sqlite3_close(connection) }
guard sqlite3_exec(connection, "CREATE TABLE consumer(value TEXT)", nil, nil, nil) == SQLITE_OK else {
    throw SmokeError.systemConnectionFailed
}
try SQLiteIndexDatabase.checkCapabilities()
print("System SQLite \(SQLiteIndexDatabase.sqliteVersion): GRDB JSON, expression indexes, and C consumer passed")
