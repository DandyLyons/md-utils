//
//  WikilinkScanner.swift
//  MarkdownUtilities
//

/// Scans raw Markdown text to extract all wikilinks.
///
/// This is a caseless enum namespace (no instances). Use ``scan(_:context:)`` to find
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
  /// Each candidate is parsed with the package's wikilink parser. On success the wikilink
  /// is collected and scanning continues after it; on failure the scanner advances
  /// past the failed position and keeps looking.
  ///
  /// Context selects grammar, not Markdown regions: this raw scanner does not
  /// exclude code spans/fences or automatically identify table cells.
  ///
  /// - Parameters:
  ///   - text: The raw Markdown text to scan.
  ///   - context: Source escaping and syntax validity rules. Defaults to standard text.
  /// - Returns: An array of ``Wikilink`` values in the order they appear.
  public static func scan(
    _ text: String,
    context: WikilinkParsingContext = .standard,
  ) -> [Wikilink] {
    scanOccurrences(text, context: context).map(\.link)
  }

  /// Scans with zero-based, half-open UTF-8 ranges relative to the supplied text.
  /// The ranges include embed prefixes and delimiters. They are not file offsets
  /// when the supplied text is a decoded frontmatter scalar or a document body.
  /// `maximumResults` bounds retained matches; callers needing a truncation
  /// indicator can request one sentinel match beyond their own output limit.
  public static func scanOccurrences(
    _ text: String,
    context: WikilinkParsingContext = .standard,
    maximumResults: Int? = nil,
  ) -> [WikilinkTextOccurrence] {
    var results: [WikilinkTextOccurrence] = []
    let parser = WikilinkParser(context: context)
    var remaining = text[...]
    var consumedBytes = 0

    while let bracketRange = remaining.range(of: "[[") {
      if let maximumResults, results.count >= maximumResults { break }
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
        let start = consumedBytes + remaining[..<parseStart].utf8.count
        let end = start + remaining[parseStart..<candidate.startIndex].utf8.count
        results.append(.init(link: wikilink, utf8Range: start..<end))
        // Continue scanning from where the parser stopped
        consumedBytes = end
        remaining = candidate
      } catch {
        // Skip past the `[[` that failed and continue
        consumedBytes += remaining[..<bracketRange.upperBound].utf8.count
        remaining = remaining[bracketRange.upperBound...]
      }
    }

    return results
  }
}
