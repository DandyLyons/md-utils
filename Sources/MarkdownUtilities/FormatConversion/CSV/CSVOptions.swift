import Foundation

/// Configuration options for converting Markdown to CSV format.
///
/// These options control which columns are included in the CSV output,
/// including metadata columns and the body content column.
///
/// Example usage:
/// ```swift
/// let options = CSVOptions(
///     includeBody: true,
///     metadataColumns: [.fileName, .relPath],
///     baseDirectory: "/path/to/docs"
/// )
/// ```
public struct CSVOptions: ConversionOptions, Sendable {

    // MARK: - ConversionOptions Conformance

    /// Whether to include YAML frontmatter in the CSV output
    ///
    /// This is always `true` for CSV conversion since the entire purpose
    /// is to export frontmatter as columns.
    public let includeFrontmatter: Bool = true

    // MARK: - CSV-Specific Options

    /// Whether to include the `$body` column containing the document body content
    ///
    /// When `true`, a `$body` column is included with the full markdown body.
    /// When `false`, only frontmatter columns are exported.
    public let includeBody: Bool

    /// Set of metadata columns to include in the output
    ///
    /// Metadata columns appear first in the CSV, in the order they appear in this set.
    /// Available metadata columns are defined by the `MetadataColumn` enum.
    public let metadataColumns: Set<MetadataColumn>

    /// Base directory for calculating relative paths
    ///
    /// When `nil`, relative paths are calculated from the current working directory.
    /// When specified, relative paths use this as the base.
    public let baseDirectory: String?

    // MARK: - Initialization

    /// Creates CSV conversion options with specified settings.
    ///
    /// - Parameters:
    ///   - includeBody: Include `$body` column (default: true)
    ///   - metadataColumns: Set of metadata columns to include (default: empty)
    ///   - baseDirectory: Base directory for relative paths (default: nil)
    public init(
        includeBody: Bool = true,
        metadataColumns: Set<MetadataColumn> = [],
        baseDirectory: String? = nil
    ) {
        self.includeBody = includeBody
        self.metadataColumns = metadataColumns
        self.baseDirectory = baseDirectory
    }

    // MARK: - Metadata Column Definition

    /// Available metadata columns for CSV export
    public enum MetadataColumn: String, CaseIterable, Sendable, Hashable {
        /// File name without path (e.g., "document.md")
        case fileName = "$fileName"

        /// Relative path from base directory (e.g., "docs/document.md")
        case relPath = "$relPath"

        /// Absolute file path (e.g., "/Users/user/docs/document.md")
        case absPath = "$absPath"
    }
}
