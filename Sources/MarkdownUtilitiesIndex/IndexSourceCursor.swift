import Foundation
import SystemPackage

/// Incrementally enumerates visible regular source files without retaining a folder listing.
///
/// Hidden entries and symlinks are skipped. Instances belong to one caller and must
/// not be accessed concurrently. Enumeration and metadata failures propagate;
/// reaching the end therefore establishes complete traversal of the directory.
public final class IndexSourceCursor {
    /// Resolves planned relative directories without following symlink ancestors.
    /// Missing prefixes have no candidates; access errors still fail discovery.
    public static func discoveryDirectories(root: URL, paths: [String]) throws -> [URL] {
        guard try Stat(FilePath(root.path), followTargetSymlink: false).type == .directory else {
            throw SQLiteIndexError(message: "Not a directory: \(root.path)/")
        }
        return try paths.compactMap { path in
            var directory = root
            for component in path.split(separator: "/") {
                guard component != ".", component != ".." else {
                    throw SQLiteIndexError(message: "Invalid discovery directory: \(path)")
                }
                directory.appendPathComponent(String(component), isDirectory: true)
                do {
                    guard try Stat(FilePath(directory.path), followTargetSymlink: false).type == .directory else { return nil }
                } catch let error as Errno where error == .noSuchFileOrDirectory || error == .notDirectory {
                    return nil
                }
            }
            return directory
        }
    }
    private final class Failure { var error: (any Error)? }
    private let failure = Failure()
    private let entries: FileManager.DirectoryEnumerator
    private let includeNonMarkdown: Bool

    /// Creates a cursor for a directory without writing index or filesystem state.
    /// - Parameters:
    ///   - directory: Native directory URL; the directory itself must not be a symlink.
    ///   - includeNonMarkdown: Whether to include extensions other than md/markdown.
    /// - Throws: Cancellation, native metadata errors, or an invalid/unreadable directory.
    public init(directory: URL, includeNonMarkdown: Bool = false) throws {
        try Task.checkCancellation()
        guard try Stat(FilePath(directory.path), followTargetSymlink: false).type == .directory else {
            throw SQLiteIndexError(message: "Not a directory: \(directory.path)/")
        }
        let failure = failure
        guard let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles], errorHandler: { _, error in
                failure.error = error
                return false
            }) else {
            throw SQLiteIndexError(message: "Cannot enumerate \(directory.path)/")
        }
        self.entries = entries
        self.includeNonMarkdown = includeNonMarkdown
    }

    /// Returns the next regular source file, or nil after complete enumeration.
    /// - Parameter isExcluded: Tests absolute paths before metadata reads; excluded directories are pruned.
    /// - Returns: A visible, non-symlink regular file URL, in native enumeration order.
    /// - Throws: Cancellation, enumeration errors, or metadata failures. Errors never imply absence.
    public func next(excluding isExcluded: (String) -> Bool = { _ in false }) throws -> URL? {
        while true {
            try Task.checkCancellation()
            let next = entries.nextObject()
            if let error = failure.error { throw error }
            guard let next else { return nil }
            guard let file = next as? URL else { throw SQLiteIndexError(message: "Unexpected directory entry.") }
            if isExcluded(file.path) {
                if (try? Stat(FilePath(file.path), followTargetSymlink: false).type) == .directory {
                    entries.skipDescendants()
                }
                continue
            }
            // Enumeration descends directories itself. Markdown-only discovery
            // need not stat every unrelated export, audio, or source-code file.
            if !includeNonMarkdown && !["md", "markdown"].contains(file.pathExtension.lowercased()) { continue }
            let metadata = try Stat(FilePath(file.path), followTargetSymlink: false)
            if metadata.type == .symbolicLink { continue }
            if metadata.type == .regular,
                includeNonMarkdown || ["md", "markdown"].contains(file.pathExtension.lowercased()) { return file }
        }
    }
}
