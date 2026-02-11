//
//  WikilinkScanner.swift
//  MarkdownUtilities
//

/// Scans raw Markdown text to extract all wikilinks.
///
/// This is a caseless enum namespace (no instances). Use ``scan(_:)`` to find
/// all wikilinks in a string. Malformed brackets are silently skipped.
///
/// ## Example
/// ```swift
/// let links = WikilinkScanner.scan("See [[Page A]] and [[Page B]].")
/// // links.count == 2
/// ```
public enum WikilinkScanner {

  /// Scans the given text and returns all valid wikilinks found.
  ///
  /// The scanner walks through the text looking for `[[` (or `![[` for embeds).
  /// Each candidate is attempted with ``WikilinkParser``. On success the wikilink
  /// is collected and scanning continues after it; on failure the scanner advances
  /// past the failed position and keeps looking.
  ///
  /// - Parameter text: The raw Markdown text to scan.
  /// - Returns: An array of ``Wikilink`` values in the order they appear.
  public static func scan(_ text: String) -> [Wikilink] {
    var results: [Wikilink] = []
    let parser = WikilinkParser()
    var remaining = text[...]

    while let bracketRange = remaining.range(of: "[[") {
      // Check for `!` embed prefix immediately before `[[`
      var parseStart = bracketRange.lowerBound
      if parseStart > remaining.startIndex {
        let beforeBracket = remaining.index(before: parseStart)
        if remaining[beforeBracket] == "!" {
          parseStart = beforeBracket
        }
      }

      // Attempt to parse a wikilink at this position
      var candidate = remaining[parseStart...]
      do {
        let wikilink = try parser.parse(&candidate)
        results.append(wikilink)
        // Continue scanning from where the parser stopped
        remaining = candidate
      } catch {
        // Skip past the `[[` that failed and continue
        remaining = remaining[bracketRange.upperBound...]
      }
    }

    return results
  }
}
