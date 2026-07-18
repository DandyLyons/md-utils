//
//  WikilinkAnchor.swift
//  MarkdownUtilities
//

/// Represents the anchor portion of a wikilink after the `#` in the target.
///
/// Obsidian supports two types of anchors:
/// - Heading anchors: `[[Page#Introduction]]` links to the "Introduction" heading
/// - Block ID anchors: `[[Page#^abc123]]` links to a specific block
public enum WikilinkAnchor: Sendable, Equatable, Hashable, Codable {
  /// A heading anchor, e.g. `#Introduction` in `[[Page#Introduction]]`.
  case heading(String)

  /// A block ID anchor, e.g. `#^abc123` in `[[Page#^abc123]]`.
  case blockID(String)
}
