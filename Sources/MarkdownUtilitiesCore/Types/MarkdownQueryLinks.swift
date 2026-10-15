import Foundation
import MarkdownSyntax
import Parsing

/// Ordinary occurrence discovery uses the existing Markdown AST and wikilink
/// parser. No domain interpretation is inferred from property names or links.
package enum MarkdownQueryLinks {
  package static func scan(_ record: MarkdownRecord, collection: MarkdownRelationshipCollection,
    maximum: Int,
  ) async throws -> (occurrences: [MarkdownQueryOccurrence], truncated: Bool) {
    let document = try MarkdownDocument(content: record.content)
    let source = record.context.path?.rawValue ?? ""
    var results: [MarkdownQueryOccurrence] = []
    var truncated = false
    var strings: [(String, [WikilinkPropertyComponent]?)] = []
    func walk(_ value: FrontMatterValue, path: [WikilinkPropertyComponent]) {
      switch value {
      case .string(let text): strings.append((text, path))
      case .object(let mapping):
        for key in mapping.keys.sorted() {
          if let child = mapping[key] { walk(child, path: path + [.key(key)]) }
        }
      case .array(let values):
        for (index, child) in values.enumerated() { walk(child, path: path + [.index(index)]) }
      default: break
      }
    }
    for key in document.frontMatter.keys.sorted() {
      if let value = document.frontMatter[key] { walk(value, path: [.key(key)]) }
    }
    strings.append((document.body, nil))
    let bodyOffset = record.content.utf8.count - document.body.utf8.count
    for (text, property) in strings {
      try Task.checkCancellation()
      // Both supported local-link syntaxes require an opening bracket. Plain
      // metadata values do not need an AST or a wikilink scanner invocation.
      guard text.contains("[") else { continue }
      let firstResult = results.count
      let textBytes = Array(text.utf8)
      func location(_ range: Range<Int>?) -> MarkdownQueryLocation {
        .init(region: property == nil ? "body" : "frontmatter", propertyPath: property,
          line: nil,
          decodedUTF8Range: range,
          sourceUTF8Range: property == nil ? range.map { (bodyOffset + $0.lowerBound)..<(bodyOffset + $0.upperBound) } : nil)
      }
      func append(_ value: String, syntax: String, range: Range<Int>?, resolution: CollectionWikilinkResolution) {
        guard results.count < maximum else { truncated = true; return }
        results.append(.init(id: "", source: source, sourceIdentity: record.identity,
          sourceRevision: record.revision, location: location(range), value: .string(value),
          syntax: syntax, resolution: resolution))
      }
      // AST positions also exclude code and image nodes from ordinary discovery.
      let parser = try await Markdown(text: text)
      let root = await parser.parse()
      var suppressed: [Range<Int>] = []
      var markdownLinks: [(String, Range<Int>?)] = []
      func range(_ node: any Node) -> Range<Int>? {
        guard let start = node.position.start.offset, let end = node.position.end.offset,
          start >= text.startIndex, end <= text.endIndex, start <= end else { return nil }
        // MarkdownSyntax's cmark adapter reports inclusive end offsets.
        return text[..<start].utf8.count..<min(text.utf8.count, text[..<end].utf8.count + 1)
      }
      func visit(_ node: any Node) {
        if node is Image || node is InlineCode || node is Code || node is HTML {
          if let span = range(node) { suppressed.append(span) }
          return
        }
        if let link = node as? Link {
          markdownLinks.append((link.url.absoluteString, range(link)))
          return
        }
        if let parent = node as? any Parent, let children = parent.children as? [any Node] {
          for child in children { visit(child) }
        }
      }
      visit(root)
      let matches = WikilinkScanner.scanOccurrences(text, context: .legacy,
        maximumResults: maximum == Int.max ? nil : maximum + 1)
      if matches.count > maximum { truncated = true }
      for match in matches.prefix(maximum) {
        try Task.checkCancellation()
        guard !match.link.isEmbed, !match.link.target.isEmpty,
          !match.link.target.contains(":"),
          !suppressed.contains(where: { $0.overlaps(match.utf8Range) }),
          isMarkdownTarget(match.link.target, allowExtensionless: true) else { continue }
        guard let resolution = try await collection.resolve(match.link.target, from: source) else { continue }
        guard resolution.destination != source else { continue }
        append(match.link.rawValue, syntax: "wikilink", range: match.utf8Range, resolution: resolution)
        if let last = results.indices.last, results[last].location.decodedUTF8Range == match.utf8Range {
          results[last].link = match.link
        }
      }
      for (destination, span) in markdownLinks {
        try Task.checkCancellation()
        guard let resolution = try await collection.resolve(destination, from: source, markdown: true),
          resolution.destination != source else { continue }
        let raw = span.map { String(decoding: textBytes[$0], as: UTF8.self) } ?? destination
        append(raw, syntax: "markdown", range: span, resolution: resolution)
      }
      // Preserve source order across syntaxes, not only within each scanner.
      results.replaceSubrange(firstResult..<results.count, with: results[firstResult...].sorted {
        ($0.location.decodedUTF8Range?.lowerBound ?? Int.max) < ($1.location.decodedUTF8Range?.lowerBound ?? Int.max)
      })
      if property == nil {
        var cursor = 0
        var line = record.content.utf8.prefix(bodyOffset).filter { $0 == 10 }.count + 1
        for index in firstResult..<results.count {
          guard let offset = results[index].location.decodedUTF8Range?.lowerBound else { continue }
          while cursor < offset {
            if textBytes[cursor] == 10 { line += 1 }
            cursor += 1
          }
          results[index].location.line = line
        }
      }
      if truncated { break }
    }
    return (results, truncated)
  }

  private static func isMarkdownTarget(_ target: String, allowExtensionless: Bool) -> Bool {
    let name = target.split(separator: "/").last ?? ""
    guard let dot = name.lastIndex(of: ".") else { return allowExtensionless }
    return ["md", "markdown"].contains(String(name[name.index(after: dot)...]).lowercased())
  }

  /// URL syntax is distinct from wikilink resolution: exact, source-relative,
  /// once-decoded paths with no basename or extension guessing.
  package static func resolveMarkdown(_ destination: String, source: String,
    resolver: CollectionWikilinkResolver,
  ) -> CollectionWikilinkResolution? {
    guard let (path, supported) = markdownPath(destination, source: source) else { return nil }
    let complete = resolver.namespaceComplete || resolver.completeExactPaths.contains(path)
    let found = supported && resolver.paths.contains(path) && isMarkdownTarget(path, allowExtensionless: false)
    return .init(status: !supported ? .unavailable : (!complete ? .unavailable : (found ? .resolved : .unresolved)),
      candidates: found ? [path] : [], namespaceComplete: supported && complete, query: destination)
  }

  package static func markdownPath(_ destination: String, source: String) -> (path: String, supported: Bool)? {
    var input = destination[...]
    guard let prefix = try? Prefix<Substring> { $0 != "#" && $0 != "?" }.parse(&input) else { return nil }
    let encoded = String(prefix)
    guard !encoded.isEmpty, !encoded.contains(":"),
      let decoded = encoded.removingPercentEncoding,
      isMarkdownTarget(decoded, allowExtensionless: true) else { return nil }
    var components = source.split(separator: "/").dropLast().map(String.init)
    var supported = !decoded.hasPrefix("/") && !decoded.contains("\\") && !decoded.contains("\0")
    for part in decoded.split(separator: "/") {
      if part == "." { continue }
      if part == ".." {
        if components.isEmpty { supported = false } else { components.removeLast() }
      } else { components.append(String(part)) }
    }
    let path = components.joined(separator: "/")
    return (path, supported)
  }
}

/// Explicit list syntax; BOM policy is intentionally not implemented here (#189).
public struct MarkdownQueryFileListParser: Parsing.Parser {
  public let nulDelimited: Bool
  public init(nulDelimited: Bool) { self.nulDelimited = nulDelimited }
  public func parse(_ input: inout Substring) throws -> [String] {
    let delimiter: Character = nulDelimited ? "\0" : "\n"
    var result: [String] = []
    while !input.isEmpty {
      let part = try Prefix<Substring> { $0 != delimiter }.parse(&input)
      if !nulDelimited && part.contains("\r") { throw MarkdownQueryInputError("File lists require LF separators; CRLF is unsupported. Use LF or --files-from0.") }
      if !part.isEmpty { result.append(String(part)) }
      guard result.count <= 100_000 else { throw MarkdownQueryInputError("File-set input exceeds 100000 entries") }
      if !input.isEmpty { input.removeFirst() }
    }
    return result
  }
}

public struct MarkdownQueryInputError: Error, LocalizedError, Sendable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}
