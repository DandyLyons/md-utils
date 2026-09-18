import Foundation
import Testing
@testable import MarkdownUtilitiesIndex

@Suite struct IndexWatchTests {
    @Test func `excluded sidecar disappearing during discovery does not fail or skip source siblings`() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/watch-sidecar-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sidecar = root.appendingPathComponent("cache.sqlite-journal")
        try Data().write(to: sidecar)
        try Data("source".utf8).write(to: root.appendingPathComponent("source.md"))
        var paths: [String] = []
        var removed = false
        try IndexDirectoryTraversal.visit(root, isExcluded: { path in
            guard path == sidecar.path else { return false }
            do {
                try FileManager.default.removeItem(at: sidecar)
                removed = true
            } catch { Issue.record("Cannot simulate disappearing journal: \(error)") }
            return true
        }, includeNonMarkdown: true) { paths.append($0.lastPathComponent) }
        #expect(removed)
        #expect(paths == ["source.md"])
    }

    @Test func `debounce coalesces bursts without starving continuous writers`() async {
        let state = IndexWatchState()
        let start = ContinuousClock.now
        await state.changed(at: start.advanced(by: .seconds(1)))
        await state.changed(at: start.advanced(by: .milliseconds(1_200)))
        #expect(await !state.takeDue(at: start.advanced(by: .milliseconds(1_400)), debounce: .milliseconds(300)))
        #expect(await state.takeDue(at: start.advanced(by: .milliseconds(1_600)), debounce: .milliseconds(300)))
        #expect(await !state.takeDue(at: start.advanced(by: .seconds(2)), debounce: .milliseconds(300)))
        await state.changed(at: start.advanced(by: .seconds(3)))
        await state.changed(at: start.advanced(by: .milliseconds(4_300)))
        #expect(await state.takeDue(at: start.advanced(by: .milliseconds(4_300)), debounce: .milliseconds(300)))
        await state.changed(at: start.advanced(by: .seconds(5)))
        #expect(await state.takeDue(at: start.advanced(by: .seconds(6)), debounce: .milliseconds(300)))
    }

    @Test func `exclusions cover custom cache sidecars and recovery descendants only`() {
        let exclusions = IndexCacheExclusions(root: URL(fileURLWithPath: "/project/"), databasePath: "/project/cache.db")
        for path in ["/project/cache.db", "/project/cache.db-wal", "/project/cache.db-shm",
            "/project/cache.db-journal", "/project/.md-utils/rebuild", "/project/.md-utils/rebuild/copy/index.sqlite"] {
            #expect(exclusions.contains(path))
        }
        for path in ["/project/cache.db.md", "/project/.md-utils/types/book.json", "/project/.md-utils/rebuild-other/a.md"] {
            #expect(!exclusions.contains(path))
        }
    }

    #if os(macOS)
    @Test func `failed initial reconciliation never reports ready or starts retries`() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/watch-initial-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = try IndexWatcher(root: root, databasePath: root.appendingPathComponent("cache.sqlite").path)
        var ready = false
        var retried = false
        await #expect(throws: SQLiteIndexError.self) {
            try await watcher.run(refresh: { throw SQLiteIndexError(message: "initial failure") },
                ready: { ready = true }, reportError: { _ in retried = true })
        }
        #expect(!ready)
        #expect(!retried)
    }

    @Test func `loss overrides exclusions and event bursts occupy one stream slot`() async {
        for (path, lost, expected) in [
            ("/project/cache.db-wal", false, 0),
            ("/project/cache.db-wal", true, 1),
            ("/project/.md-utils/types/book.json", false, 1),
        ] {
            let (events, continuation) = AsyncStream<ContinuousClock.Instant>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let sink = IndexWatchEventSink(continuation: continuation,
                exclusions: IndexCacheExclusions(root: URL(fileURLWithPath: "/project/"), databasePath: "/project/cache.db"))
            for _ in 0..<10_000 { sink.receive(path: path, requiresReconciliation: lost) }
            continuation.finish()
            var count = 0
            for await _ in events { count += 1 }
            #expect(count == expected)
        }
    }

    @Test(arguments: [IndexBodyMode.metadataOnly, .fts])
    func `native changes reconcile creation edits atomic replacement moves and deletion`(mode: IndexBodyMode) async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/watch-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let run = Task {
            let database = try SQLiteIndexDatabase(path: root.appendingPathComponent("cache.sqlite").path)
            let indexer = try CollectionIndexer(database: database, root: root)
            try database.setBodyMode(mode)
            let watcher = try IndexWatcher(root: root, databasePath: database.path)
            let file = root.appendingPathComponent("one.md")
            let moved = root.appendingPathComponent("two.md")
            var phase = 0
            do {
                try await watcher.run(debounce: .milliseconds(100), reconcileInterval: .seconds(60), refresh: {
                    let report = try await indexer.update(adding: IndexScope(includeNonMarkdown: true),
                        fingerprint: "watch", verifyHashes: true) { _, _, content, _ in
                        let expected = [1: "created", 2: "edited", 3: "atomic", 4: "atomic"]
                        #expect(content == expected[phase])
                        return IndexEvaluation(metadata: "{}", body: content,
                            assessment: IndexAssessment(selected: true, status: "selected"))
                    }
                    #expect(report.errors.isEmpty)
                    #expect(try database.storagePolicy().bodyMode == mode)
                    switch phase {
                    case 0:
                        #expect(try database.selectedPaths().isEmpty)
                        try Data("created".utf8).write(to: file)
                    case 1:
                        #expect(try database.selectedPaths() == ["one.md"])
                        try Data("edited".utf8).write(to: file)
                    case 2:
                        try Data("atomic".utf8).write(to: file, options: .atomic)
                    case 3:
                        try FileManager.default.moveItem(at: file, to: moved)
                    case 4:
                        #expect(try database.selectedPaths() == ["two.md"])
                        try FileManager.default.removeItem(at: moved)
                    default:
                        #expect(try database.selectedPaths().isEmpty)
                        throw CancellationError()
                    }
                    phase += 1
                }, reportError: { error in Issue.record("Unexpected watch failure: \(error)") })
            } catch is CancellationError {}
            return phase
        }
        let deadline = Task {
            try await Task.sleep(for: .seconds(15))
            run.cancel()
        }
        defer { deadline.cancel(); run.cancel() }
        #expect(try await run.value == 5)
    }

    @Test func `periodic reconciliation retries failures without filesystem events`() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tmp/watch-periodic-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = try IndexWatcher(root: root, databasePath: root.appendingPathComponent("cache.sqlite").path)
        var calls = 0
        var errors = 0
        var ready = false
        do {
            try await watcher.run(reconcileInterval: .milliseconds(100), refresh: {
                calls += 1
                if calls == 2 { throw SQLiteIndexError(message: "competing writer") }
                if calls == 3 { throw CancellationError() }
                #expect(!ready)
            }, ready: { ready = true }, reportError: { _ in errors += 1 })
        } catch is CancellationError {}
        #expect(ready)
        #expect(calls == 3)
        #expect(errors == 1)
    }
    #else
    @Test func `unsupported platforms explicitly refuse native watching`() {
        #expect(throws: SQLiteIndexError.self) {
            try IndexWatcher(root: URL(fileURLWithPath: "/project/"), databasePath: "/project/cache.sqlite")
        }
    }
    #endif
}
