import Foundation
import MarkdownSyntax

/// Options for configuring text extraction from phrasing content.
public struct PhrasingTextExtractionOptions: Sendable {
    /// Whether to preserve line breaks as newlines or convert them to spaces
    ///
    /// When `true`, `Break` and `SoftBreak` nodes are converted to newlines.
    /// When `false`, they are converted to spaces.
    public let preserveLineBreaks: Bool

    /// Whether to extract alt text from images
    ///
    /// When `true`, the alt text from `Image` nodes is included.
    /// When `false`, images are ignored entirely.
    public let extractImageAltText: Bool

    /// Whether to include HTML content
    ///
    /// When `true`, raw HTML is preserved in the output.
    /// When `false`, HTML is skipped.
    public let includeHTML: Bool

    /// Creates text extraction options with specified settings.
    ///
    /// - Parameters:
    ///   - preserveLineBreaks: Whether to preserve line breaks as newlines (default: true)
    ///   - extractImageAltText: Whether to extract alt text from images (default: true)
    ///   - includeHTML: Whether to include HTML content (default: false)
    public init(
        preserveLineBreaks: Bool = true,
        extractImageAltText: Bool = true,
        includeHTML: Bool = false
    ) {
        self.preserveLineBreaks = preserveLineBreaks
        self.extractImageAltText = extractImageAltText
        self.includeHTML = includeHTML
    }

    /// Default options for plain text extraction
    public static let `default` = PhrasingTextExtractionOptions()

    /// Options optimized for single-line text (no line breaks, no images)
    public static let singleLine = PhrasingTextExtractionOptions(
        preserveLineBreaks: false,
        extractImageAltText: false,
        includeHTML: false
    )
}

/// Extracts plain text from phrasing content (inline) AST nodes.
///
/// This utility provides configurable text extraction from Markdown inline elements,
/// handling various formatting constructs and allowing customization of how different
/// elements are processed.
///
/// Example usage:
/// ```swift
/// let options = PhrasingTextExtractionOptions(preserveLineBreaks: true)
/// let text = PhrasingContentTextExtractor.extractText(
///     from: heading.children,
///     options: options
/// )
/// ```
public enum PhrasingContentTextExtractor {

    /// Extracts plain text from an array of phrasing content.
    ///
    /// - Parameters:
    ///   - content: Array of phrasing content nodes
    ///   - options: Configuration for text extraction
    /// - Returns: The concatenated plain text
    public static func extractText(
        from content: [PhrasingContent],
        options: PhrasingTextExtractionOptions = .default
    ) -> String {
        content.map { extractText(from: $0, options: options) }.joined()
    }

    /// Extracts plain text from a single phrasing content node.
    ///
    /// - Parameters:
    ///   - content: A phrasing content node
    ///   - options: Configuration for text extraction
    /// - Returns: The extracted plain text
    public static func extractText(
        from content: PhrasingContent,
        options: PhrasingTextExtractionOptions = .default
    ) -> String {
        switch content {
        // Literal types - return the value directly
        case let text as Text:
            return text.value

        case let code as InlineCode:
            return code.value

        case let html as HTML:
            return options.includeHTML ? html.value : ""

        // Parent types - recurse into children
        case let strong as Strong:
            return extractText(from: strong.children, options: options)

        case let emphasis as Emphasis:
            return extractText(from: emphasis.children, options: options)

        case let delete as Delete:
            return extractText(from: delete.children, options: options)

        // Link - extract text from children (not URL)
        case let link as Link:
            return extractText(from: link.children.map { $0 as PhrasingContent }, options: options)

        // Image - extract alt text if configured
        case let image as Image:
            if options.extractImageAltText {
                return extractText(from: image.children.map { $0 as PhrasingContent }, options: options)
            } else {
                return ""
            }

        // Break types - convert to newline or space based on options
        case is Break, is SoftBreak:
            return options.preserveLineBreaks ? "\n" : " "

        // Unknown types - ignore
        default:
            return ""
        }
    }
}
