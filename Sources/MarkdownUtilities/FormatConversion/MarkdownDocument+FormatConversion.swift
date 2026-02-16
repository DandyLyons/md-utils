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

    // MARK: - RTF Conversion

    /// Converts the Markdown document to RTF data.
    ///
    /// - Parameter options: Configuration options for the conversion (default: .default)
    /// - Returns: The RTF data representation of the document
    /// - Throws: Conversion errors if the operation fails
    public func toRTF(options: RTFOptions = .default) async throws -> Data {
        let root = try await parseAST()
        let converter = RTFConverter()
        return try await converter.convert(from: root, options: options)
    }

    /// Generates Markdown content from RTF data.
    ///
    /// - Parameters:
    ///   - data: The RTF data to convert
    ///   - options: Configuration options for the generation (default: .default)
    /// - Returns: The generated Markdown content
    /// - Throws: Generation errors if the operation fails
    public static func fromRTF(data: Data, options: RTFGeneratorOptions = .default) async throws -> String {
        let generator = RTFGenerator()
        return try await generator.generate(from: data, options: options)
    }

    // MARK: - Private Helpers

    /// Serializes the frontmatter mapping back to YAML format.
    ///
    /// - Returns: The YAML representation of the frontmatter
    /// - Throws: Serialization errors if the frontmatter cannot be converted to YAML
    private func serializeFrontmatter() throws -> String {
        try YAMLConversion.serialize(frontMatter)
    }

    // MARK: - Future Format Conversions (Placeholders)

    // Uncomment and implement as needed:

    // /// Converts the Markdown document to HTML.
    // ///
    // /// - Parameter options: Configuration options for HTML conversion
    // /// - Returns: The HTML representation of the document
    // /// - Throws: Conversion errors if the operation fails
    // public func toHTML(options: HTMLOptions = .default) async throws -> String {
    //     fatalError("HTML conversion not yet implemented")
    // }
}
