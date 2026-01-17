//
//  TOCEntry.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// A single entry in a table of contents.
///
/// Each entry represents one heading in the document, with its level, text content,
/// optional anchor slug, and any nested child entries.
public struct TOCEntry: Equatable, Sendable {
  /// The heading level (1-6).
  ///
  /// Corresponds to H1 through H6 in Markdown.
  public let level: Int

  /// The display text for this entry.
  ///
  /// This is the plain text extracted from the heading, without any formatting.
  public let text: String

  /// URL-safe anchor slug for linking.
  ///
  /// Generated from the text using GitHub-style slug rules.
  /// `nil` if slug generation was disabled.
  public let slug: String?

  /// Source position in the original document.
  ///
  /// `nil` if position tracking was disabled during generation.
  public let position: Position?

  /// Nested child entries (headings at deeper levels).
  ///
  /// For hierarchical TOC structures, this contains all headings that are children
  /// of this heading (i.e., headings at deeper levels that appear before the next
  /// heading at the same or shallower level).
  public let children: [TOCEntry]

  /// Create a TOC entry.
  ///
  /// - Parameters:
  ///   - level: Heading level (1-6)
  ///   - text: Display text
  ///   - slug: Optional URL-safe anchor slug
  ///   - position: Optional source position
  ///   - children: Nested child entries (default: empty)
  public init(
    level: Int,
    text: String,
    slug: String? = nil,
    position: Position? = nil,
    children: [TOCEntry] = []
  ) {
    self.level = level
    self.text = text
    self.slug = slug
    self.position = position
    self.children = children
  }

  /// Returns a flat array of all entries including this entry and all descendants.
  ///
  /// The entries are returned in document order.
  public var flattenedEntries: [TOCEntry] {
    var result = [self]
    for child in children {
      result.append(contentsOf: child.flattenedEntries)
    }
    return result
  }

  /// Returns true if this entry has any children.
  public var hasChildren: Bool {
    !children.isEmpty
  }
}
