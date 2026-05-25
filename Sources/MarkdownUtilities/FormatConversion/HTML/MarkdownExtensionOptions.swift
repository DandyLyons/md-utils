import MarkdownSyntax

/// Controls which GFM extensions are active during Markdown → HTML rendering.
///
/// This is our public API for toggling individual features. Internally it maps to
/// `CMExtensionOption` — users never touch that type directly.
///
/// Use `.all` (the default) for full GFM support or `.none` for CommonMark-only output.
/// Individual options can be combined using set operations:
/// ```swift
/// var options = MarkdownExtensionOptions.all
/// options.remove(.tables)      // all GFM except tables
///
/// let tablesOnly: MarkdownExtensionOptions = [.tables]
/// ```
public struct MarkdownExtensionOptions: OptionSet, Sendable {
    public let rawValue: Int64
    public init(rawValue: Int64) { self.rawValue = rawValue }

    /// No GFM extensions — CommonMark only.
    public static let none: MarkdownExtensionOptions = []

    /// All supported GFM extensions (tables, autolinks, strikethrough, tagfilters, tasklist).
    public static let all: MarkdownExtensionOptions = [.tables, .autolinks, .strikethrough, .tagfilters, .tasklist]

    // MARK: - GFM Extensions (bits 0–4, matching CMExtensionOption's layout)

    /// GFM pipe tables.
    public static let tables        = MarkdownExtensionOptions(rawValue: 1)

    /// URL autolinks.
    public static let autolinks     = MarkdownExtensionOptions(rawValue: 2)

    /// `~~Strikethrough~~` via double tildes.
    public static let strikethrough = MarkdownExtensionOptions(rawValue: 4)

    /// Filter unsafe HTML tags from output (e.g. `<script>`).
    public static let tagfilters    = MarkdownExtensionOptions(rawValue: 8)

    /// `- [x]` Task list checkboxes.
    public static let tasklist      = MarkdownExtensionOptions(rawValue: 16)

    // Future: bits 32+ for other flavors (MultiMarkdown, Pandoc, etc.)
    // Int64 gives 63 usable bits; CMExtensionOption uses Int32 (31 bits).
}

// MARK: - Internal mapping to CMExtensionOption

extension MarkdownExtensionOptions {
    /// Maps our public options to the underlying cmark type.
    ///
    /// This is intentionally internal — `CMExtensionOption` is an implementation detail.
    var asCMExtensionOption: CMExtensionOption {
        var result: CMExtensionOption = []
        if contains(.tables)        { result.insert(.tables) }
        if contains(.autolinks)     { result.insert(.autolinks) }
        if contains(.strikethrough) { result.insert(.strikethrough) }
        if contains(.tagfilters)    { result.insert(.tagfilters) }
        if contains(.tasklist)      { result.insert(.tasklist) }
        return result
    }
}
