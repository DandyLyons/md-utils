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
  /// Creates an alias suggestion for a host-supplied canonical destination.
  /// This neither searches aliases nor substitutes the alias for target identity.
  public static func suggestion(canonicalTarget: String, alias: String) throws -> Wikilink {
    let link = try parse("[[\(canonicalTarget)|\(alias)]]")
    guard link.target == canonicalTarget, link.anchor == nil, link.displayText == alias else {
      throw MarkdownSemanticScalarError.syntax
    }
    return link
  }

  /// Parses exactly one link without resolving its destination. Use the same
  /// context as discovery when reparsing an occurrence's preserved raw text.
  public static func parse(
    _ source: String,
    context: WikilinkParsingContext = .standard,
  ) throws -> Wikilink {
    var input = source[...]
    let link: Wikilink
    do { link = try WikilinkParser(context: context).parse(&input) }
    catch { throw MarkdownSemanticScalarError.syntax }
    guard input.isEmpty else { throw MarkdownSemanticScalarError.trailingInput }
    return link
  }

  /// The full source text including brackets (and `!` prefix for embeds).
  public let rawValue: String

  /// The file path or page name target (with escaped pipes resolved to literal `|`).
  public let target: String

  /// The display text after the context's alias separator, if present.
  public let displayText: String?

  /// The heading or block anchor, if present.
  public let anchor: WikilinkAnchor?

  /// Whether this wikilink is an embed (prefixed with `!`).
  public let isEmbed: Bool
  /// Creates a configured instance.
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
