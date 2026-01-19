import Foundation
import MarkdownSyntax

/// Converts Markdown AST to plain text format.
///
/// This converter strips all Markdown formatting while preserving the content and
/// maintaining readability through configurable spacing, indentation, and structure.
///
/// Example usage:
/// ```swift
/// let converter = PlainTextConverter()
/// let options = PlainTextOptions.default
/// let plainText = try await converter.convert(from: root, options: options)
/// ```
public struct PlainTextConverter: MarkdownConverter {
    public typealias Output = String
    public typealias Options = PlainTextOptions

    /// Creates a new plain text converter
    public init() {}

    /// Converts a Markdown AST to plain text.
    ///
    /// - Parameters:
    ///   - root: The root node of the Markdown AST
    ///   - options: Configuration options for the conversion
    /// - Returns: The plain text representation of the Markdown content
    /// - Throws: Conversion errors if the operation fails
    public func convert(from root: Root, options: PlainTextOptions) async throws -> String {
        // Create block extraction options from plain text options
        let phrasingOptions = PhrasingTextExtractionOptions(
            preserveLineBreaks: options.preserveLineBreaks,
            extractImageAltText: options.extractImageAltText,
            includeHTML: false
        )

        let blockOptions = BlockTextExtractionOptions(
            phrasingOptions: phrasingOptions,
            listIndentSpaces: options.indentLists ? options.indentSpaces : 0,
            preserveCodeBlocks: options.preserveCodeBlocks,
            includeHTMLBlocks: false,
            blockSeparator: String(repeating: "\n", count: options.blockSeparator)
        )

        // Extract text from all block content
        let bodyText = BlockContentTextExtractor.extractText(
            from: root.children,
            options: blockOptions
        )

        return bodyText
    }
}
