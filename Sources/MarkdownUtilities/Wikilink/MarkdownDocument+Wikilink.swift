//
//  MarkdownDocument+Wikilink.swift
//  MarkdownUtilities
//

import Yams

extension MarkdownDocument {
  /// Scans both the YAML frontmatter and the document body for wikilinks.
  ///
  /// Frontmatter wikilinks appear first (in the order they are encountered
  /// while walking the YAML tree), followed by body wikilinks in document order.
  ///
  /// - Returns: An array of ``Wikilink`` values found in the entire document.
  public func wikilinks() -> [Wikilink] {
    var results: [Wikilink] = []
    results.append(contentsOf: frontMatterWikilinks())
    results.append(contentsOf: bodyWikilinks())
    return results
  }

  /// Whether the document contains any wikilinks (in frontmatter or body).
  public var hasWikilinks: Bool {
    !wikilinks().isEmpty
  }

  /// Scans only the document body for wikilinks.
  public func bodyWikilinks() -> [Wikilink] {
    WikilinkScanner.scan(body)
  }

  /// Scans only the YAML frontmatter for wikilinks.
  ///
  /// Recursively walks all scalar values in the frontmatter mapping and scans
  /// each string for wikilinks.
  public func frontMatterWikilinks() -> [Wikilink] {
    var results: [Wikilink] = []
    collectWikilinks(from: .mapping(frontMatter), into: &results)
    return results
  }

  /// Recursively walks a YAML node tree, scanning all scalar string values for wikilinks.
  private func collectWikilinks(from node: Yams.Node, into results: inout [Wikilink]) {
    switch node {
    case .scalar(let scalar):
      results.append(contentsOf: WikilinkScanner.scan(scalar.string))

    case .mapping(let mapping):
      for (_, value) in mapping {
        collectWikilinks(from: value, into: &results)
      }

    case .sequence(let sequence):
      for item in sequence {
        collectWikilinks(from: item, into: &results)
      }

    case .alias:
      break
    }
  }
}
