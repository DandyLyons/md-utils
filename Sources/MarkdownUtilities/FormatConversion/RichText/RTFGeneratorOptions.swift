import Foundation

/// Configuration options for converting RTF to Markdown.
public struct RTFGeneratorOptions: ConversionOptions, Sendable {

    // MARK: - ConversionOptions Conformance

    /// Whether to include YAML frontmatter in the Markdown output.
    public let includeFrontmatter: Bool

    // MARK: - Heading Detection

    /// Whether to detect headings based on font size and weight (default: true).
    public let detectHeadings: Bool

    /// Minimum font size ratio (relative to the most common font size)
    /// to consider a paragraph a heading (default: 1.2).
    public let headingSizeThreshold: CGFloat

    // MARK: - List Detection

    /// Whether to detect list items based on bullet/number prefixes and indentation (default: true).
    public let detectLists: Bool

    // MARK: - Code Detection

    /// Whether to detect code blocks based on monospace font usage (default: true).
    public let detectCodeBlocks: Bool

    // MARK: - Initialization

    /// Creates RTF-to-Markdown generation options with the specified settings.
    public init(
        includeFrontmatter: Bool = false,
        detectHeadings: Bool = true,
        headingSizeThreshold: CGFloat = 1.2,
        detectLists: Bool = true,
        detectCodeBlocks: Bool = true
    ) {
        self.includeFrontmatter = includeFrontmatter
        self.detectHeadings = detectHeadings
        self.headingSizeThreshold = headingSizeThreshold
        self.detectLists = detectLists
        self.detectCodeBlocks = detectCodeBlocks
    }

    // MARK: - Presets

    /// Default options for RTF-to-Markdown generation.
    public static let `default` = RTFGeneratorOptions()
}
