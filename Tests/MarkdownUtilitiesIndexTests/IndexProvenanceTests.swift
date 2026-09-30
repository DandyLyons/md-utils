import Foundation
import Testing
import MarkdownUtilitiesCore
@testable import MarkdownUtilitiesIndex

@Suite struct IndexProvenanceTests {
    @Test func observationsDistinguishVerifiedReadsAndSurviveOnlyIncrementalUpdates() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tmp/provenance-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.md")
        try Data("body".utf8).write(to: file)
        let db = try SQLiteIndexDatabase(path: root.appendingPathComponent("index.sqlite").path)
        let indexer = try CollectionIndexer(database: db, root: root)
        let evaluate: (IndexScope, String, String, Date) async throws -> IndexEvaluation = { _, _, content, _ in
            .init(metadata: "{}", body: content, assessment: .init(selected: true, status: "selected"))
        }
        _ = try await indexer.update(adding: IndexScope(), fingerprint: "v1", evaluate: evaluate)
        let first = try db.provenance(paths: ["a.md"])
        #expect(first.observations.first?.verified == true)
        #expect(first.observations.first?.completeScan == true)
        _ = try await indexer.update(fingerprint: "v1", evaluate: evaluate)
        #expect(try db.provenance(paths: ["a.md"]).observations.first?.verified == false)
        _ = try await indexer.update(fingerprint: "v1", verifyHashes: true, evaluate: evaluate)
        #expect(try db.provenance(paths: ["a.md"]).observations.first?.verified == true)
        let event = ManagedDocumentEvent(id: "operation", kind: .create, path: "a.md", revision: "hash", observedAt: 1)
        try db.recordManagedEvent(event)
        try db.recordManagedEvent(event)
        #expect(try db.provenance(paths: ["a.md"]).events.count == 1)
        try FileManager.default.moveItem(at: file, to: root.appendingPathComponent("b.md"))
        _ = try await indexer.update(fingerprint: "v1", evaluate: evaluate)
        #expect(try db.provenance(paths: ["a.md"]).observations.first?.absent == true)
        try Data("body".utf8).write(to: file)
        _ = try await indexer.update(fingerprint: "v1", evaluate: evaluate)
        #expect(try db.provenance(paths: ["a.md"]).observations.first?.historyGap == true)
        _ = try await indexer.update(fingerprint: "v1", rebuild: true, evaluate: evaluate)
        let rebuilt = try db.provenance(paths: ["a.md"])
        #expect(rebuilt.epoch != first.epoch)
        #expect(rebuilt.events.isEmpty)
        #expect(rebuilt.observations.first?.historyGap == false)
    }

    @Test func boundedEventsReportPruningAndQueriesReportTruncation() throws {
        let db = try SQLiteIndexDatabase(path: ":memory:")
        try db.prepareCollection(root: "/project")
        for index in 0..<10_002 {
            try db.recordManagedEvent(.init(id: String(index), kind: .create, path: "a.md", revision: "hash", observedAt: Double(index)))
        }
        let evidence = try db.provenance(paths: ["a.md"], limit: 2)
        #expect(evidence.historyPruned)
        #expect(evidence.truncated)
        #expect(evidence.events.count == 2)
    }

    @Test func interruptedRefreshDoesNotPublishAndIncompleteScansCannotProveAbsence() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tmp/provenance-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes/"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("body".utf8).write(to: root.appendingPathComponent("notes/a.md"))
        let db = try SQLiteIndexDatabase(path: root.appendingPathComponent("index.sqlite").path)
        let indexer = try CollectionIndexer(database: db, root: root)
        let evaluate: (IndexScope, String, String, Date) async throws -> IndexEvaluation = { _, _, content, _ in
            .init(metadata: "{}", body: content, assessment: .init(selected: true, status: "selected"))
        }
        _ = try await indexer.update(adding: IndexScope(path: "notes/"), fingerprint: "v1", evaluate: evaluate)
        let original = try db.provenance(paths: ["notes/a.md"])
        await #expect(throws: CancellationError.self) {
            _ = try await indexer.update(fingerprint: "v2") { _, _, _, _ in throw CancellationError() }
        }
        #expect(try db.provenance(paths: ["notes/a.md"]) == original)
        try FileManager.default.moveItem(at: root.appendingPathComponent("notes/"), to: root.appendingPathComponent("offline/"))
        let report = try await indexer.update(fingerprint: "v2", evaluate: evaluate)
        #expect(!report.errors.isEmpty)
        #expect(try db.provenance(paths: ["notes/a.md"]).observations.first?.absent == false)
    }
}
