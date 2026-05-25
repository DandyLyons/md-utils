/// Configuration options for Markdown → HTML conversion.
public struct HTMLOptions: ConversionOptions, Sendable {

    // MARK: - ConversionOptions

    /// Prepend YAML frontmatter as an HTML comment (`<!-- ... -->`).
    public var includeFrontmatter: Bool

    // MARK: - Document structure

    /// Wrap the rendered body in a minimal HTML document skeleton:
    /// `<!DOCTYPE html><html><head></head><body>…</body></html>`.
    public var wrapInDocument: Bool

    // MARK: - Rendering behaviour

    /// Render soft line breaks as `<br>` instead of a space.
    public var hardBreaks: Bool

    /// Pass raw HTML through unchanged (unsafe). When `false`, raw HTML is
    /// replaced with an HTML comment placeholder.
    public var allowUnsafeHTML: Bool

    /// Convert straight quotes to curly, `---` to em dashes, `--` to en dashes.
    public var smartPunctuation: Bool

    // MARK: - Feature toggles

    /// Which GFM extensions to enable. Defaults to `.all`.
    public var extensions: MarkdownExtensionOptions

    // MARK: - Default

    /// Default options: no frontmatter, no document wrapper, soft breaks,
    /// safe HTML, no smart punctuation, all GFM extensions enabled.
    public static let `default` = HTMLOptions(
        includeFrontmatter: false,
        wrapInDocument: false,
        hardBreaks: false,
        allowUnsafeHTML: false,
        smartPunctuation: false,
        extensions: .all
    )

    public init(
        includeFrontmatter: Bool = false,
        wrapInDocument: Bool = false,
        hardBreaks: Bool = false,
        allowUnsafeHTML: Bool = false,
        smartPunctuation: Bool = false,
        extensions: MarkdownExtensionOptions = .all
    ) {
        self.includeFrontmatter = includeFrontmatter
        self.wrapInDocument = wrapInDocument
        self.hardBreaks = hardBreaks
        self.allowUnsafeHTML = allowUnsafeHTML
        self.smartPunctuation = smartPunctuation
        self.extensions = extensions
    }
}
