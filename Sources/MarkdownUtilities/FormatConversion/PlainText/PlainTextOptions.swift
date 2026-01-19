import Foundation

/// Configuration options for converting Markdown to plain text.
///
/// These options control how various Markdown elements are converted to plain text,
/// including frontmatter handling, block spacing, list formatting, and more.
///
/// Example usage:
/// ```swift
/// let options = PlainTextOptions(
///     includeFrontmatter: true,
///     blockSeparator: 1,
///     indentLists: false
/// )
/// let plainText = try await doc.toPlainText(options: options)
/// ```
public struct PlainTextOptions: ConversionOptions, Sendable {

    // MARK: - ConversionOptions Conformance

    /// Whether to include YAML frontmatter in the plain text output
    ///
    /// When `true`, frontmatter is preserved as a YAML block at the beginning.
    /// When `false`, frontmatter is excluded from the output.
    public let includeFrontmatter: Bool

    // MARK: - Block Formatting Options

    /// Number of newlines to use between block elements
    ///
    /// Default is `2` (double-spacing for readability).
    /// Use `1` for single-spacing.
    public let blockSeparator: Int

    // MARK: - Inline Content Options

    /// Whether to preserve line breaks as newlines or convert them to spaces
    ///
    /// When `true`, hard breaks and soft breaks in the source are preserved as newlines.
    /// When `false`, they are converted to spaces.
    public let preserveLineBreaks: Bool

    /// Whether to extract alt text from images
    ///
    /// When `true`, image alt text is included in the output.
    /// When `false`, images are completely omitted.
    public let extractImageAltText: Bool

    // MARK: - List Formatting Options

    /// Whether to indent nested list items
    ///
    /// When `true`, nested lists are indented according to `indentSpaces`.
    /// When `false`, all list items appear at the same indentation level.
    public let indentLists: Bool

    /// Number of spaces to use for each level of list indentation
    ///
    /// Only applies when `indentLists` is `true`.
    /// Default is `2` spaces per level.
    public let indentSpaces: Int

    // MARK: - Code Block Options

    /// Whether to preserve code blocks in the output
    ///
    /// When `true`, code block content is included with indentation.
    /// When `false`, code blocks are omitted entirely.
    public let preserveCodeBlocks: Bool

    // MARK: - Initialization

    /// Creates plain text conversion options with specified settings.
    ///
    /// - Parameters:
    ///   - includeFrontmatter: Include YAML frontmatter (default: false)
    ///   - blockSeparator: Newlines between blocks (default: 2)
    ///   - preserveLineBreaks: Preserve line breaks as newlines (default: true)
    ///   - extractImageAltText: Extract image alt text (default: true)
    ///   - indentLists: Indent nested lists (default: true)
    ///   - indentSpaces: Spaces per indentation level (default: 2)
    ///   - preserveCodeBlocks: Include code blocks (default: true)
    public init(
        includeFrontmatter: Bool = false,
        blockSeparator: Int = 2,
        preserveLineBreaks: Bool = true,
        extractImageAltText: Bool = true,
        indentLists: Bool = true,
        indentSpaces: Int = 2,
        preserveCodeBlocks: Bool = true
    ) {
        self.includeFrontmatter = includeFrontmatter
        self.blockSeparator = blockSeparator
        self.preserveLineBreaks = preserveLineBreaks
        self.extractImageAltText = extractImageAltText
        self.indentLists = indentLists
        self.indentSpaces = indentSpaces
        self.preserveCodeBlocks = preserveCodeBlocks
    }

    // MARK: - Presets

    /// Default options for plain text conversion
    ///
    /// Uses double-spacing between blocks, preserves line breaks,
    /// indents lists, and includes code blocks. Excludes frontmatter.
    public static let `default` = PlainTextOptions()

    /// Compact options for minimal plain text output
    ///
    /// Uses single-spacing, no list indentation, and no code blocks.
    /// Useful for generating compact text summaries.
    public static let compact = PlainTextOptions(
        blockSeparator: 1,
        indentLists: false,
        preserveCodeBlocks: false
    )

    /// Options optimized for single-line text extraction
    ///
    /// Converts line breaks to spaces and omits images and code blocks.
    /// Useful for generating one-line summaries or titles.
    public static let singleLine = PlainTextOptions(
        blockSeparator: 0,
        preserveLineBreaks: false,
        extractImageAltText: false,
        indentLists: false,
        preserveCodeBlocks: false
    )
}
