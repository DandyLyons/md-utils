import ArgumentParser
import Foundation
import MarkdownUtilitiesIndex
import UnixSignals

extension CLIEntry.Index {
    /// Keeps saved scopes current through native changes and bounded reconciliation.
    struct Watch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Watch files and reconcile saved scopes (macOS)")
        @Argument(help: "Directory to register, such as ./notes/; omit to watch saved scopes") var directory: String?
        @OptionGroup var options: IndexOptions
        @Option(help: "Quiet time in seconds before refreshing a burst of changes") var debounce: Double = 0.3
        @Option(help: "Maximum idle seconds between recovery reconciliations") var reconcileInterval: Double = 30

        mutating func validate() throws {
            guard debounce.isFinite, debounce > 0, debounce < Double(Int64.max) / 4,
                reconcileInterval.isFinite, reconcileInterval > 0, reconcileInterval < Double(Int64.max) / 4 else {
                throw ValidationError("Watch intervals must be finite, positive, and representable as Swift durations.")
            }
        }

        mutating func run() async throws {
            let options = options
            let directory = directory
            let debounce = Duration.seconds(debounce)
            let reconcileInterval = Duration.seconds(reconcileInterval)
            // Await signal registration before starting work. Both children belong
            // to this command; a signal, refresh failure, or parent cancellation
            // cancels and joins the other child before returning.
            let signals = await UnixSignalsSequence(trapping: .sigint, .sigterm)
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let context = try options.context()
                        let config = try context.database.configurationPath(context.explicitConfig?.string)
                            ?? context.configPath.string
                        let watcher = try IndexWatcher(root: context.canonicalRoot, databasePath: context.database.path,
                            additionalDirectories: [URL(fileURLWithPath: config).deletingLastPathComponent()])
                        var first = true
                        var verified = options
                        // Native events can preserve size and timestamps (atomic replacement,
                        // restored mtimes). Hashes also make periodic recovery authoritative.
                        verified.verifyHashes = true
                        try await watcher.run(debounce: debounce, reconcileInterval: reconcileInterval, refresh: {
                            try await verified.run(kind: .directory, directory: first ? directory : nil, name: "",
                                quiet: !first)
                            first = false
                        }, ready: {
                            print("Watching; initial reconciliation complete. Press Ctrl-C to stop.")
                        }, reportError: { error in
                            FileHandle.standardError.write(Data("Watch refresh failed; will retry: \(error)\n".utf8))
                        })
                    }
                    group.addTask {
                        for await _ in signals { return }
                    }
                    defer { group.cancelAll() }
                    try await group.next()
                }
            } catch is CancellationError {
                // A handled interruption is a clean shutdown; the cache remains rebuildable.
            }
        }
    }
}
