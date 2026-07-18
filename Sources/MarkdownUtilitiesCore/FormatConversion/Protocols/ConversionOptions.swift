import Foundation

/// Base protocol for format conversion options.
///
/// All format conversion option types should conform to this protocol,
/// which ensures they are thread-safe and can be used across concurrent contexts.
///
/// Conforming types should provide configuration options specific to their
/// target format while maintaining the base requirement for frontmatter handling.
public protocol ConversionOptions: Sendable {
    /// Whether to include YAML frontmatter in the converted output
    ///
    /// When `true`, frontmatter will be preserved in the output.
    /// When `false`, frontmatter will be excluded from the conversion.
    ///
    /// Default behavior varies by format but typically defaults to `false`
    /// for formats that don't natively support YAML metadata.
    var includeFrontmatter: Bool { get }
}
