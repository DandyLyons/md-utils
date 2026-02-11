//
//  Wikilink.swift
//  MarkdownUtilities
//

/// Represents a parsed Obsidian-flavored wikilink.
///
/// Wikilinks follow the format `[[target]]` or `[[target|display text]]`,
/// with optional embed prefix `!` and anchor suffix `#heading` or `#^blockID`.
///
/// ## Examples
/// - `[[My Page]]` — simple link
/// - `[[My Page|Display]]` — aliased link
/// - `[[My Page#Introduction]]` — heading anchor
/// - `[[My Page#^abc123]]` — block ID anchor
/// - `![[Image.png]]` — embedded file
public struct Wikilink: Sendable, Equatable, Hashable, Codable {
  /// The full source text including brackets (and `!` prefix for embeds).
  public let rawValue: String

  /// The file path or page name target (with escaped pipes resolved to literal `|`).
  public let target: String

  /// The display text after an unescaped pipe, if present.
  public let displayText: String?

  /// The heading or block anchor, if present.
  public let anchor: WikilinkAnchor?

  /// Whether this wikilink is an embed (prefixed with `!`).
  public let isEmbed: Bool

  public init(
    rawValue: String,
    target: String,
    displayText: String?,
    anchor: WikilinkAnchor?,
    isEmbed: Bool
  ) {
    self.rawValue = rawValue
    self.target = target
    self.displayText = displayText
    self.anchor = anchor
    self.isEmbed = isEmbed
  }
}
