import Foundation
import MarkdownSyntax
import Yams

/// Options controlling which formatting normalizations `MarkdownDocument.format(options:)` applies.
public struct FormattingOptions: Sendable {
    /// Target bullet marker for unordered lists, or `nil` to leave bullets unchanged.
    public var bulletMarker: BulletNormalizer.Marker?

    /// Target italic marker for emphasis, or `nil` to leave italic markers unchanged.
    public var italicMarker: ItalicNormalizer.Marker?

    /// When `true`, GFM tables are reformatted so that columns align vertically.
    public var normalizeTables: Bool

    /// Maximum column width (in characters) when normalizing tables.
    /// Columns are padded to at most this width; cells whose content already
    /// exceeds this value are never truncated. Defaults to `80`.
    public var tableMaxWidth: Int

    public init(
        bulletMarker: BulletNormalizer.Marker? = nil,
        italicMarker: ItalicNormalizer.Marker? = nil,
        normalizeTables: Bool = false,
        tableMaxWidth: Int = 80
    ) {
        self.bulletMarker = bulletMarker
        self.italicMarker = italicMarker
        self.normalizeTables = normalizeTables
        self.tableMaxWidth = tableMaxWidth
    }
}

extension MarkdownDocument {

    /// Returns a new `MarkdownDocument` with the requested formatting normalizations applied.
    ///
    /// The AST is parsed once for bullet normalization.  If italic normalization is also
    /// requested the body is re-parsed after bullet changes so that character offsets remain
    /// accurate.  Table normalization is purely string-based and runs last.
    ///
    /// - Parameter options: Which normalizations to apply
    /// - Returns: A new document with the normalizations applied
    /// - Throws: If AST parsing or document reconstruction fails
    public func format(options: FormattingOptions) async throws -> MarkdownDocument {
        var result = body

        // --- Bullet normalization ---
        if let bulletMarker = options.bulletMarker {
            let root = try await parseAST()
            result = BulletNormalizer.normalize(result, root: root, to: bulletMarker)
        }

        // --- Italic normalization ---
        // Re-parse the (possibly modified) body so that String.Index offsets are accurate.
        if let italicMarker = options.italicMarker {
            let markdown = try await Markdown(text: result)
            let root = await markdown.parse()
            result = ItalicNormalizer.normalize(result, root: root, to: italicMarker)
        }

        // --- Table normalization ---
        if options.normalizeTables {
            result = TableNormalizer.normalize(result, maxWidth: options.tableMaxWidth)
        }

        let fullContent = try reconstructFullDocument(frontMatter: frontMatter, body: result)
        return try MarkdownDocument(content: fullContent)
    }

    /// Reconstructs the full markdown document combining frontmatter and body.
    private func reconstructFullDocument(
        frontMatter: Yams.Node.Mapping,
        body: String
    ) throws -> String {
        guard !frontMatter.isEmpty else { return body }
        let yamlContent = try YAMLConversion.serialize(frontMatter)
        return """
            ---
            \(yamlContent)---
            \(body)
            """
    }
}
