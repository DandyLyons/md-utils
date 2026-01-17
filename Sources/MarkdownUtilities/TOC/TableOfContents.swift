//
//  TableOfContents.swift
//  MarkdownUtilities
//

import Foundation

/// A complete table of contents for a Markdown document.
///
/// Contains the hierarchical structure of headings extracted from a document,
/// along with metadata about the level range.
public struct TableOfContents: Equatable, Sendable {
  /// Top-level TOC entries.
  ///
  /// For hierarchical TOCs, this contains only the root-level entries.
  /// For flat TOCs, this contains all entries.
  public let entries: [TOCEntry]

  /// The minimum heading level present in this TOC.
  ///
  /// Will be between 1 and 6.
  public let minLevel: Int

  /// The maximum heading level present in this TOC.
  ///
  /// Will be between 1 and 6.
  public let maxLevel: Int

  /// Create a table of contents.
  ///
  /// - Parameters:
  ///   - entries: Top-level entries
  ///   - minLevel: Minimum heading level (1-6)
  ///   - maxLevel: Maximum heading level (1-6)
  public init(entries: [TOCEntry], minLevel: Int, maxLevel: Int) {
    self.entries = entries
    self.minLevel = minLevel
    self.maxLevel = maxLevel
  }

  /// Returns a flat array of all entries in document order.
  ///
  /// This flattens the hierarchical structure into a single array,
  /// preserving document order.
  public var flatEntries: [TOCEntry] {
    entries.flatMap { $0.flattenedEntries }
  }

  /// Returns true if this TOC has no entries.
  public var isEmpty: Bool {
    entries.isEmpty
  }

  /// Returns the total number of entries including all nested children.
  public var totalCount: Int {
    flatEntries.count
  }

  /// Returns a filtered table of contents containing only entries within the specified level range.
  ///
  /// - Parameters:
  ///   - minLevel: Minimum level to include (1-6)
  ///   - maxLevel: Maximum level to include (1-6)
  /// - Returns: A new TableOfContents with filtered entries
  public func filtered(minLevel: Int, maxLevel: Int) -> TableOfContents {
    let filteredFlat = flatEntries.filter { entry in
      entry.level >= minLevel && entry.level <= maxLevel
    }

    if filteredFlat.isEmpty {
      return TableOfContents(entries: [], minLevel: minLevel, maxLevel: maxLevel)
    }

    let actualMinLevel = filteredFlat.map(\.level).min() ?? minLevel
    let actualMaxLevel = filteredFlat.map(\.level).max() ?? maxLevel

    // For filtered TOCs, we return a flat structure (no hierarchy reconstruction)
    let flatEntries = filteredFlat.map { entry in
      TOCEntry(
        level: entry.level,
        text: entry.text,
        slug: entry.slug,
        position: entry.position,
        children: []
      )
    }

    return TableOfContents(
      entries: flatEntries,
      minLevel: actualMinLevel,
      maxLevel: actualMaxLevel
    )
  }
}
