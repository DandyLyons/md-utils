//
//  MarkdownDocument+Wikilink.swift
//  MarkdownUtilities
//

/// Adds wikilink behavior to ``MarkdownDocument``.
extension MarkdownDocument {
  /// Scans both YAML or TOML frontmatter and the document body for wikilinks.
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

  /// Scans only the YAML or TOML frontmatter for wikilinks.
  ///
  /// Recursively walks all scalar values in the frontmatter mapping and scans
  /// each string for wikilinks.
  public func frontMatterWikilinks() -> [Wikilink] {
    var results: [Wikilink] = []
    for (_, value) in frontMatter {
      collectWikilinks(from: value, into: &results)
    }
    return results
  }

  /// Recursively walks a YAML node tree, scanning all scalar string values for wikilinks.
  private func collectWikilinks(from value: FrontMatterValue, into results: inout [Wikilink]) {
    switch value {
    case .string(let string):
      results.append(contentsOf: WikilinkScanner.scan(string))
    case .object(let mapping):
      for (_, value) in mapping {
        collectWikilinks(from: value, into: &results)
      }
    case .array(let sequence):
      for item in sequence {
        collectWikilinks(from: item, into: &results)
      }
    default:
      break
    }
  }
}
