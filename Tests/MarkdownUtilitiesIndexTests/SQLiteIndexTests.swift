import Foundation
import Testing
@testable import MarkdownUtilitiesIndex

private func temporaryFile() throws -> URL {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("tmp/sqlite-tests/", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(UUID().uuidString)
}

@Test func `system runtime supports all required capabilities`() throws {
    #expect(!SQLiteIndexDatabase.sqliteVersion.isEmpty)
    try SQLiteIndexDatabase.checkCapabilities()
}

@Test func `capability failure identifies runtime and remediation`() throws {
    do {
        try SQLiteIndexDatabase.checkCapabilities(probes: [("JSON", "SELECT missing_json_function('{}')")])
        Issue.record("Expected capability failure")
    } catch let error as SQLiteIndexError {
        #expect(error.description.contains("JSON"))
        #expect(error.description.contains(SQLiteIndexDatabase.sqliteVersion))
        #expect(error.description.contains("OS or distribution SQLite package"))
        #expect(error.description.contains("Updating GRDB alone does not update SQLite"))
        #expect(error.description.contains("index was not opened"))
    }
}

@Test func `successful probe permits opening an index file`() throws {
    let file = try temporaryFile()
    defer { try? FileManager.default.removeItem(at: file) }
    let database = try SQLiteIndexDatabase(path: file.path)
    withExtendedLifetime(database) {
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}

@Test func `failed FTS probe does not create an index`() throws {
    let path = try temporaryFile().path
    #expect(throws: SQLiteIndexError.self) {
        _ = try SQLiteIndexDatabase(path: path) {
            try SQLiteIndexDatabase.checkCapabilities(probes: [("FTS5", "CREATE VIRTUAL TABLE unavailable USING missing_fts5(body)")])
        }
    }
    #expect(!FileManager.default.fileExists(atPath: path))
}

@Test func `failed JSON probe preserves an existing file`() throws {
    let file = try temporaryFile()
    let original = Data("existing index".utf8)
    try original.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(throws: SQLiteIndexError.self) {
        _ = try SQLiteIndexDatabase(path: file.path) {
            try SQLiteIndexDatabase.checkCapabilities(probes: [("JSON", "SELECT missing_json_function('{}')")])
        }
    }
    #expect(try Data(contentsOf: file) == original)
}

@Test func `invalid parent reports an actionable open error`() throws {
    let path = try temporaryFile().appendingPathComponent("index.sqlite").path
    do {
        _ = try SQLiteIndexDatabase(path: path)
        Issue.record("Expected file-open failure")
    } catch let error as SQLiteIndexError {
        #expect(error.description.contains(path))
        #expect(error.description.contains("parent directory and permissions"))
    }
}

@Test func `probe rejects incorrect query results`() {
    #expect(throws: SQLiteIndexError.self) {
        try SQLiteIndexDatabase.checkCapabilities(probes: [
            ("result assertions", "CREATE TABLE assertions(ok INTEGER CHECK(ok = 1)); INSERT INTO assertions VALUES (0);")
        ])
    }
}
