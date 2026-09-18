import Foundation

/// Paths owned by the index, shared by discovery and native event filtering.
public struct IndexCacheExclusions: Sendable {
    private let files: Set<String>
    private let recovery: String

    public init(root: URL, databasePath: String) {
        let cache = URL(fileURLWithPath: databasePath).standardizedFileURL.resolvingSymlinksInPath().path
        files = Set([cache, cache + "-wal", cache + "-shm", cache + "-journal"])
        recovery = root.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent(".md-utils/rebuild").path
    }

    public func contains(_ path: String) -> Bool {
        files.contains(path) || path == recovery || path.hasPrefix(recovery + "/")
    }
}

/// Actor-isolated debounce state. Bursts retain no per-file event backlog.
actor IndexWatchState {
    private var firstChange: ContinuousClock.Instant?
    private var lastChange: ContinuousClock.Instant?

    func changed(at time: ContinuousClock.Instant) {
        if firstChange == nil { firstChange = time }
        lastChange = time
    }

    func takeDue(at time: ContinuousClock.Instant, debounce: Duration) -> Bool {
        guard let firstChange, let lastChange,
            lastChange.duration(to: time) >= debounce
                || firstChange.duration(to: time) >= max(.seconds(1), debounce * 4) else { return false }
        self.firstChange = nil
        self.lastChange = nil
        return true
    }
}

/// Loss notifications always win over cache filtering, because their paths do
/// not describe the full set of changes the operating system could not deliver.
final class IndexWatchEventSink: Sendable {
    let continuation: AsyncStream<ContinuousClock.Instant>.Continuation
    let exclusions: IndexCacheExclusions

    init(continuation: AsyncStream<ContinuousClock.Instant>.Continuation, exclusions: IndexCacheExclusions) {
        self.continuation = continuation
        self.exclusions = exclusions
    }

    func receive(path: String, requiresReconciliation: Bool) {
        if requiresReconciliation || !exclusions.contains(path) { continuation.yield(.now) }
    }
}

/// Native recursive notifications with conservative reconciliation of all saved scopes.
///
/// Subscribe before initial refresh to avoid a startup gap. Each notification batch
/// causes the normal bounded incremental refresh; event paths are never evidence of
/// deletion. A periodic refresh covers dropped events and temporarily offline roots.
/// macOS uses FSEvents. Other platforms fail explicitly; callers can run normal updates.
public final class IndexWatcher {
    private let state = IndexWatchState()
    private let notifications: IndexNativeWatch

    public init(root: URL, databasePath: String, additionalDirectories: [URL] = []) throws {
        notifications = try IndexNativeWatch(root: root, databasePath: databasePath,
            additionalDirectories: additionalDirectories)
    }

    /// Initial failures propagate; later failures are reported and retried at the
    /// reconciliation interval or next change. Cancellation releases the native stream
    /// when the caller drops this watcher and prevents staged publication.
    public func run(debounce: Duration = .milliseconds(300), reconcileInterval: Duration = .seconds(30),
        refresh: () async throws -> Void, ready: () -> Void = {},
        reportError: (any Error) -> Void = { _ in }) async throws {
        guard debounce > .zero, reconcileInterval > .zero else {
            throw SQLiteIndexError(message: "Watch intervals must be positive.")
        }
        // One structured consumer bridges synchronous native callbacks to actor
        // state. The stream buffers one timestamp, never a task or list per event.
        let events = notifications.events
        let state = state
        async let _: Void = Self.observe(events, state: state)
        let clock = ContinuousClock()
        try Task.checkCancellation()
        try await refresh()
        ready()
        var lastRefresh = clock.now
        while true {
            try await clock.sleep(for: .milliseconds(100))
            let now = clock.now
            let changed = await state.takeDue(at: now, debounce: debounce)
            guard changed || lastRefresh.duration(to: now) >= reconcileInterval else { continue }
            do { try await refresh() }
            catch is CancellationError { throw CancellationError() }
            catch { reportError(error) }
            lastRefresh = clock.now
        }
    }

    private static func observe(_ events: AsyncStream<ContinuousClock.Instant>, state: IndexWatchState) async {
        for await time in events { await state.changed(at: time) }
    }
}
