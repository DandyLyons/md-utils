import Foundation

#if canImport(AppKit)
import AppKit
/// Platform-specific font type (NSFont on macOS).
public typealias PlatformFont = NSFont
/// Platform-specific color type (NSColor on macOS).
public typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
/// Platform-specific font type (UIFont on iOS/tvOS/watchOS).
public typealias PlatformFont = UIFont
/// Platform-specific color type (UIColor on iOS/tvOS/watchOS).
public typealias PlatformColor = UIColor
#endif

/// Configuration options for converting Markdown to RTF.
public struct RTFOptions: ConversionOptions, Sendable {

    // MARK: - ConversionOptions Conformance

    /// Whether to include YAML frontmatter in the RTF output.
    public let includeFrontmatter: Bool

    // MARK: - Font Options

    /// Base font name for body text (default: "Helvetica").
    public let baseFontName: String

    /// Base font size in points (default: 14).
    public let baseFontSize: CGFloat

    /// Monospace font name for code elements (default: "Menlo").
    public let monospaceFontName: String

    // MARK: - Heading Options

    /// Scale factors for heading levels h1–h6 relative to `baseFontSize`.
    ///
    /// Must contain exactly 6 elements. Index 0 corresponds to h1.
    public let headingScales: [CGFloat]

    // MARK: - Spacing Options

    /// Spacing in points after paragraphs (default: 8).
    public let paragraphSpacing: CGFloat

    /// Indentation in points per list nesting level (default: 24).
    public let listIndent: CGFloat

    // MARK: - Content Options

    /// Whether to preserve hyperlinks as `.link` attributes (default: true).
    public let preserveLinks: Bool

    // MARK: - Initialization

    /// Creates RTF conversion options with the specified settings.
    public init(
        includeFrontmatter: Bool = false,
        baseFontName: String = "Helvetica",
        baseFontSize: CGFloat = 14,
        monospaceFontName: String = "Menlo",
        headingScales: [CGFloat] = [2.0, 1.5, 1.25, 1.1, 1.0, 0.9],
        paragraphSpacing: CGFloat = 8,
        listIndent: CGFloat = 24,
        preserveLinks: Bool = true
    ) {
        self.includeFrontmatter = includeFrontmatter
        self.baseFontName = baseFontName
        self.baseFontSize = baseFontSize
        self.monospaceFontName = monospaceFontName
        self.headingScales = headingScales
        self.paragraphSpacing = paragraphSpacing
        self.listIndent = listIndent
        self.preserveLinks = preserveLinks
    }

    // MARK: - Presets

    /// Default options for RTF conversion.
    public static let `default` = RTFOptions()
}
