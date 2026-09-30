import Foundation
import SystemPackage

/// Incremental traversal with explicit error propagation. The caller stages paths
/// in count- and byte-limited batches rather than retaining the complete listing.
enum IndexDirectoryTraversal {
    static func visit(_ directory: URL, excluding cacheFiles: IndexCacheExclusions,
        includeNonMarkdown: Bool, visitFile: (URL) throws -> Void) throws {
        try visit(directory, isExcluded: cacheFiles.contains, includeNonMarkdown: includeNonMarkdown, visitFile: visitFile)
    }

    static func visit(_ directory: URL, excluding cacheFiles: Set<String>,
        includeNonMarkdown: Bool, visitFile: (URL) throws -> Void) throws {
        try visit(directory, isExcluded: cacheFiles.contains, includeNonMarkdown: includeNonMarkdown, visitFile: visitFile)
    }

    static func visit(_ directory: URL, isExcluded: (String) -> Bool,
        includeNonMarkdown: Bool, visitFile: (URL) throws -> Void) throws {
        let cursor = try IndexSourceCursor(directory: directory, includeNonMarkdown: includeNonMarkdown)
        while let file = try cursor.next(excluding: isExcluded) { try visitFile(file) }
    }
}
