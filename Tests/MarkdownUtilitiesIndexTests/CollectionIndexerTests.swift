import Foundation
import GRDB
import Testing
@testable import MarkdownUtilitiesIndex

private struct IndexFixture {
    let root: URL
    let database: SQLiteIndexDatabase
    let indexer: CollectionIndexer

    init(bodyMode: IndexBodyMode = .metadataOnly) throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/index-tests/\(UUID().uuidString)/", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes/"), withIntermediateDirectories: true)
        database = try SQLiteIndexDatabase(path: root.appendingPathComponent("index.sqlite").path)
        indexer = try CollectionIndexer(database: database, root: root)
        if bodyMode != .metadataOnly { try database.setBodyMode(bodyMode) }
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
    @Test func `new caches are metadata only and expose ordinary JSON without body surfaces`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "private body")
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1") {
            _, _, content, _ in
            IndexEvaluation(metadata: "{\"title\":\"One\",\"nested\":{\"body\":true}}", body: content,
                assessment: IndexAssessment(selected: true, status: "selected"))
        }
        let policy = try fixture.database.storagePolicy()
        #expect(policy.bodyMode == .metadataOnly)
        #expect(try fixture.database.query("SELECT metadata FROM current_documents").rows
            == [[.text("{\"title\":\"One\",\"nested\":{\"body\":true}}")]])
        #expect(try fixture.database.query("SELECT json_extract(metadata,'$.nested.body') FROM current_documents").rows
            == [[.integer(1)]])
        let rawBody = try await fixture.database.databaseQueue.read {
            try String.fetchOne($0, sql: "SELECT body FROM documents")
        }
        #expect(rawBody == nil)
        let objects = try fixture.database.query("SELECT name FROM sqlite_master WHERE name='documents_fts'")
        #expect(objects.rows.isEmpty)
        let columns = try fixture.database.query("SELECT name FROM pragma_table_info('current_documents') ORDER BY cid")
        #expect(columns.rows == [[.text("path")], [.text("metadata")]])
        do {
            _ = try fixture.database.query("SELECT body FROM current_documents")
            Issue.record("Expected an explicit metadata-only body error")
        } catch let error as SQLiteIndexError {
            #expect(error.description.contains("metadata-only"))
        }
        #expect(throws: SQLiteIndexError.self) {
            try fixture.database.query("SELECT \"body\" FROM documents")
        }
        do {
            _ = try fixture.database.query("SELECT * FROM documents_fts WHERE documents_fts MATCH 'private'")
            Issue.record("Expected an explicit metadata-only FTS error")
        } catch let error as SQLiteIndexError {
            #expect(error.description.contains("metadata-only"))
        }
        let rawType = try fixture.database.query("SELECT typeof(metadata) FROM documents")
        #expect(rawType.rows == [[.text(policy.metadataEncoding == .jsonb ? "blob" : "text")]])
    }

    @Test func `opt in search uses one external content body and disable removes it`() async throws {
        let fixture = try IndexFixture(bodyMode: .fts)
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "searchable original")
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: selectAll)
        let definition = try fixture.database.query("SELECT sql FROM sqlite_master WHERE name='documents_fts'")
        #expect(definition.rows.first?.first == .text("CREATE VIRTUAL TABLE documents_fts USING fts5(body, content='documents', content_rowid='rowid')"))
        #expect(try fixture.database.query("SELECT body FROM documents").rows == [[.text("searchable original")]])
        #expect(throws: SQLiteIndexError.self) {
            try fixture.database.streamQuery("SELECT body FROM current_documents",
                limits: IndexQueryLimits(rows: 10, bytes: 100, valueBytes: 5)) { _ in }
        }
        #expect(try fixture.database.query("SELECT count(*) FROM documents_fts WHERE documents_fts MATCH 'searchable'").rows
            == [[.integer(1)]])
        let triggers = try fixture.database.query("SELECT sql FROM sqlite_master WHERE type='trigger' AND name LIKE 'documents_fts_update%' ORDER BY name")
        #expect(triggers.rows.allSatisfy { row in
            guard case .text(let sql) = row[0] else { return false }
            return sql.contains("UPDATE OF body") && sql.contains("old.body IS NOT new.body")
        })
        try fixture.database.setBodyMode(.metadataOnly)
        let removedBody = try await fixture.database.databaseQueue.read {
            try String.fetchOne($0, sql: "SELECT body FROM documents")
        }
        #expect(removedBody == nil)
        #expect(try fixture.database.query("SELECT name FROM sqlite_master WHERE name='documents_fts'").rows.isEmpty)
    }

    @Test func `streamed queries enforce independent bounds and cancellation`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "one")
        try fixture.write("notes/two.md", "two")
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: selectAll)
        var rows: [[IndexQueryValue]] = []
        let summary = try fixture.database.streamQuery("SELECT path FROM current_documents ORDER BY path",
            limits: IndexQueryLimits(rows: 1, bytes: 100, valueBytes: 100)) { rows.append($0) }
        #expect(rows == [[.text("notes/one.md")]])
        #expect(summary.truncated)
        #expect(summary.rowCount == 1)
        var byteBounded: [[IndexQueryValue]] = []
        let byteSummary = try fixture.database.streamQuery("SELECT path FROM current_documents ORDER BY path",
            limits: IndexQueryLimits(rows: 10, bytes: 13, valueBytes: 13)) { byteBounded.append($0) }
        #expect(byteBounded == [[.text("notes/one.md")]])
        #expect(byteSummary.truncated)
        #expect(throws: SQLiteIndexError.self) {
            try fixture.database.streamQuery("SELECT path FROM current_documents",
                limits: IndexQueryLimits(rows: 10, bytes: 100, valueBytes: 3)) { _ in }
        }
        var delivered = 0
        #expect(throws: CancellationError.self) {
            try fixture.database.streamQuery("SELECT path FROM current_documents ORDER BY path",
                shouldCancel: { delivered == 1 }) { _ in delivered += 1 }
        }
        #expect(delivered == 1)
    }

    @Test func `source read limit records an explicit retryable failure`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "three")
        var called = false
        let report = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1",
            limits: IndexRefreshLimits(fileBytes: 3)) { _, _, _, _ in
            called = true
            return IndexEvaluation(metadata: "{}", body: "",
                assessment: IndexAssessment(selected: true, status: "selected"))
        }
        #expect(!called)
        #expect(report.errors.contains { $0.contains("3-byte refresh limit") })
        #expect(try fixture.database.selectedPaths().isEmpty)
        #expect(!(try fixture.database.freshness().isCurrent))
        #expect(try fixture.count("diagnostics") == 1)
    }

    @Test func `overlapping scopes share one extraction call`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "one")
        let first = IndexScope(kind: .type, path: "notes/", name: "First")
        let second = IndexScope(kind: .type, path: "notes/", name: "Second")
        _ = try await fixture.indexer.update(adding: first, fingerprint: "v1", evaluate: selectAll)
        var calls = 0
        let report = try await fixture.indexer.updateMany(adding: second, fingerprint: "v2", rebuild: true) {
            scopes, _, content, _ in
            calls += 1
            return Dictionary(uniqueKeysWithValues: scopes.map { scope in
                (scope.id, IndexEvaluation(metadata: "{}", body: content,
                    assessment: IndexAssessment(selected: true, status: "conforms")))
            })
        }
        #expect(calls == 1)
        #expect(report.evaluated == 2)
        #expect(try fixture.count("assessments") == 2)
    }

    @Test func `creation refresh edits additions deletions and rebuild preserve declared SQL`() async throws {
        let fixture = try IndexFixture(bodyMode: .fts)
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
        let fixture = try IndexFixture(bodyMode: .fts)
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
        let fixture = try IndexFixture(bodyMode: .fts)
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
        #expect(!(try fixture.database.freshness().isCurrent))
        #expect(try fixture.count("diagnostics") == 1)
        try fixture.write("notes/one.md", "recovered")
        _ = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(try fixture.database.selectedPaths().count == 1)
        #expect(try fixture.count("diagnostics") == 0)
    }

    @Test func `interruption and failed commit leave old rows unavailable and recover transactionally`() async throws {
        let fixture = try IndexFixture(bodyMode: .fts)
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
        #expect(try fixture.count("grdb_migrations") == 4)
        #expect(throws: SQLiteIndexError.self) { try fixture.database.prepareCollection(root: "/different") }
    }

    @Test func `legacy body cache migrates to external FTS and JSON text policy`() throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        let path = fixture.root.appendingPathComponent("legacy.sqlite").path
        let database = try SQLiteIndexDatabase(path: path)
        let scope = IndexScope(path: "notes/")
        let definition = String(decoding: try JSONEncoder().encode(scope), as: UTF8.self)
        try database.databaseQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES('collection-v1'),('collection-v2-query-schema');
                CREATE TABLE index_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                INSERT INTO index_metadata VALUES('generation','1'),('root',?);
                CREATE TABLE scopes(id TEXT PRIMARY KEY, definition TEXT NOT NULL,
                  state TEXT NOT NULL, error TEXT, fingerprint TEXT NOT NULL DEFAULT '');
                CREATE TABLE files(path TEXT PRIMARY KEY, mtime REAL NOT NULL, size INTEGER NOT NULL,
                  hash TEXT NOT NULL, state TEXT NOT NULL);
                CREATE TABLE assessments(scope_id TEXT NOT NULL REFERENCES scopes(id) ON DELETE CASCADE,
                  path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
                  selected INTEGER NOT NULL, status TEXT NOT NULL,
                  detail TEXT NOT NULL CHECK(json_valid(detail)), PRIMARY KEY(scope_id,path));
                CREATE TABLE diagnostics(scope_id TEXT NOT NULL,path TEXT NOT NULL,category TEXT NOT NULL,
                  severity TEXT NOT NULL,code TEXT NOT NULL,location TEXT NOT NULL,message TEXT NOT NULL,
                  FOREIGN KEY(scope_id,path) REFERENCES assessments(scope_id,path) ON DELETE CASCADE);
                CREATE TABLE documents(path TEXT PRIMARY KEY REFERENCES files(path) ON DELETE CASCADE,
                  metadata TEXT NOT NULL CHECK(json_valid(metadata)),body TEXT NOT NULL);
                CREATE INDEX assessments_path ON assessments(path);
                CREATE VIEW current_documents AS SELECT d.path,d.metadata,d.body FROM documents d JOIN files f USING(path)
                  WHERE f.state='ok' AND EXISTS(SELECT 1 FROM assessments a JOIN scopes s ON s.id=a.scope_id
                    WHERE a.path=d.path AND a.selected=1 AND s.state='complete');
                CREATE VIEW titles AS SELECT json_extract(metadata,'$.title') AS title FROM documents;
                CREATE VIRTUAL TABLE documents_fts USING fts5(path UNINDEXED,body);
                CREATE TABLE index_fields(name TEXT PRIMARY KEY,json_path TEXT NOT NULL UNIQUE,column_name TEXT NOT NULL UNIQUE);
                CREATE TABLE type_views(type_name TEXT PRIMARY KEY,view_name TEXT NOT NULL UNIQUE);
                INSERT INTO scopes VALUES(?,?,'complete',NULL,'v1');
                INSERT INTO files VALUES('notes/one.md',1,4,'hash','ok');
                INSERT INTO assessments VALUES(?,'notes/one.md',1,'selected','{}');
                INSERT INTO documents VALUES('notes/one.md','{"title":"One"}','body search');
                INSERT INTO documents_fts VALUES('notes/one.md','body search');
                """, arguments: [fixture.root.path, scope.id, definition, scope.id])
        }
        try database.prepareCollection(root: fixture.root.path)
        #expect(try database.storagePolicy() == IndexStoragePolicy(bodyMode: .fts, metadataEncoding: .text))
        #expect(try database.query("SELECT metadata,body FROM current_documents").rows
            == [[.text("{\"title\":\"One\"}"), .text("body search")]])
        #expect(try database.query("SELECT count(*) FROM documents_fts WHERE documents_fts MATCH 'search'").rows
            == [[.integer(1)]])
        #expect(try database.query("SELECT title FROM titles").rows == [[.text("One")]])
        #expect(try database.databaseQueue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM grdb_migrations") } == 4)
    }

    @Test func `superseded scan cannot overwrite a newer generation`() throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        let scope = IndexScope(path: "notes/")
        let first = try fixture.database.beginStagedRefresh(scopes: [scope], fingerprint: "v1")
        let second = try fixture.database.beginStagedRefresh(scopes: [scope], fingerprint: "v2")
        try fixture.database.commitStagedRefresh(scopes: [scope], errors: [:], fingerprint: "v2", generation: second)
        #expect(throws: SQLiteIndexError.self) {
            try fixture.database.commitStagedRefresh(scopes: [scope], errors: [:], fingerprint: "v1", generation: first)
        }
    }

    @Test func `newer migration is refused without changing indexed data`() throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.database.databaseQueue.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations VALUES ('collection-v999')")
        }
        #expect(throws: SQLiteIndexError.self) { try fixture.database.prepareCollection(root: fixture.root.path) }
        #expect(try fixture.count("grdb_migrations") == 5)
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
        let fixture = try IndexFixture(bodyMode: .fts)
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

    @Test func `bounded queries preserve SQLite types and reject mutations`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "first")
        try fixture.write("notes/two.md", "second")
        _ = try await fixture.indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1") {
            _, path, content, _ in
            let number = path == "notes/one.md" ? 1 : 2
            return IndexEvaluation(metadata: "{\"number\":\(number),\"nothing\":null}", body: content,
                assessment: IndexAssessment(selected: true, status: "selected"))
        }

        let result = try fixture.database.query("SELECT path,json_extract(metadata,'$.number'),json_extract(metadata,'$.nothing') FROM current_documents ORDER BY path", limit: 1)
        #expect(result.columns == ["path", "json_extract(metadata,'$.number')", "json_extract(metadata,'$.nothing')"])
        #expect(result.rows == [[.text("notes/one.md"), .integer(1), .null]])
        #expect(result.truncated)
        do {
            _ = try fixture.database.query("DELETE FROM documents")
            Issue.record("Expected SQL mutation rejection")
        } catch let error as SQLiteIndexError {
            #expect(error.description.contains("SQL mutations are not allowed"))
        }
        #expect(throws: SQLiteIndexError.self) { try fixture.database.query("SELECT 1; SELECT 2") }
        #expect(try fixture.count("documents") == 2)
        let freshness = try fixture.database.freshness()
        #expect(freshness.isCurrent)
        #expect(freshness.lastStartedAt != nil)
        #expect(freshness.lastCompletedAt != nil)
    }

    @Test func `managed field indexes match documented expressions and type view projections`() async throws {
        let fixture = try IndexFixture(bodyMode: .fts)
        defer { fixture.remove() }
        try fixture.write("notes/one.md", "searchable original")
        let book = IndexScope(kind: .type, path: "notes/", name: "Book")
        _ = try await fixture.indexer.update(adding: book, fingerprint: "v1") { _, _, content, _ in
            IndexEvaluation(metadata: "{\"status\":\"draft\",\"tags\":[\"swift\",\"sqlite\"]}", body: content,
                assessment: IndexAssessment(selected: true, status: "conforms"))
        }
        let status = try fixture.database.addField(jsonPath: "$.status")
        let tags = try fixture.database.addField(jsonPath: "$.tags")
        #expect(throws: SQLiteIndexError.self) { try fixture.database.addField(jsonPath: "$.path") }
        #expect(status.columnName == "status")
        #expect(status.queryExpression == "json_extract(metadata, '$.status')")
        #expect(tags.columnName == "tags")

        let plan = try fixture.database.query("EXPLAIN QUERY PLAN SELECT path FROM documents WHERE json_extract(metadata, '$.status')='draft'")
        #expect(plan.rows.flatMap { $0 }.contains { value in
            if case .text(let detail) = value { return detail.contains(status.name) }
            return false
        })
        let view = try fixture.database.query("SELECT path,status,tags FROM type_book")
        #expect(view.rows == [[.text("notes/one.md"), .text("draft"), .text("[\"swift\",\"sqlite\"]")]])
        #expect(try fixture.database.fields() == [status, tags].sorted { $0.columnName < $1.columnName })

        try fixture.write("notes/one.md", "searchable changed")
        _ = try await fixture.indexer.update(fingerprint: "v1") { _, _, content, _ in
            IndexEvaluation(metadata: "{\"status\":\"published\",\"tags\":[\"swift\"]}", body: content,
                assessment: IndexAssessment(selected: true, status: "conforms"))
        }
        #expect(try fixture.database.query("SELECT count(*) FROM documents_fts WHERE documents_fts MATCH 'changed'").rows == [[.integer(1)]])
        #expect(try fixture.database.query("SELECT status FROM type_book").rows == [[.text("published")]])
        #expect(try fixture.database.removeField("$.tags"))
        #expect(try fixture.database.fields() == [status])
        #expect(try fixture.database.query("SELECT * FROM pragma_table_info('type_book') WHERE name='tags'").rows.isEmpty)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("notes/one.md"))
        _ = try await fixture.indexer.update(fingerprint: "v1", evaluate: selectAll)
        #expect(try fixture.database.query("SELECT count(*) FROM documents_fts").rows == [[.integer(0)]])
        #expect(try fixture.database.query("SELECT count(*) FROM type_book").rows == [[.integer(0)]])
    }

    @Test func `type views overlap and use only complete successful memberships`() async throws {
        let fixture = try IndexFixture()
        defer { fixture.remove() }
        try fixture.write("notes/shared.md", "shared")
        let book = IndexScope(kind: .type, path: "notes/", name: "Book")
        let article = IndexScope(kind: .type, path: "notes/", name: "Article")
        _ = try await fixture.indexer.update(adding: book, fingerprint: "v1") { _, _, content, _ in
            IndexEvaluation(metadata: "{}", body: content,
                assessment: IndexAssessment(selected: true, status: "conforms"))
        }
        _ = try await fixture.indexer.update(adding: article, fingerprint: "v1") { _, _, content, _ in
            IndexEvaluation(metadata: "{}", body: content,
                assessment: IndexAssessment(selected: true, status: "conforms"))
        }
        #expect(try fixture.database.query("SELECT path FROM type_book").rows == [[.text("notes/shared.md")]])
        #expect(try fixture.database.query("SELECT path FROM type_article").rows == [[.text("notes/shared.md")]])
        let schema = try fixture.database.query("SELECT sql FROM sqlite_master WHERE name IN ('type_book','type_article') ORDER BY name")
        #expect(schema.rows.count == 2)
        #expect(schema.rows.allSatisfy { row in
            guard case .text(let sql) = row[0] else { return false }
            return sql.contains("json_extract") && !sql.contains("md_utils")
        })
        try fixture.database.invalidate(message: "configuration unavailable")
        #expect(try fixture.database.query("SELECT count(*) FROM type_book").rows == [[.integer(0)]])
        #expect(!(try fixture.database.freshness().isCurrent))
    }
}
