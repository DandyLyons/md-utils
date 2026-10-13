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
  /// Defaults to historical legacy syntax; retain the selected context when reparsing.
  /// Use ``wikilinkOccurrences(context:)`` to retain property paths and locations.
  ///
  /// - Returns: An array of ``Wikilink`` values found in the entire document.
  public func wikilinks(context: WikilinkParsingContext = .legacy) -> [Wikilink] {
    var results: [Wikilink] = []
    results.append(contentsOf: frontMatterWikilinks(context: context))
    results.append(contentsOf: bodyWikilinks(context: context))
    return results
  }

  /// Whether the document contains any wikilinks (in frontmatter or body).
  public var hasWikilinks: Bool {
    !wikilinks().isEmpty
  }

  /// Scans only the document body for wikilinks.
  /// Defaults to legacy syntax without detecting tables or excluding code examples.
  public func bodyWikilinks(context: WikilinkParsingContext = .legacy) -> [Wikilink] {
    WikilinkScanner.scan(body, context: context)
  }

  /// Scans only the YAML or TOML frontmatter for wikilinks.
  ///
  /// Recursively walks all scalar values in the frontmatter mapping and scans
  /// each string for wikilinks.
  /// Defaults to legacy syntax; declared scalar validation uses standard context.
  public func frontMatterWikilinks(context: WikilinkParsingContext = .legacy) -> [Wikilink] {
    var results: [Wikilink] = []
    for (_, value) in frontMatter {
      collectWikilinks(from: value, context: context, into: &results)
    }
    return results
  }

  /// Recursively walks a YAML node tree, scanning all scalar string values for wikilinks.
  private func collectWikilinks(
    from value: FrontMatterValue,
    context: WikilinkParsingContext,
    into results: inout [Wikilink],
  ) {
    switch value {
    case .string(let string):
      results.append(contentsOf: WikilinkScanner.scan(string, context: context))
    case .object(let mapping):
      for (_, value) in mapping {
        collectWikilinks(from: value, context: context, into: &results)
      }
    case .array(let sequence):
      for item in sequence {
        collectWikilinks(from: item, context: context, into: &results)
      }
    default:
      break
    }
  }
}
