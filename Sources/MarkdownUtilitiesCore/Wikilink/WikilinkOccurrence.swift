/// One scanner match in the exact string passed to the scanner.
public struct WikilinkTextOccurrence: Equatable, Sendable, Codable {
  public let link: Wikilink
  /// Zero-based, half-open UTF-8 byte range in the scanned string.
  public let utf8Range: Range<Int>
}

/// A literal property key or array index; punctuation in keys has no path syntax.
public enum WikilinkPropertyComponent: Hashable, Sendable, Codable {
  case key(String)
  case index(Int)

  public var jsonValue: JSONValue {
    switch self {
    case .key(let key): .object(["key": .string(key)])
    case .index(let index): .object(["index": .integer(index)])
    }
  }
}

/// Identifies both the origin and the coordinate space of an occurrence.
public enum WikilinkOccurrenceOrigin: Equatable, Sendable, Codable {
  /// Ranges refer to the decoded string selected by this concrete property path.
  case frontMatter(path: [WikilinkPropertyComponent])
  /// Ranges refer to the document body, starting at byte zero of that body.
  case body
}

/// A discovered link, without asserting a scalar or relationship contract.
public struct WikilinkOccurrence: Equatable, Sendable, Codable {
  /// The immutable record snapshot, when extraction was requested on a record.
  /// Identity, revision, logical path and host context are retained without I/O.
  public let source: MarkdownRecord?
  public let origin: WikilinkOccurrenceOrigin
  public let link: Wikilink
  public let context: WikilinkParsingContext
  /// Complete scanned scalar or body, before any edits.
  public let text: String
  /// Zero-based, half-open UTF-8 range in `text`, never implicitly in a file.
  public let utf8Range: Range<Int>
  /// UTF-8 range in `source.content`, available only for record body matches.
  /// YAML/TOML decoding can change bytes; frontmatter ranges are never fabricated.
  public let sourceUTF8Range: Range<Int>?
}

extension MarkdownDocument {
  /// Discovers valid embedded links, frontmatter first and then body order.
  /// Mapping traversal follows the decoded mapping order, not a promise of raw
  /// YAML/TOML key order. Arrays and matches within strings preserve order and
  /// duplicates. Malformed candidates and nonstrings are skipped, as in `wikilinks`.
  /// This is discovery, not whole-value scalar or declared relationship validation.
  public func wikilinkOccurrences(
    context: WikilinkParsingContext = .legacy,
  ) -> [WikilinkOccurrence] {
    collectWikilinkOccurrences(context: context, source: nil)
  }

  fileprivate func collectWikilinkOccurrences(
    context: WikilinkParsingContext,
    source: MarkdownRecord?,
  ) -> [WikilinkOccurrence] {
    var results: [WikilinkOccurrence] = []
    func scan(_ text: String, origin: WikilinkOccurrenceOrigin) {
      for match in WikilinkScanner.scanOccurrences(text, context: context) {
        let rawRange: Range<Int>?
        if case .body = origin, let source {
          let offset = source.content.utf8.count - body.utf8.count
          rawRange = (offset + match.utf8Range.lowerBound)..<(offset + match.utf8Range.upperBound)
        } else {
          rawRange = nil
        }
        results.append(.init(
          source: source, origin: origin, link: match.link, context: context,
          text: text, utf8Range: match.utf8Range, sourceUTF8Range: rawRange,
        ))
      }
    }
    func walk(_ value: FrontMatterValue, path: [WikilinkPropertyComponent]) {
      switch value {
      case .string(let text): scan(text, origin: .frontMatter(path: path))
      case .object(let mapping):
        for (key, value) in mapping { walk(value, path: path + [.key(key)]) }
      case .array(let values):
        for (index, value) in values.enumerated() { walk(value, path: path + [.index(index)]) }
      default: break
      }
    }
    for (key, value) in frontMatter { walk(value, path: [.key(key)]) }
    scan(body, origin: .body)
    return results
  }
}

extension MarkdownRecord {
  /// Parses this snapshot and discovers links with source identity and revision.
  /// Invalid frontmatter throws rather than silently returning incomplete results.
  /// Body matches additionally carry raw content byte ranges. Frontmatter edits
  /// must use the structured path and decoded scalar, then serialize through a codec.
  public func wikilinkOccurrences(
    context: WikilinkParsingContext = .legacy,
  ) throws -> [WikilinkOccurrence] {
    try MarkdownDocument(content: content).collectWikilinkOccurrences(context: context, source: self)
  }
}
