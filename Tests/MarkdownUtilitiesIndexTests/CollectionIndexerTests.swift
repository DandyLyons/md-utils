import Foundation
import GRDB
import Testing
@testable import MarkdownUtilitiesIndex

private struct IndexFixture {
    let root: URL
    let database: SQLiteIndexDatabase
    let indexer: CollectionIndexer

    init() throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/index-tests/\(UUID().uuidString)/", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes/"), withIntermediateDirectories: true)
        database = try SQLiteIndexDatabase(path: root.appendingPathComponent("index.sqlite").path)
        indexer = try CollectionIndexer(database: database, root: root)
    }

    func write(_ path: String, _ text: String) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    func count(_ table: String) throws -> Int {
        try database.databaseQueue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM \(table)") ?? 0 }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func selectAll(_ scope: IndexScope, _ path: String, _ content: String, _ modified: Date) async throws -> IndexEvaluation {
    IndexEvaluation(metadata: "{}", body: content, assessment: IndexAssessment(selected: true, status: "selected"))
}

@Suite("Incremental collection indexing")
struct CollectionIndexerTests {
    @Test func `creation refresh edits additions deletions and rebuild preserve declared SQL`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "first")
        let scope = IndexScope(path: "notes/")
        let first = try await fixture.indexer.update(adding: scope, fingerprint: "v1", evaluate: selectAll)
        #expect(first.evaluated == 1)
        let noop = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(noop.cached == 1)
        #expect(noop.hashed == 0)
        try fixture.write("notes/one.md", "edited body")
        try fixture.write("notes/two.md", "second")
        let changed = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(changed.evaluated == 2)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("notes/one.md"))
        _ = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(try fixture.database.selectedPaths() == ["notes/two.md"])
        #expect(try fixture.count("documents_fts") == 1)
        try await fixture.database.databaseQueue.write { db in
            try db.execute(sql: "CREATE INDEX title_field ON documents(json_extract(metadata,'$.title')); CREATE VIEW titles AS SELECT metadata FROM documents")
        }
        let rebuilt = try await fixture.indexer.update(fingerprint: "v1", rebuild: true, evaluate: selectAll)
        #expect(rebuilt.evaluated == 1)
        #expect(try fixture.count("titles") == 1)
        let indexExists = try await fixture.database.databaseQueue.read {
            try Int.fetchOne($0, sql: "SELECT count(*) FROM sqlite_master WHERE name='title_field'")
        }
        #expect(indexExists == 1)
    }

    @Test func `full hashing catches same size same mtime edits and fingerprint invalidates cache`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "aaaa")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234)],
            ofItemAtPath: fixture.root.appendingPathComponent("notes/one.md").path)
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: selectAll)
        let file = fixture.root.appendingPathComponent("notes/one.md")
        let original = try #require(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        try fixture.write("notes/one.md", "bbbb")
        try FileManager.default.setAttributes([.modificationDate: original], ofItemAtPath: file.path)
        let statOnly = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(statOnly.cached == 1)
        let verified = try await fixture.indexer.update(fingerprint: "v1", verifyHashes: true, evaluate: selectAll)
        #expect(verified.evaluated == 1)
        let body = try await fixture.database.databaseQueue.read { try String.fetchOne($0, sql: "SELECT body FROM documents") }
        #expect(body == "bbbb")
        let invalidated = try await fixture.indexer.update(fingerprint: "v2", evaluate: selectAll)
        #expect(invalidated.evaluated == 1)
    }

    @Test func `mtime changes reevaluate even with identical bytes`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "same")
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: selectAll)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234)],
            ofItemAtPath: fixture.root.appendingPathComponent("notes/one.md").path)
        let report = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(report.evaluated == 1)
    }

    @Test func `negative assessments stay cached while overlapping memberships survive`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "Book Article")
        let book = IndexScope(kind: .type, path: "notes/", name: "Book")
        let article = IndexScope(kind: .type, path: "notes/", name: "Article")
        let evaluator: (IndexScope, String, String, Date) async throws -> IndexEvaluation = { scope, _, content, _ in
            IndexEvaluation(metadata: "{}", body: content,
                assessment: IndexAssessment(selected: content.contains(scope.name), status: "assessed"))
        }
        _ = try await fixture.indexer.update(adding: book, fingerprint: "v1", evaluate: evaluator)
        _ = try await fixture.indexer.update(adding: article, fingerprint: "v1", evaluate: evaluator)
        try fixture.write("notes/one.md", "Article")
        _ = try await fixture.indexer.update(fingerprint: "v1", evaluate: evaluator)
        #expect(try fixture.database.selectedPaths(scope: book).isEmpty)
        #expect(try fixture.database.selectedPaths(scope: article) == ["notes/one.md"])
        #expect(try fixture.count("assessments") == 2)
        let noop = try await fixture.indexer.update(fingerprint: "v1", evaluate: evaluator)
        #expect(noop.cached == 2)
        try fixture.write("notes/one.md", "Neither")
        _ = try await fixture.indexer.update(fingerprint: "v1", evaluate: evaluator)
        #expect(try fixture.count("documents") == 0)
        #expect(try fixture.count("documents_fts") == 0)
        #expect(try fixture.count("assessments") == 2)
    }

    @Test func `inaccessible scope retains prior entries and reports incomplete even during rebuild`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "original")
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: selectAll)
        // Missing mount/directory is an enumeration failure, not an empty collection.
        try FileManager.default.moveItem(at: fixture.root.appendingPathComponent("notes/"), to: fixture.root.appendingPathComponent("offline/"))
        let report = try await fixture.indexer.update(fingerprint: "v1", rebuild: true, evaluate: selectAll)
        #expect(report.errors.count == 1)
        #expect(try fixture.count("documents") == 1)
        #expect(try fixture.count("assessments") == 1)
        #expect(try fixture.database.selectedPaths().isEmpty)
        try FileManager.default.moveItem(at: fixture.root.appendingPathComponent("offline/"), to: fixture.root.appendingPathComponent("notes/"))
        _ = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(try fixture.database.selectedPaths() == ["notes/one.md"])
    }

    @Test func `unreadable nested directory prevents pruning accessible siblings`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/private/one.md", "private")
        try fixture.write("notes/two.md", "public")
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: selectAll)
        let directory = fixture.root.appendingPathComponent("notes/private/").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: directory)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory) }
        // Root can read mode-000 directories; CI containers run as root.
        if FileManager.default.isReadableFile(atPath: directory) { return }
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("notes/two.md"))
        let report = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(!report.errors.isEmpty)
        #expect(try fixture.count("assessments") == 2)
        #expect(try fixture.database.selectedPaths().isEmpty)
    }

    @Test func `invalid text replaces old data with an explicit failure and recovers`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "good")
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: selectAll)
        try Data([0xff, 0xfe]).write(to: fixture.root.appendingPathComponent("notes/one.md"))
        let report = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(report.errors.count == 1)
        #expect(try fixture.database.selectedPaths().isEmpty)
        #expect(try fixture.count("diagnostics") == 1)
        try fixture.write("notes/one.md", "recovered")
        _ = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(try fixture.database.selectedPaths().count == 1)
        #expect(try fixture.count("diagnostics") == 0)
    }

    @Test func `interruption and failed commit leave old rows unavailable and recover transactionally`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "original")
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: selectAll)
        do {
            _ = try await fixture.indexer.update(fingerprint: "v1", rebuild: true) { _, _, _, _ in throw CancellationError() }
            Issue.record("Expected cancellation")
        } catch is CancellationError {}
        #expect(try fixture.count("documents") == 1)
        #expect(try fixture.database.selectedPaths().isEmpty)
        do {
            _ = try await fixture.indexer.update(fingerprint: "v1", rebuild: true) { _, _, content, _ in
                IndexEvaluation(metadata: "invalid json", body: content, assessment: IndexAssessment(selected: true, status: "ok"))
            }
            Issue.record("Expected transaction failure")
        } catch is DatabaseError {}
        #expect(try fixture.count("documents_fts") == 1)
        #expect(try fixture.database.selectedPaths().isEmpty)
        let recovered = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(recovered.evaluated == 1)
        #expect(try fixture.database.selectedPaths().count == 1)
    }

    @Test func `migration from runtime probe database is idempotent and rejects a different root`() throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.database.prepareCollection(root: fixture.root.path)
        #expect(try fixture.count("grdb_migrations") == 1)
        #expect(throws: SQLiteIndexError.self) { try fixture.database.prepareCollection(root: "/different") }
    }

    @Test func `superseded scan cannot overwrite a newer generation`() throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(path: "notes/")
        let first = try fixture.database.begin(scopes: [scope])
        let second = try fixture.database.begin(scopes: [scope])
        try fixture.database.commit([], fingerprint: "v2", generation: second.generation)
        #expect(throws: SQLiteIndexError.self) { try fixture.database.commit([], fingerprint: "v1", generation: first.generation) }
    }

    @Test func `newer migration is refused without changing indexed data`() throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.database.databaseQueue.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations VALUES ('collection-v2')")
        }
        #expect(throws: SQLiteIndexError.self) { try fixture.database.prepareCollection(root: fixture.root.path) }
        #expect(try fixture.count("grdb_migrations") == 2)
    }

    @Test func `failed migration rolls back tables and can be retried`() throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        let database = try SQLiteIndexDatabase(path: fixture.root.appendingPathComponent("migration.sqlite").path)
        try database.databaseQueue.write { try $0.execute(sql: "CREATE TABLE scopes(sentinel TEXT); INSERT INTO scopes VALUES ('keep')") }
        #expect(throws: DatabaseError.self) { try database.prepareCollection(root: fixture.root.path) }
        let metadataTables = try database.databaseQueue.read {
            try Int.fetchOne($0, sql: "SELECT count(*) FROM sqlite_master WHERE name='index_metadata'")
        }
        #expect(metadataTables == 0)
        let sentinel = try database.databaseQueue.read { try String.fetchOne($0, sql: "SELECT sentinel FROM scopes") }
        #expect(sentinel == "keep")
        try database.databaseQueue.write { try $0.execute(sql: "DROP TABLE scopes") }
        try database.prepareCollection(root: fixture.root.path)
        #expect(try database.scopes().isEmpty)
    }

    @Test func `thousand document collection caches and rebuilds without duplicate FTS entries`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        for index in 0..<1000 { try fixture.write("notes/\(index).md", "# Document \(index)\n\nCollection search text.") }
        let initial = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: selectAll)
        #expect(initial.evaluated == 1000)
        let cached = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(cached.cached == 1000)
        _ = try await fixture.indexer.update(fingerprint: "v1", rebuild: true, evaluate: selectAll)
        #expect(try fixture.count("documents_fts") == 1000)
        let matches = try await fixture.database.databaseQueue.read {
            try Int.fetchOne($0, sql: "SELECT count(*) FROM documents_fts WHERE documents_fts MATCH 'search'")
        }
        #expect(matches == 1000)
    }
}
