import Foundation
import MarkdownSyntax
import Yams

/// Format conversion extensions for MarkdownDocument.
///
/// These methods provide convenient APIs for converting Markdown documents
/// to various output formats while handling frontmatter appropriately.
extension MarkdownDocument {

    // MARK: - Plain Text Conversion

    /// Converts the Markdown document to plain text.
    ///
    /// This method strips all Markdown formatting while preserving content
    /// and maintaining readability through configurable spacing and structure.
    ///
    /// Example usage:
    /// ```swift
    /// let doc = try MarkdownDocument(content: markdownText)
    /// let plainText = try await doc.toPlainText()
    /// ```
    ///
    /// With custom options:
    /// ```swift
    /// let options = PlainTextOptions(
    ///     includeFrontmatter: true,
    ///     blockSeparator: 1
    /// )
    /// let plainText = try await doc.toPlainText(options: options)
    /// ```
    ///
    /// - Parameter options: Configuration options for the conversion (default: .default)
    /// - Returns: The plain text representation of the document
    /// - Throws: Conversion errors if the operation fails
    public func toPlainText(options: PlainTextOptions = .default) async throws -> String {
        // Parse the AST from the body
        let root = try await parseAST()

        // Convert to plain text
        let converter = PlainTextConverter()
        let bodyText = try await converter.convert(from: root, options: options)

        // Optionally prepend frontmatter
        if options.includeFrontmatter && !frontMatter.isEmpty {
            let frontmatterYAML = try serializeFrontmatter()
            let separator = String(repeating: "\n", count: max(1, options.blockSeparator))
            return "---\n\(frontmatterYAML)---\(separator)\(bodyText)"
        }

        return bodyText
    }

    // MARK: - Private Helpers

    /// Serializes the frontmatter mapping back to YAML format.
    ///
    /// - Returns: The YAML representation of the frontmatter
    /// - Throws: Serialization errors if the frontmatter cannot be converted to YAML
    private func serializeFrontmatter() throws -> String {
        try YAMLConversion.serialize(frontMatter)
    }

    // MARK: - HTML Conversion

    /// Converts the Markdown document to HTML.
    ///
    /// Uses the battle-tested cmark-gfm renderer directly, bypassing the typed AST.
    /// GFM extensions (tables, autolinks, strikethrough, tagfilters, task lists) are
    /// enabled by default; disable them individually via `options.extensions`.
    ///
    /// Example usage:
    /// ```swift
    /// let doc = try MarkdownDocument(content: markdownText)
    /// let html = try await doc.toHTML()
    /// ```
    ///
    /// With custom options:
    /// ```swift
    /// let options = HTMLOptions(wrapInDocument: true, extensions: [.tables, .tasklist])
    /// let html = try await doc.toHTML(options: options)
    /// ```
    ///
    /// - Parameter options: Configuration options for the conversion (default: .default)
    /// - Returns: The HTML representation of the document
    /// - Throws: Conversion errors if the cmark renderer fails
    public func toHTML(options: HTMLOptions = .default) async throws -> String {
        var cmarkOptions: CMDocumentOption = [.strikethroughDoubleTilde, .footnotes]
        if options.hardBreaks      { cmarkOptions.insert(.hardBreaks) }
        if options.allowUnsafeHTML { cmarkOptions.insert(.unsafe) }
        if options.smartPunctuation { cmarkOptions.insert(.smart) }

        let document = try CMDocument(
            text: body,
            options: cmarkOptions,
            extensions: options.extensions.asCMExtensionOption
        )
        var html = try await document.renderHtml()

        if options.includeFrontmatter && !frontMatter.isEmpty {
            let yaml = try serializeFrontmatter()
            html = "<!--\n\(yaml)-->\n" + html
        }

        if options.wrapInDocument {
            html = "<!DOCTYPE html>\n<html>\n<head></head>\n<body>\n\(html)</body>\n</html>\n"
        }

        return html
    }
}
