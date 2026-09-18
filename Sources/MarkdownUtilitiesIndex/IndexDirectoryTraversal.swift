import Foundation
import SystemPackage

/// Incremental traversal with explicit error propagation. The caller stages paths
/// in count- and byte-limited batches rather than retaining the complete listing.
enum IndexDirectoryTraversal {
    static func visit(_ directory: URL, excluding cacheFiles: Set<String>,
        includeNonMarkdown: Bool, visitFile: (URL) throws -> Void) throws {
        try Task.checkCancellation()
        let rootMetadata = try Stat(FilePath(directory.path), followTargetSymlink: false)
        guard rootMetadata.type == .directory else {
            throw SQLiteIndexError(message: "Not a directory: \(directory.path)")
        }
        var traversalError: (any Error)?
        guard let entries = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                traversalError = error
                return false
            }) else {
            throw SQLiteIndexError(message: "Cannot enumerate \(directory.path)/")
        }
        while true {
            try Task.checkCancellation()
            let next = entries.nextObject()
            // A failure may be delivered on the call that returns nil. Check it
            // before treating nil as successful completion of the scope.
            if let traversalError { throw traversalError }
            guard let next else { return }
            guard let file = next as? URL else {
                throw SQLiteIndexError(message: "Unexpected directory entry in \(directory.path)/")
            }
            if cacheFiles.contains(file.path) { continue }
            let metadata = try Stat(FilePath(file.path), followTargetSymlink: false)
            if metadata.type == .symbolicLink {
                // Foundation does not descend into symbolic links. Calling
                // skipDescendants for a non-directory can skip unrelated entries.
                continue
            }
            if metadata.type == .regular,
                includeNonMarkdown || ["md", "markdown"].contains(file.pathExtension.lowercased()) {
                try visitFile(file)
            }
        }
    }
}
