import Foundation
import MarkdownSyntax

/// Options for configuring text extraction from block content.
public struct BlockTextExtractionOptions: Sendable {
    /// Options for extracting text from phrasing (inline) content
    public let phrasingOptions: PhrasingTextExtractionOptions

    /// Number of spaces to use for list indentation per level
    ///
    /// When `0`, list items are not indented.
    public let listIndentSpaces: Int

    /// Whether to preserve code blocks in the output
    ///
    /// When `true`, code block content is included.
    /// When `false`, code blocks are skipped.
    public let preserveCodeBlocks: Bool

    /// Whether to include HTML blocks in the output
    ///
    /// When `true`, HTML block content is included.
    /// When `false`, HTML blocks are skipped.
    public let includeHTMLBlocks: Bool

    /// Separator to use between block elements
    ///
    /// Typically `"\n\n"` for double-spacing between blocks.
    public let blockSeparator: String

    /// Creates block text extraction options with specified settings.
    ///
    /// - Parameters:
    ///   - phrasingOptions: Options for phrasing content extraction
    ///   - listIndentSpaces: Spaces for list indentation (default: 2)
    ///   - preserveCodeBlocks: Whether to preserve code blocks (default: true)
    ///   - includeHTMLBlocks: Whether to include HTML blocks (default: false)
    ///   - blockSeparator: Separator between blocks (default: "\n\n")
    public init(
        phrasingOptions: PhrasingTextExtractionOptions = .default,
        listIndentSpaces: Int = 2,
        preserveCodeBlocks: Bool = true,
        includeHTMLBlocks: Bool = false,
        blockSeparator: String = "\n\n"
    ) {
        self.phrasingOptions = phrasingOptions
        self.listIndentSpaces = listIndentSpaces
        self.preserveCodeBlocks = preserveCodeBlocks
        self.includeHTMLBlocks = includeHTMLBlocks
        self.blockSeparator = blockSeparator
    }

    /// Default options for plain text extraction
    public static let `default` = BlockTextExtractionOptions()
}

/// Extracts plain text from block content AST nodes.
///
/// This utility provides configurable text extraction from Markdown block-level elements,
/// handling headings, paragraphs, lists, code blocks, blockquotes, and other structural
/// elements while maintaining appropriate formatting and hierarchy.
///
/// Example usage:
/// ```swift
/// let options = BlockTextExtractionOptions(listIndentSpaces: 2)
/// let text = BlockContentTextExtractor.extractText(
///     from: root.children,
///     options: options
/// )
/// ```
public enum BlockContentTextExtractor {

    /// Extracts plain text from an array of content nodes.
    ///
    /// - Parameters:
    ///   - content: Array of content nodes
    ///   - options: Configuration for text extraction
    ///   - indentLevel: Current indentation level for nested structures (default: 0)
    /// - Returns: The extracted plain text with appropriate formatting
    public static func extractText(
        from content: [Content],
        options: BlockTextExtractionOptions = .default,
        indentLevel: Int = 0
    ) -> String {
        let texts = content.compactMap { extractText(from: $0, options: options, indentLevel: indentLevel) }
        return texts.joined(separator: options.blockSeparator)
    }

    /// Extracts plain text from a single content node.
    ///
    /// - Parameters:
    ///   - content: A content node
    ///   - options: Configuration for text extraction
    ///   - indentLevel: Current indentation level for nested structures
    /// - Returns: The extracted plain text, or nil if the block should be skipped
    public static func extractText(
        from content: Content,
        options: BlockTextExtractionOptions = .default,
        indentLevel: Int = 0
    ) -> String? {
        let indent = String(repeating: " ", count: indentLevel * options.listIndentSpaces)

        switch content {
        // Heading - extract text from children
        case let heading as Heading:
            let text = PhrasingContentTextExtractor.extractText(
                from: heading.children,
                options: options.phrasingOptions
            )
            return indent + text

        // Paragraph - extract text from children
        case let paragraph as Paragraph:
            let text = PhrasingContentTextExtractor.extractText(
                from: paragraph.children,
                options: options.phrasingOptions
            )
            return indent + text

        // Code block - preserve if configured
        case let codeBlock as Code:
            guard options.preserveCodeBlocks else { return nil }
            // Split code into lines and indent each line
            let lines = codeBlock.value.split(separator: "\n", omittingEmptySubsequences: false)
            return lines.map { indent + $0 }.joined(separator: "\n")

        // Blockquote - extract from children with increased indentation
        case let blockquote as Blockquote:
            return extractText(
                from: blockquote.children,
                options: options,
                indentLevel: indentLevel + 1
            )

        // List - extract from items (both ordered and unordered)
        case let list as List:
            return extractListItems(
                list.children,
                options: options,
                indentLevel: indentLevel
            )

        // Thematic break - skip (can't represent meaningfully in plain text)
        case is ThematicBreak:
            return nil

        // Unknown types - skip
        default:
            return nil
        }
    }

    /// Extracts text from list content.
    ///
    /// - Parameters:
    ///   - content: Array of list content nodes
    ///   - options: Configuration for text extraction
    ///   - indentLevel: Current indentation level
    /// - Returns: The extracted text from all list items
    private static func extractListItems(
        _ content: [ListContent],
        options: BlockTextExtractionOptions,
        indentLevel: Int
    ) -> String {
        let itemTexts = content.compactMap { listContent -> String? in
            // Cast to ListItem
            guard let item = listContent as? ListItem else {
                return nil
            }
            // Extract text from the item's children
            let childText = extractText(
                from: item.children,
                options: options,
                indentLevel: indentLevel + 1
            )
            return childText.isEmpty ? nil : childText
        }
        return itemTexts.joined(separator: options.blockSeparator)
    }
}
