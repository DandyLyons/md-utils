import Foundation
#if os(macOS)
import CoreServices
#endif

/// The sole C interoperability boundary for native recursive watching.
///
/// FSEvents is retained because it watches whole hierarchies and reports lost
/// events. Dispatch's Swift file-system source monitors a single open descriptor;
/// replacing FSEvents with per-file sources would scale with the corpus and need
/// separate watch registration/replacement recovery. Swift System has no equivalent
/// recursive event stream. All scheduling and refresh policy lives in Swift above
/// this adapter, which publishes through a bounded AsyncStream.
final class IndexNativeWatch {
    let events: AsyncStream<ContinuousClock.Instant>
    private let continuation: AsyncStream<ContinuousClock.Instant>.Continuation
    #if os(macOS)
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "md-utils.index-watch")
    private let callback: IndexWatchEventSink
    #endif

    init(root: URL, databasePath: String, additionalDirectories: [URL]) throws {
        let channel = AsyncStream<ContinuousClock.Instant>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = channel.stream
        continuation = channel.continuation
        #if os(macOS)
        callback = IndexWatchEventSink(continuation: continuation,
            exclusions: IndexCacheExclusions(root: root, databasePath: databasePath))
        // The adapter owns the callback until stop/invalidate and the queue drain
        // complete. No Swift reference crosses the C context without that lifetime.
        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let paths = Set(([root] + additionalDirectories).map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        guard let created = FSEventStreamCreate(nil, { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let callback = Unmanaged<IndexWatchEventSink>.fromOpaque(info).takeUnretainedValue()
            let paths = rawPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            for index in 0..<count {
                let ambiguous = flags[index] & UInt32(kFSEventStreamEventFlagMustScanSubDirs
                    | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                    | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagEventIdsWrapped) != 0
                let path = String(cString: paths[index])
                if ambiguous || !callback.exclusions.contains(path) {
                    callback.receive(path: path, requiresReconciliation: ambiguous)
                    break
                }
            }
        }, &context, Array(paths) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1, UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)) else {
            throw SQLiteIndexError(message: "Cannot create native index watch stream.")
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            queue.sync {}
            FSEventStreamRelease(created)
            throw SQLiteIndexError(message: "Cannot start native index watch stream.")
        }
        stream = created
        #else
        throw SQLiteIndexError(message: "Native index watch is currently supported on macOS only. Run index update on this platform.")
        #endif
    }

    deinit {
        #if os(macOS)
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            queue.sync {}
            FSEventStreamRelease(stream)
        }
        #endif
        continuation.finish()
    }
}
