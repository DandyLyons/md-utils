import Foundation
import Parsing

/// Parses fm-var custom elements from one immutable Markdown source snapshot.
///
/// The parser conforms to swift-parsing's `Parser` protocol with `Substring` input. It consumes the
/// complete input, retains the exact source in ``FMVarParseResult``, and recovers after malformed
/// candidates so later elements remain available. See <doc:ParsingFMVarElements> for accepted
/// Markdown contexts and recovery behavior.
public struct FMVarParser: Parsing.Parser {
  public typealias Input = Substring
  public typealias Output = FMVarParseResult

  /// Creates a lossless fm-var parser.
  public init() {}

  /// Parses and consumes a complete Markdown source snapshot.
  ///
  /// - Parameter input: Markdown source beginning at the parser's current position.
  /// - Returns: Lossless elements, normalized declarations, and deterministic diagnostics.
  /// - Throws: ``FMVarSourceLocationError`` if an internal source range cannot be represented.
  public func parse(
    _ input: inout Substring
  ) throws(FMVarSourceLocationError) -> FMVarParseResult {
    let source = String(input)
    input = input[input.endIndex...]
    return try parseSource(source)
  }

  /// Convenience entry point for parsing a complete Swift string.
  ///
  /// - Parameter source: Complete Markdown source to retain as the immutable parse snapshot.
  /// - Returns: Lossless elements, normalized declarations, and deterministic diagnostics.
  /// - Throws: ``FMVarSourceLocationError`` if an internal source range cannot be represented.
  public func parse(
    _ source: String
  ) throws(FMVarSourceLocationError) -> FMVarParseResult {
    var input = Substring(source)
    return try parse(&input)
  }

  /// Builds all snapshot-scoped parser state and runs lexical and semantic parsing.
  ///
  /// Keeping the source map and Markdown context tied to the same string prevents ranges from
  /// crossing snapshots while the lower parser layers work exclusively with UTF-8 offsets.
  ///
  /// - Parameter source: Complete immutable Markdown source snapshot.
  /// - Returns: Lossless elements, normalized declarations, and diagnostics for `source`.
  /// - Throws: ``FMVarSourceLocationError`` if a derived source range violates map invariants.
  private func parseSource(
    _ source: String
  ) throws(FMVarSourceLocationError) -> FMVarParseResult {
    let context = FMVarMarkdownContext(source: source)
    let sourceMap = FMVarSourceMap(source: source)
    let tokens = try tokenize(context: context, sourceMap: sourceMap)
    return try assemble(
      source: source,
      context: context,
      sourceMap: sourceMap,
      tokens: tokens
    )
  }

  /// Scans non-excluded Markdown bytes and parses every fm-var lexical candidate.
  ///
  /// Non-candidates advance by one byte, while recognized tags consume their full lexical range.
  /// Escaped element-shaped text is skipped through its matching closing tag so inner text cannot
  /// be mistaken for live fm-var markup.
  ///
  /// - Parameters:
  ///   - context: Precomputed Markdown exclusions and UTF-8 source bytes.
  ///   - sourceMap: Coordinate map created from the same source as `context`.
  /// - Returns: Opening and closing tokens in source order.
  /// - Throws: ``FMVarSourceLocationError`` if a token or attribute range cannot be represented.
  private func tokenize(
    context: FMVarMarkdownContext,
    sourceMap: FMVarSourceMap
  ) throws(FMVarSourceLocationError) -> [FMVarTagToken] {
    let bytes = context.bytes
    var tokens: [FMVarTagToken] = []
    var cursor = 0
    let tagParser = FMVarLexicalTagParser(sourceMap: sourceMap)

    while cursor < bytes.count {
      guard bytes[cursor] == ASCII.lessThan, context.isExcluded(cursor) == false else {
        cursor += 1
        continue
      }

      if context.isEscaped(cursor) {
        cursor = escapedElementEnd(startingAt: cursor, context: context) ?? cursor + 1
        continue
      }

      var candidate = bytes[cursor...]
      do {
        let token = try tagParser.parse(&candidate)
        tokens.append(token)
        cursor = max(candidate.startIndex, cursor + 1)
      } catch {
        switch error {
        case .notCandidate:
          cursor += 1
        case .sourceLocation(let error):
          throw error
        }
      }
    }

    return tokens
  }

  /// Locates the byte after a closing tag for escaped element-shaped source.
  ///
  /// - Parameters:
  ///   - start: Offset of an escaped `<` byte.
  ///   - context: Markdown context containing the complete UTF-8 source.
  /// - Returns: The first offset after the matching closing tag, or `nil` when the source does not
  ///   start with a supported element name or has no closing tag.
  private func escapedElementEnd(
    startingAt start: Int,
    context: FMVarMarkdownContext
  ) -> Int? {
    let bytes = context.bytes
    let nameStart = start + 1
    guard nameStart < bytes.count,
      let kind = FMVarElementKind.allCases.first(where: {
        let name = Array($0.rawValue.utf8)
        return nameStart + name.count <= bytes.count
          && bytes[nameStart..<(nameStart + name.count)].elementsEqual(name)
      })
    else { return nil }

    let closing = Array("</\(kind.rawValue)>".utf8)
    var cursor = nameStart + kind.rawValue.utf8.count
    while cursor + closing.count <= bytes.count {
      if bytes[cursor..<(cursor + closing.count)].elementsEqual(closing) {
        return cursor + closing.count
      }
      cursor += 1
    }
    return nil
  }

  /// Pairs lexical tags, builds declarations, and adds semantic and placement diagnostics.
  ///
  /// Opening tags determine element ordinals. Malformed or unmatched openings still produce
  /// elements, preserving deterministic recovery and allowing subsequent tags to be analyzed.
  ///
  /// - Parameters:
  ///   - source: Exact source retained by the result.
  ///   - context: Markdown-aware byte context for content and placement validation.
  ///   - sourceMap: Coordinate map for `source`.
  ///   - tokens: Lexical tags in source order.
  /// - Returns: Fully assembled parse output.
  /// - Throws: ``FMVarSourceLocationError`` if a combined element or cache range is invalid.
  private func assemble(
    source: String,
    context: FMVarMarkdownContext,
    sourceMap: FMVarSourceMap,
    tokens: [FMVarTagToken]
  ) throws(FMVarSourceLocationError) -> FMVarParseResult {
    var elements: [FMVarElement] = []
    var declarations: [FMVarParsedDeclaration] = []
    var diagnostics: [FMVarDiagnostic] = []
    var consumedClosings: Set<Int> = []
    var diagnosedClosings: Set<Int> = []
    var ordinal = 0

    for tokenIndex in tokens.indices where tokens[tokenIndex].direction == .opening {
      let opening = tokens[tokenIndex]
      let elementOrdinal = ordinal
      ordinal += 1
      diagnostics.append(contentsOf: opening.diagnosticSeeds.map {
        $0.diagnostic(ordinal: elementOrdinal, kind: opening.kind)
      })

      let pairing = structuralPairing(for: tokenIndex, in: tokens)
      let closingIndex: Int?
      if opening.isMalformed || opening.isSelfClosing {
        closingIndex = nil
      } else {
        closingIndex = pairing.closingIndex
      }

      if let obstacleIndex = pairing.obstacleIndex, closingIndex == nil {
        let obstacle = tokens[obstacleIndex]
        if obstacle.direction == .opening {
          diagnostics.append(FMVarDiagnostic(
            code: .nestedElement,
            severity: .error,
            range: obstacle.range,
            elementOrdinal: elementOrdinal,
            elementKind: opening.kind,
            message: "fm-var family elements must not be nested"
          ))
        } else {
          diagnostics.append(FMVarDiagnostic(
            code: .mismatchedClosingTag,
            severity: .error,
            range: obstacle.range,
            elementOrdinal: elementOrdinal,
            elementKind: opening.kind,
            message: "Expected </\(opening.kind.rawValue)> before \(obstacle.rawText)"
          ))
          diagnosedClosings.insert(obstacleIndex)
        }
      }

      let element: FMVarElement
      if let closingIndex {
        let closing = tokens[closingIndex]
        consumedClosings.insert(closingIndex)
        element = FMVarElement(
          kind: opening.kind,
          ordinal: elementOrdinal,
          attributes: opening.attributes,
          range: try sourceMap.range(
            fromUTF8Offset: opening.range.start.utf8Offset,
            toUTF8Offset: closing.range.end.utf8Offset
          ),
          openingTagRange: opening.range,
          cacheRange: try sourceMap.range(
            fromUTF8Offset: opening.range.end.utf8Offset,
            toUTF8Offset: closing.range.start.utf8Offset
          ),
          closingTagRange: closing.range
        )
      } else {
        element = FMVarElement(
          kind: opening.kind,
          ordinal: elementOrdinal,
          attributes: opening.attributes,
          range: opening.range,
          openingTagRange: opening.range
        )
        diagnostics.append(FMVarDiagnostic(
          code: .missingClosingTag,
          severity: .error,
          range: opening.range,
          elementOrdinal: elementOrdinal,
          elementKind: opening.kind,
          message: "<\(opening.kind.rawValue)> requires an explicit closing tag"
        ))
      }

      let declarationResult = FMVarDeclarationBuilder.build(
        for: element,
        openingTagRange: opening.range
      )
      diagnostics.append(contentsOf: declarationResult.diagnostics)
      if let declaration = declarationResult.declaration {
        declarations.append(FMVarParsedDeclaration(
          elementOrdinal: elementOrdinal,
          declaration: declaration
        ))
      }
      elements.append(element)
    }

    for tokenIndex in tokens.indices
    where tokens[tokenIndex].direction == .closing
      && consumedClosings.contains(tokenIndex) == false
      && diagnosedClosings.contains(tokenIndex) == false
    {
      let token = tokens[tokenIndex]
      diagnostics.append(contentsOf: token.diagnosticSeeds.map {
        $0.diagnostic(ordinal: nil, kind: token.kind)
      })
      diagnostics.append(FMVarDiagnostic(
        code: .unexpectedClosingTag,
        severity: .error,
        range: token.range,
        elementKind: token.kind,
        message: "\(token.rawText) has no compatible opening element"
      ))
    }

    diagnostics.append(contentsOf: try contentDiagnostics(
      elements: elements,
      declarations: declarations,
      context: context,
      sourceMap: sourceMap
    ))
    diagnostics.append(contentsOf: placementDiagnostics(
      elements: elements,
      declarations: declarations,
      context: context
    ))

    return FMVarParseResult(
      source: source,
      elements: elements,
      declarations: declarations,
      diagnostics: diagnostics
    )
  }

  /// Finds the first structural token after an opening tag.
  ///
  /// Nesting is prohibited, so any intervening opening or mismatched closing tag is an obstacle
  /// instead of something the parser skips while searching farther ahead.
  ///
  /// - Parameters:
  ///   - openingIndex: Index of an opening token in `tokens`.
  ///   - tokens: All lexical tokens in source order.
  /// - Returns: Either a compatible closing index, an obstacle index, or neither at end of input.
  private func structuralPairing(
    for openingIndex: Int,
    in tokens: [FMVarTagToken]
  ) -> (closingIndex: Int?, obstacleIndex: Int?) {
    let opening = tokens[openingIndex]
    guard openingIndex + 1 < tokens.count else { return (nil, nil) }

    for candidateIndex in (openingIndex + 1)..<tokens.count {
      let candidate = tokens[candidateIndex]
      if candidate.direction == .opening {
        return (nil, candidateIndex)
      }
      if candidate.kind == opening.kind, candidate.isMalformed == false {
        return (candidateIndex, nil)
      }
      return (nil, candidateIndex)
    }
    return (nil, nil)
  }

  /// Validates cached content according to each successfully normalized declaration.
  ///
  /// - Parameters:
  ///   - elements: Lossless elements whose cache ranges identify candidate content.
  ///   - declarations: Successfully normalized declarations keyed by element ordinal.
  ///   - context: Source bytes used for allocation-free cache inspection.
  ///   - sourceMap: Coordinate map used to pinpoint an invalid byte.
  /// - Returns: Content diagnostics in element order.
  /// - Throws: ``FMVarSourceLocationError`` if a diagnostic byte range cannot be represented.
  private func contentDiagnostics(
    elements: [FMVarElement],
    declarations: [FMVarParsedDeclaration],
    context: FMVarMarkdownContext,
    sourceMap: FMVarSourceMap
  ) throws(FMVarSourceLocationError) -> [FMVarDiagnostic] {
    var diagnostics: [FMVarDiagnostic] = []
    let bytes = context.bytes

    for element in elements {
      guard let cacheRange = element.cacheRange else { continue }
      let cache = cacheRange.start.utf8Offset..<cacheRange.end.utf8Offset
      switch element.kind {
      case .variable:
        if let invalidOffset = firstInvalidInlineCacheByte(in: cache, bytes: bytes) {
          diagnostics.append(invalidContentDiagnostic(
            element: element,
            range: try sourceMap.range(fromUTF8Offset: invalidOffset, toUTF8Offset: invalidOffset + 1),
            message: "Scalar caches must contain serialized literal text only"
          ))
        }
      case .list:
        guard case .list(let declaration)? = declaration(
          for: element.ordinal,
          in: declarations
        ) else { continue }
        switch declaration.format {
        case .ordered, .unordered:
          let expectedName = declaration.format == .ordered ? "ol" : "ul"
          if validBlockListCache(in: cache, expectedName: expectedName, bytes: bytes) == false {
            diagnostics.append(invalidContentDiagnostic(
              element: element,
              range: cacheRange,
              message: "Block list cache must contain one escaped <\(expectedName)> list"
            ))
          }
        case .conjunction, .disjunction, .unit:
          if let invalidOffset = firstInvalidInlineCacheByte(in: cache, bytes: bytes) {
            diagnostics.append(invalidContentDiagnostic(
              element: element,
              range: try sourceMap.range(
                fromUTF8Offset: invalidOffset,
                toUTF8Offset: invalidOffset + 1
              ),
              message: "Inline list caches must contain serialized literal text only"
            ))
          }
        }
      case .format:
        if bytes[cache].contains(where: { ASCII.isWhitespace($0) == false }) {
          diagnostics.append(invalidContentDiagnostic(
            element: element,
            range: cacheRange,
            message: "<fm-format> must not contain cached children"
          ))
        }
      }
    }
    return diagnostics
  }

  /// Enforces block-list and configuration-element placement rules.
  ///
  /// - Parameters:
  ///   - elements: Parsed elements in source order.
  ///   - declarations: Normalized declarations needed to distinguish block list formats.
  ///   - context: Line and front-matter context for standalone and configuration-prefix checks.
  /// - Returns: Placement diagnostics in element order.
  private func placementDiagnostics(
    elements: [FMVarElement],
    declarations: [FMVarParsedDeclaration],
    context: FMVarMarkdownContext
  ) -> [FMVarDiagnostic] {
    var diagnostics: [FMVarDiagnostic] = []

    for element in elements where element.kind == .list {
      guard case .list(let declaration)? = declaration(
        for: element.ordinal,
        in: declarations
      ), declaration.format == .ordered || declaration.format == .unordered,
        let closingRange = element.closingTagRange
      else { continue }

      let openingOffsets = element.openingTagRange.start.utf8Offset..<element.openingTagRange.end.utf8Offset
      let closingOffsets = closingRange.start.utf8Offset..<closingRange.end.utf8Offset
      if context.isStandalone(openingOffsets) == false
        || context.isStandalone(closingOffsets) == false
      {
        diagnostics.append(FMVarDiagnostic(
          code: .invalidPlacement,
          severity: .error,
          range: element.range,
          elementOrdinal: element.ordinal,
          elementKind: element.kind,
          message: "Ordered and unordered <fm-list> tags must stand on their own lines"
        ))
      }
    }

    let formatElements = elements.filter { $0.kind == .format }
    guard formatElements.isEmpty == false else { return diagnostics }
    var configurationCursor = context.yamlFrontMatterEnd
    var ordinaryContentSeen = configurationCursor == nil

    for element in formatElements {
      let elementStart = element.range.start.utf8Offset
      let elementEnd = element.range.end.utf8Offset
      let offsets = elementStart..<elementEnd
      if let cursor = configurationCursor {
        if context.isOnlyWhitespace(from: cursor, to: elementStart) == false {
          ordinaryContentSeen = true
        }
      }

      if ordinaryContentSeen || context.isStandalone(offsets) == false {
        let message = context.yamlFrontMatterEnd == nil
          ? "<fm-format> requires YAML frontmatter and must precede ordinary content"
          : "<fm-format> must be top-level immediately after YAML frontmatter"
        diagnostics.append(FMVarDiagnostic(
          code: .invalidPlacement,
          severity: .error,
          range: element.range,
          elementOrdinal: element.ordinal,
          elementKind: element.kind,
          message: message
        ))
      }
      configurationCursor = elementEnd
    }

    return diagnostics
  }

  /// Looks up the normalized declaration corresponding to a lossless element.
  ///
  /// - Parameters:
  ///   - ordinal: Element ordinal assigned during assembly.
  ///   - declarations: Successfully normalized declaration associations.
  /// - Returns: The matching declaration, or `nil` when semantic validation failed.
  private func declaration(
    for ordinal: Int,
    in declarations: [FMVarParsedDeclaration]
  ) -> FMVarDeclaration? {
    declarations.first(where: { $0.elementOrdinal == ordinal })?.declaration
  }

  /// Locates markup or XML-invalid content that cannot appear in an inline literal cache.
  ///
  /// Valid XML entity references are skipped as complete units. Markdown delimiters, raw angle
  /// brackets, line endings, invalid entities, and invalid XML scalars are rejected.
  ///
  /// - Parameters:
  ///   - range: Cache byte range to inspect.
  ///   - bytes: Complete source snapshot.
  /// - Returns: First invalid absolute UTF-8 offset, or `nil` for valid literal content.
  private func firstInvalidInlineCacheByte(
    in range: Range<Int>,
    bytes: [UInt8]
  ) -> Int? {
    if let invalidScalarOffset = firstInvalidXMLScalarByte(in: range, bytes: bytes) {
      return invalidScalarOffset
    }
    let rawDelimiters: Set<UInt8> = [
      ASCII.lessThan, ASCII.greaterThan, ASCII.backslash, ASCII.backtick,
      0x2A, 0x5F, ASCII.tilde, 0x5B, 0x5D, 0x7C,
      ASCII.lineFeed, ASCII.carriageReturn,
    ]
    var cursor = range.lowerBound
    while cursor < range.upperBound {
      let byte = bytes[cursor]
      if rawDelimiters.contains(byte) { return cursor }
      if byte == ASCII.ampersand {
        guard let entityEnd = XMLEntityDecoder.entityEnd(
          in: bytes,
          from: cursor,
          before: range.upperBound
        ) else { return cursor }
        cursor = entityEnd
      } else {
        cursor += 1
      }
    }
    return nil
  }

  /// Checks the constrained HTML serialization allowed for a block list cache.
  ///
  /// The cache must contain exactly one expected `ol` or `ul` container whose only children are
  /// `li` elements containing XML-valid escaped text. Arbitrary nested HTML is rejected.
  ///
  /// - Parameters:
  ///   - range: Cache byte range to validate after trimming outer whitespace.
  ///   - expectedName: Required container name, either `ol` or `ul`.
  ///   - bytes: Complete source snapshot.
  /// - Returns: `true` when the cache matches the block-list serialization contract.
  private func validBlockListCache(
    in range: Range<Int>,
    expectedName: String,
    bytes: [UInt8]
  ) -> Bool {
    let trimmed = trimWhitespace(range, bytes: bytes)
    let opening = Array("<\(expectedName)>".utf8)
    let closing = Array("</\(expectedName)>".utf8)
    guard hasPrefix(opening, at: trimmed.lowerBound, before: trimmed.upperBound, bytes: bytes),
      hasSuffix(closing, in: trimmed, bytes: bytes)
    else { return false }

    let childrenStart = trimmed.lowerBound + opening.count
    let childrenEnd = trimmed.upperBound - closing.count
    var cursor = childrenStart
    let itemOpen = Array("<li>".utf8)
    let itemClose = Array("</li>".utf8)
    while cursor < childrenEnd {
      while cursor < childrenEnd, ASCII.isWhitespace(bytes[cursor]) { cursor += 1 }
      if cursor == childrenEnd { return true }
      guard hasPrefix(itemOpen, at: cursor, before: childrenEnd, bytes: bytes) else { return false }
      cursor += itemOpen.count
      guard let itemEnd = find(itemClose, in: bytes, from: cursor, before: childrenEnd) else {
        return false
      }
      if validHTMLText(in: cursor..<itemEnd, bytes: bytes) == false { return false }
      cursor = itemEnd + itemClose.count
    }
    return true
  }

  /// Validates the escaped text content of one serialized list item.
  ///
  /// - Parameters:
  ///   - range: Bytes between `<li>` and `</li>`.
  ///   - bytes: Complete source snapshot.
  /// - Returns: `true` for XML 1.0 text containing no raw tags or line breaks.
  private func validHTMLText(in range: Range<Int>, bytes: [UInt8]) -> Bool {
    guard firstInvalidXMLScalarByte(in: range, bytes: bytes) == nil else { return false }
    var cursor = range.lowerBound
    while cursor < range.upperBound {
      switch bytes[cursor] {
      case ASCII.lessThan, ASCII.greaterThan, ASCII.lineFeed, ASCII.carriageReturn:
        return false
      case ASCII.ampersand:
        guard let entityEnd = XMLEntityDecoder.entityEnd(
          in: bytes,
          from: cursor,
          before: range.upperBound
        ) else { return false }
        cursor = entityEnd
      default:
        cursor += 1
      }
    }
    return true
  }

  /// Finds the first byte belonging to an invalid UTF-8 or XML 1.0 scalar.
  ///
  /// - Parameters:
  ///   - range: UTF-8 byte range to decode and inspect.
  ///   - bytes: Complete source snapshot.
  /// - Returns: Absolute offset of the invalid scalar, the range start for malformed UTF-8, or
  ///   `nil` when all scalars are allowed by XML 1.0.
  private func firstInvalidXMLScalarByte(in range: Range<Int>, bytes: [UInt8]) -> Int? {
    guard let text = String(bytes: bytes[range], encoding: .utf8) else { return range.lowerBound }
    var offset = range.lowerBound
    for scalar in text.unicodeScalars {
      if XMLEntityDecoder.isXML10Scalar(scalar.value) == false { return offset }
      offset += scalar.utf8.count
    }
    return nil
  }

  /// Narrows a byte range by removing leading and trailing ASCII whitespace.
  private func trimWhitespace(_ range: Range<Int>, bytes: [UInt8]) -> Range<Int> {
    var start = range.lowerBound
    var end = range.upperBound
    while start < end, ASCII.isWhitespace(bytes[start]) { start += 1 }
    while end > start, ASCII.isWhitespace(bytes[end - 1]) { end -= 1 }
    return start..<end
  }

  /// Checks for an exact byte prefix without reading past a caller-supplied boundary.
  private func hasPrefix(
    _ prefix: [UInt8],
    at start: Int,
    before end: Int,
    bytes: [UInt8]
  ) -> Bool {
    start + prefix.count <= end
      && bytes[start..<(start + prefix.count)].elementsEqual(prefix)
  }

  /// Checks whether a bounded byte range ends with an exact suffix.
  private func hasSuffix(_ suffix: [UInt8], in range: Range<Int>, bytes: [UInt8]) -> Bool {
    range.count >= suffix.count
      && bytes[(range.upperBound - suffix.count)..<range.upperBound].elementsEqual(suffix)
  }

  /// Finds an exact byte sequence within a bounded half-open source region.
  ///
  /// - Returns: Absolute offset of the first match, or `nil` when no complete match fits.
  private func find(
    _ needle: [UInt8],
    in bytes: [UInt8],
    from start: Int,
    before end: Int
  ) -> Int? {
    guard needle.isEmpty == false, start <= end - needle.count else { return nil }
    for offset in start...(end - needle.count)
    where bytes[offset..<(offset + needle.count)].elementsEqual(needle) {
      return offset
    }
    return nil
  }

  /// Creates a consistently associated invalid-cache diagnostic for one element.
  private func invalidContentDiagnostic(
    element: FMVarElement,
    range: FMVarSourceRange,
    message: String
  ) -> FMVarDiagnostic {
    FMVarDiagnostic(
      code: .invalidContent,
      severity: .error,
      range: range,
      elementOrdinal: element.ordinal,
      elementKind: element.kind,
      message: message
    )
  }
}

/// Errors used internally to separate scan misses from source-coordinate failures.
private enum FMVarLexicalParserError: Error {
  /// The current `<` byte does not begin a supported fm-var family tag.
  case notCandidate
  /// A recognized candidate produced a range that the snapshot map could not represent.
  case sourceLocation(FMVarSourceLocationError)
}

/// Whether a lexical token begins or ends an fm-var family element.
private enum FMVarTagDirection: Equatable {
  /// A tag beginning with `<name`.
  case opening
  /// A tag beginning with `</name`.
  case closing
}

/// Lossless lexical information for one recognized opening or closing tag.
private struct FMVarTagToken {
  /// Whether the token opens or closes an element.
  let direction: FMVarTagDirection
  /// Supported fm-var family tag name.
  let kind: FMVarElementKind
  /// Exact UTF-8 text consumed for the token.
  let rawText: String
  /// Half-open range covering `rawText` in the source snapshot.
  let range: FMVarSourceRange
  /// Authored attributes, retained only for opening tags.
  let attributes: [FMVarRawAttribute]
  /// Whether the opening tag used unsupported `/>` syntax.
  let isSelfClosing: Bool
  /// Whether structural tag syntax prevents safe pairing.
  let isMalformed: Bool
  /// Recoverable lexical errors to materialize after an element ordinal is known.
  let diagnosticSeeds: [FMVarDiagnosticSeed]
}

/// A lexical diagnostic awaiting the element identity assigned during assembly.
private struct FMVarDiagnosticSeed {
  /// Stable machine-readable diagnostic code.
  let code: FMVarDiagnosticCode
  /// Exact source range responsible for the diagnostic.
  let range: FMVarSourceRange
  /// Human-readable explanation of the lexical failure.
  let message: String

  /// Associates this lexical failure with its assembled element, when one exists.
  ///
  /// - Parameters:
  ///   - ordinal: Element ordinal assigned to an opening token, or `nil` for an unmatched closing
  ///     token.
  ///   - kind: Supported fm-var family element kind recognized by the lexer.
  /// - Returns: An error diagnostic with the seed's stable code, range, and message.
  func diagnostic(ordinal: Int?, kind: FMVarElementKind) -> FMVarDiagnostic {
    FMVarDiagnostic(
      code: code,
      severity: .error,
      range: range,
      elementOrdinal: ordinal,
      elementKind: kind,
      message: message
    )
  }
}

/// swift-parsing parser for one lexical opening or closing tag at the start of a UTF-8 slice.
private struct FMVarLexicalTagParser: Parsing.Parser {
  /// UTF-8 bytes beginning at the scan cursor.
  typealias Input = ArraySlice<UInt8>
  /// One lossless recognized tag.
  typealias Output = FMVarTagToken

  /// Coordinate map for translating lexical byte offsets into source ranges.
  let sourceMap: FMVarSourceMap

  /// Parses one supported opening or closing tag from the start of a UTF-8 slice.
  ///
  /// A recognized malformed tag is consumed and returned with diagnostic seeds so parsing can
  /// recover. A slice that does not start with a supported tag throws `notCandidate` without
  /// consuming input.
  ///
  /// - Parameter input: Remaining source bytes beginning at a possible `<` candidate.
  /// - Returns: The recognized lossless lexical tag.
  /// - Throws: ``FMVarLexicalParserError`` for a scan miss or source-coordinate failure.
  func parse(
    _ input: inout ArraySlice<UInt8>
  ) throws(FMVarLexicalParserError) -> FMVarTagToken {
    let original = input
    let start = original.startIndex
    guard original.first == ASCII.lessThan else { throw FMVarLexicalParserError.notCandidate }
    var cursor = start + 1
    let direction: FMVarTagDirection
    if cursor < original.endIndex, original[cursor] == ASCII.slash {
      direction = .closing
      cursor += 1
    } else {
      direction = .opening
    }

    guard let kind = FMVarElementKind.allCases.first(where: {
      let name = Array($0.rawValue.utf8)
      return cursor + name.count <= original.endIndex
        && original[cursor..<(cursor + name.count)].elementsEqual(name)
    }) else { throw FMVarLexicalParserError.notCandidate }
    cursor += kind.rawValue.utf8.count
    let hasValidNameBoundary = isTagBoundary(
      at: cursor,
      direction: direction,
      input: original
    )
    if hasValidNameBoundary == false,
      cursor < original.endIndex,
      ASCII.isAttributeNameByte(original[cursor])
    {
      throw FMVarLexicalParserError.notCandidate
    }

    let boundary = tagBoundary(startingAt: cursor, input: original)
    let tokenEnd = max(boundary.end, cursor)
    let tagRange = try sourceRange(from: start, to: tokenEnd)
    let rawText = String(decoding: original[start..<tokenEnd], as: UTF8.self)
    input = original[tokenEnd...]

    if direction == .closing {
      var seeds: [FMVarDiagnosticSeed] = []
      let interiorEnd = boundary.hasTerminator ? tokenEnd - 1 : tokenEnd
      let remainder = trimWhitespace(cursor..<interiorEnd, input: original)
      if boundary.hasTerminator == false || remainder.isEmpty == false {
        seeds.append(FMVarDiagnosticSeed(
          code: .malformedTag,
          range: tagRange,
          message: "Malformed closing tag for </\(kind.rawValue)>"
        ))
      }
      if hasValidNameBoundary == false {
        seeds.append(FMVarDiagnosticSeed(
          code: .malformedTag,
          range: tagRange,
          message: "Invalid character after </\(kind.rawValue)> tag name"
        ))
      }
      return FMVarTagToken(
        direction: direction,
        kind: kind,
        rawText: rawText,
        range: tagRange,
        attributes: [],
        isSelfClosing: false,
        isMalformed: seeds.isEmpty == false,
        diagnosticSeeds: seeds
      )
    }

    let attributeEnd = boundary.hasTerminator ? tokenEnd - 1 : tokenEnd
    let parsedAttributes = try parseAttributes(
      in: cursor..<attributeEnd,
      source: original,
      kind: kind
    )
    var seeds = parsedAttributes.diagnosticSeeds
    if hasValidNameBoundary == false {
      seeds.append(FMVarDiagnosticSeed(
        code: .malformedTag,
        range: tagRange,
        message: "Invalid character after <\(kind.rawValue)> tag name"
      ))
    }
    if boundary.hasTerminator == false {
      seeds.append(FMVarDiagnosticSeed(
        code: .malformedTag,
        range: tagRange,
        message: "Opening <\(kind.rawValue)> tag is missing >"
      ))
    }
    if parsedAttributes.isSelfClosing {
      seeds.append(FMVarDiagnosticSeed(
        code: .malformedTag,
        range: tagRange,
        message: "Self-closing syntax is not valid for <\(kind.rawValue)>"
      ))
    }

    return FMVarTagToken(
      direction: direction,
      kind: kind,
      rawText: rawText,
      range: tagRange,
      attributes: parsedAttributes.attributes,
      isSelfClosing: parsedAttributes.isSelfClosing,
      isMalformed: boundary.hasTerminator == false || hasValidNameBoundary == false,
      diagnosticSeeds: seeds
    )
  }

  /// Parses authored attributes while retaining exact source spelling and ranges.
  ///
  /// Malformed attribute fragments become diagnostic seeds and scanning resumes at the next byte.
  /// Duplicate names and declaration-specific meaning are intentionally deferred to semantic
  /// assembly.
  ///
  /// - Parameters:
  ///   - range: Tag-interior byte range after the element name and before the terminator.
  ///   - source: Complete remaining source slice whose indices match the source map.
  ///   - kind: Element kind used in recovery diagnostics.
  /// - Returns: Parsed raw attributes, self-closing syntax state, and recoverable diagnostics.
  /// - Throws: ``FMVarLexicalParserError/sourceLocation(_:)`` if an attribute range cannot be
  ///   represented by the source map.
  private func parseAttributes(
    in range: Range<Int>,
    source: ArraySlice<UInt8>,
    kind: FMVarElementKind
  ) throws(FMVarLexicalParserError) -> (
    attributes: [FMVarRawAttribute],
    isSelfClosing: Bool,
    diagnosticSeeds: [FMVarDiagnosticSeed]
  ) {
    var attributes: [FMVarRawAttribute] = []
    var seeds: [FMVarDiagnosticSeed] = []
    var cursor = range.lowerBound
    var effectiveEnd = range.upperBound
    while effectiveEnd > cursor, ASCII.isWhitespace(source[effectiveEnd - 1]) { effectiveEnd -= 1 }
    var selfClosing = false
    if effectiveEnd > cursor, source[effectiveEnd - 1] == ASCII.slash {
      selfClosing = true
      effectiveEnd -= 1
    }

    while cursor < effectiveEnd {
      while cursor < effectiveEnd, ASCII.isWhitespace(source[cursor]) { cursor += 1 }
      guard cursor < effectiveEnd else { break }
      let attributeStart = cursor
      let nameStart = cursor
      while cursor < effectiveEnd, ASCII.isAttributeNameByte(source[cursor]) { cursor += 1 }
      let nameEnd = cursor
      guard nameStart < nameEnd else {
        let invalidEnd = min(cursor + 1, effectiveEnd)
        let invalidRange = try sourceRange(from: cursor, to: invalidEnd)
        seeds.append(FMVarDiagnosticSeed(
          code: .malformedTag,
          range: invalidRange,
          message: "Invalid character in <\(kind.rawValue)> opening tag"
        ))
        cursor = invalidEnd
        continue
      }

      while cursor < effectiveEnd, ASCII.isWhitespace(source[cursor]) { cursor += 1 }
      var value: String?
      var valueRange: FMVarSourceRange?
      var quoteStyle: FMVarAttributeQuoteStyle?
      if cursor < effectiveEnd, source[cursor] == ASCII.equals {
        cursor += 1
        while cursor < effectiveEnd, ASCII.isWhitespace(source[cursor]) { cursor += 1 }
        if cursor < effectiveEnd,
          source[cursor] == ASCII.doubleQuote || source[cursor] == ASCII.singleQuote
        {
          let quote = source[cursor]
          quoteStyle = quote == ASCII.doubleQuote ? .double : .single
          cursor += 1
          let valueStart = cursor
          while cursor < effectiveEnd, source[cursor] != quote { cursor += 1 }
          let valueEnd = cursor
          value = String(decoding: source[valueStart..<valueEnd], as: UTF8.self)
          valueRange = try sourceRange(from: valueStart, to: valueEnd)
          if cursor < effectiveEnd {
            cursor += 1
          } else {
            seeds.append(FMVarDiagnosticSeed(
              code: .malformedTag,
              range: try sourceRange(from: valueStart - 1, to: valueEnd),
              message: "Attribute has an unterminated quoted value"
            ))
          }
        } else {
          quoteStyle = .unquoted
          let valueStart = cursor
          while cursor < effectiveEnd, ASCII.isWhitespace(source[cursor]) == false { cursor += 1 }
          let valueEnd = cursor
          value = String(decoding: source[valueStart..<valueEnd], as: UTF8.self)
          valueRange = try sourceRange(from: valueStart, to: valueEnd)
        }
      }

      let attributeEnd = cursor
      let attributeRange = try sourceRange(from: attributeStart, to: attributeEnd)
      attributes.append(FMVarRawAttribute(
        rawText: String(decoding: source[attributeStart..<attributeEnd], as: UTF8.self),
        name: String(decoding: source[nameStart..<nameEnd], as: UTF8.self),
        value: value,
        quoteStyle: quoteStyle,
        range: attributeRange,
        nameRange: try sourceRange(from: nameStart, to: nameEnd),
        valueRange: valueRange
      ))
    }

    return (attributes, selfClosing, seeds)
  }

  /// Translates lexical byte offsets while preserving this parser's typed error surface.
  ///
  /// - Parameters:
  ///   - start: Included absolute UTF-8 offset.
  ///   - end: Excluded absolute UTF-8 offset.
  /// - Returns: Snapshot-relative source range for the offsets.
  /// - Throws: ``FMVarLexicalParserError/sourceLocation(_:)`` when the source map rejects either
  ///   offset or their ordering.
  private func sourceRange(
    from start: Int,
    to end: Int
  ) throws(FMVarLexicalParserError) -> FMVarSourceRange {
    do {
      return try sourceMap.range(fromUTF8Offset: start, toUTF8Offset: end)
    } catch {
      throw FMVarLexicalParserError.sourceLocation(error)
    }
  }

  /// Finds the end of a tag without consuming across a conflicting tag or unterminated line.
  ///
  /// - Parameters:
  ///   - start: First byte after the recognized element name.
  ///   - input: Source slice containing the candidate.
  /// - Returns: End offset and whether it follows a closing `>` terminator.
  private func tagBoundary(
    startingAt start: Int,
    input: ArraySlice<UInt8>
  ) -> (end: Int, hasTerminator: Bool) {
    var cursor = start
    var quote: UInt8?
    while cursor < input.endIndex {
      let byte = input[cursor]
      if let activeQuote = quote {
        if byte == activeQuote {
          quote = nil
        } else if byte == ASCII.lineFeed || byte == ASCII.carriageReturn {
          return (cursor, false)
        }
      } else if byte == ASCII.doubleQuote || byte == ASCII.singleQuote {
        quote = byte
      } else if byte == ASCII.greaterThan {
        return (cursor + 1, true)
      } else if byte == ASCII.lessThan {
        return (cursor, false)
      } else if byte == ASCII.lineFeed {
        var lookahead = cursor + 1
        while lookahead < input.endIndex, ASCII.isHorizontalWhitespace(input[lookahead]) {
          lookahead += 1
        }
        if lookahead < input.endIndex, input[lookahead] == ASCII.lessThan {
          return (cursor, false)
        }
      }
      cursor += 1
    }
    return (input.endIndex, false)
  }

  /// Checks the byte following an element name for direction-appropriate tag syntax.
  ///
  /// - Parameters:
  ///   - offset: First byte after the recognized name.
  ///   - direction: Opening or closing tag grammar to apply.
  ///   - input: Candidate source slice.
  /// - Returns: `true` when the name ends at end of input, whitespace, or an allowed delimiter.
  private func isTagBoundary(
    at offset: Int,
    direction: FMVarTagDirection,
    input: ArraySlice<UInt8>
  ) -> Bool {
    guard offset < input.endIndex else { return true }
    let byte = input[offset]
    if direction == .closing {
      return byte == ASCII.greaterThan || ASCII.isWhitespace(byte)
    }
    return byte == ASCII.greaterThan || byte == ASCII.slash || ASCII.isWhitespace(byte)
  }

  /// Removes leading and trailing ASCII whitespace from a byte range without copying bytes.
  ///
  /// - Parameters:
  ///   - range: Candidate half-open range within `input`.
  ///   - input: Source slice whose indices bound `range`.
  /// - Returns: The narrowed range, which may be empty.
  private func trimWhitespace(
    _ range: Range<Int>,
    input: ArraySlice<UInt8>
  ) -> Range<Int> {
    var start = range.lowerBound
    var end = range.upperBound
    while start < end, ASCII.isWhitespace(input[start]) { start += 1 }
    while end > start, ASCII.isWhitespace(input[end - 1]) { end -= 1 }
    return start..<end
  }
}

/// Normalizes lossless raw attributes into element-specific declaration models.
private enum FMVarDeclarationBuilder {
  /// Attribute names accepted by `<fm-var>`.
  private static let variableAttributes: Set<String> = [
    "key", "src", "default", "type", "format", "locale",
  ]
  /// Attribute names accepted by `<fm-list>`.
  private static let listAttributes: Set<String> = [
    "key", "src", "item-type", "format", "locale", "list-style",
  ]
  /// Attribute names accepted by `<fm-format>`.
  private static let formatAttributes: Set<String> = [
    "for", "locale", "format", "list-style", "calendar", "numbering-system",
    "time-zone", "hour-cycle", "hour12", "date-style", "time-style", "weekday",
    "era", "year", "month", "day", "day-period", "hour", "minute", "second",
    "fractional-second-digits", "time-zone-name", "format-matcher",
  ]

  /// Validates and decodes attributes for one lossless element.
  ///
  /// Raw attributes remain available on the element even when normalization fails. This method
  /// accumulates all independent attribute diagnostics it can determine, returning a declaration
  /// only when its element-specific invariants are satisfied.
  ///
  /// - Parameters:
  ///   - element: Lossless parsed element and authored attributes.
  ///   - openingTagRange: Fallback range for missing required attributes.
  /// - Returns: An optional normalized declaration and all semantic diagnostics for the element.
  static func build(
    for element: FMVarElement,
    openingTagRange: FMVarSourceRange
  ) -> (declaration: FMVarDeclaration?, diagnostics: [FMVarDiagnostic]) {
    let allowed: Set<String>
    switch element.kind {
    case .variable: allowed = variableAttributes
    case .list: allowed = listAttributes
    case .format: allowed = formatAttributes
    }

    var diagnostics: [FMVarDiagnostic] = []
    var values: [String: String] = [:]
    var seenNames: Set<String> = []
    var invalid = false
    for attribute in element.attributes {
      guard allowed.contains(attribute.name) else {
        diagnostics.append(diagnostic(
          code: .unknownAttribute,
          element: element,
          range: attribute.nameRange,
          message: "Unknown \(element.kind.rawValue) attribute '\(attribute.name)'"
        ))
        invalid = true
        continue
      }
      if seenNames.contains(attribute.name) {
        diagnostics.append(diagnostic(
          code: .duplicateAttribute,
          element: element,
          range: attribute.nameRange,
          message: "Attribute '\(attribute.name)' must not be repeated"
        ))
        invalid = true
        continue
      }
      seenNames.insert(attribute.name)
      guard let rawValue = attribute.value,
        let quoteStyle = attribute.quoteStyle,
        quoteStyle != .unquoted
      else {
        diagnostics.append(diagnostic(
          code: .invalidAttribute,
          element: element,
          range: attribute.range,
          message: "Attribute '\(attribute.name)' requires a quoted value"
        ))
        invalid = true
        continue
      }
      guard let decoded = XMLEntityDecoder.decode(rawValue) else {
        diagnostics.append(diagnostic(
          code: .invalidAttribute,
          element: element,
          range: attribute.valueRange ?? attribute.range,
          message: "Attribute '\(attribute.name)' contains an invalid XML value"
        ))
        invalid = true
        continue
      }
      values[attribute.name] = decoded
    }

    switch element.kind {
    case .variable:
      guard let key = required(
        "key",
        values: values,
        element: element,
        openingTagRange: openingTagRange,
        diagnostics: &diagnostics
      ) else { return (nil, diagnostics) }
      let type = enumValue(
        FMVarValueType.self,
        name: "type",
        value: values["type"] ?? FMVarValueType.string.rawValue,
        element: element,
        diagnostics: &diagnostics
      )
      if key.isEmpty {
        diagnostics.append(invalidValue("key", element: element))
        invalid = true
      }
      guard invalid == false, let type else { return (nil, diagnostics) }
      return (.scalar(FMVarScalarDeclaration(
        key: key,
        source: values["src"],
        defaultValue: values["default"],
        type: type,
        format: values["format"],
        locale: values["locale"]
      )), diagnostics)

    case .list:
      guard let key = required(
        "key",
        values: values,
        element: element,
        openingTagRange: openingTagRange,
        diagnostics: &diagnostics
      ), let formatString = required(
        "format",
        values: values,
        element: element,
        openingTagRange: openingTagRange,
        diagnostics: &diagnostics
      ) else { return (nil, diagnostics) }
      let itemType = enumValue(
        FMVarValueType.self,
        name: "item-type",
        value: values["item-type"] ?? FMVarValueType.string.rawValue,
        element: element,
        diagnostics: &diagnostics
      )
      let format = enumValue(
        FMVarListFormat.self,
        name: "format",
        value: formatString,
        element: element,
        diagnostics: &diagnostics
      )
      let style = enumValue(
        FMVarListStyle.self,
        name: "list-style",
        value: values["list-style"] ?? FMVarListStyle.long.rawValue,
        element: element,
        diagnostics: &diagnostics
      )
      if key.isEmpty {
        diagnostics.append(invalidValue("key", element: element))
        invalid = true
      }
      guard invalid == false, let itemType, let format, let style else {
        return (nil, diagnostics)
      }
      return (.list(FMVarListDeclaration(
        key: key,
        source: values["src"],
        itemType: itemType,
        format: format,
        locale: values["locale"],
        listStyle: style
      )), diagnostics)

    case .format:
      var targets: [FMVarFormatTarget]?
      if let targetString = values["for"] {
        var parsedTargets: [FMVarFormatTarget] = []
        for token in targetString.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
          guard let target = FMVarFormatTarget(rawValue: token),
            parsedTargets.contains(target) == false
          else {
            diagnostics.append(invalidValue("for", element: element))
            invalid = true
            continue
          }
          parsedTargets.append(target)
        }
        if parsedTargets.isEmpty {
          diagnostics.append(invalidValue("for", element: element))
          invalid = true
        }
        targets = parsedTargets
      }

      let listStyle: FMVarListStyle?
      if let style = values["list-style"] {
        listStyle = enumValue(
          FMVarListStyle.self,
          name: "list-style",
          value: style,
          element: element,
          diagnostics: &diagnostics
        )
        if listStyle == nil { invalid = true }
      } else {
        listStyle = nil
      }
      let hour12: Bool?
      if let rawHour12 = values["hour12"] {
        if rawHour12 == "true" { hour12 = true }
        else if rawHour12 == "false" { hour12 = false }
        else {
          hour12 = nil
          diagnostics.append(invalidValue("hour12", element: element))
          invalid = true
        }
      } else { hour12 = nil }
      let fractionalDigits: Int?
      if let rawDigits = values["fractional-second-digits"] {
        if let digits = Int(rawDigits), (1...3).contains(digits) {
          fractionalDigits = digits
        } else {
          fractionalDigits = nil
          diagnostics.append(invalidValue("fractional-second-digits", element: element))
          invalid = true
        }
      } else { fractionalDigits = nil }

      guard invalid == false else { return (nil, diagnostics) }
      return (.format(FMVarFormatDeclaration(
        targets: targets,
        options: FMVarFormatOptions(
          locale: values["locale"],
          format: values["format"],
          listStyle: listStyle,
          calendar: values["calendar"],
          numberingSystem: values["numbering-system"],
          timeZone: values["time-zone"],
          hourCycle: values["hour-cycle"],
          hour12: hour12,
          dateStyle: values["date-style"],
          timeStyle: values["time-style"],
          weekday: values["weekday"],
          era: values["era"],
          year: values["year"],
          month: values["month"],
          day: values["day"],
          dayPeriod: values["day-period"],
          hour: values["hour"],
          minute: values["minute"],
          second: values["second"],
          fractionalSecondDigits: fractionalDigits,
          timeZoneName: values["time-zone-name"],
          formatMatcher: values["format-matcher"]
        )
      )), diagnostics)
    }
  }

  /// Reads a required decoded attribute and diagnoses its absence at the opening tag.
  ///
  /// - Returns: The decoded value, or `nil` after appending a missing-attribute diagnostic.
  private static func required(
    _ name: String,
    values: [String: String],
    element: FMVarElement,
    openingTagRange: FMVarSourceRange,
    diagnostics: inout [FMVarDiagnostic]
  ) -> String? {
    guard let value = values[name] else {
      diagnostics.append(diagnostic(
        code: .missingAttribute,
        element: element,
        range: openingTagRange,
        message: "<\(element.kind.rawValue)> requires the '\(name)' attribute"
      ))
      return nil
    }
    return value
  }

  /// Converts a decoded string into a string-backed declaration enum.
  ///
  /// - Returns: Parsed enum value, or `nil` after appending an invalid-value diagnostic.
  private static func enumValue<T: RawRepresentable>(
    _ type: T.Type,
    name: String,
    value: String,
    element: FMVarElement,
    diagnostics: inout [FMVarDiagnostic]
  ) -> T? where T.RawValue == String {
    guard let parsed = T(rawValue: value) else {
      diagnostics.append(invalidValue(name, element: element))
      return nil
    }
    return parsed
  }

  /// Creates an invalid-attribute diagnostic at the narrowest authored value range available.
  private static func invalidValue(_ name: String, element: FMVarElement) -> FMVarDiagnostic {
    let range = element.attribute(named: name)?.valueRange
      ?? element.attribute(named: name)?.range
      ?? element.openingTagRange
    return diagnostic(
      code: .invalidAttribute,
      element: element,
      range: range,
      message: "Attribute '\(name)' has an invalid value"
    )
  }

  /// Creates a semantic error diagnostic associated with its source element.
  private static func diagnostic(
    code: FMVarDiagnosticCode,
    element: FMVarElement,
    range: FMVarSourceRange,
    message: String
  ) -> FMVarDiagnostic {
    FMVarDiagnostic(
      code: code,
      severity: .error,
      range: range,
      elementOrdinal: element.ordinal,
      elementKind: element.kind,
      message: message
    )
  }
}

/// Decodes the XML entity subset accepted in fm-var attribute and cache literals.
private enum XMLEntityDecoder {
  /// Decodes named and numeric XML entities while validating all resulting XML 1.0 scalars.
  ///
  /// - Parameter value: Attribute text without surrounding quotes.
  /// - Returns: Decoded text, or `nil` for an invalid entity, scalar, or numeric reference.
  static func decode(_ value: String) -> String? {
    let bytes = Array(value.utf8)
    var decoded = ""
    var cursor = 0
    var literalStart = 0
    while cursor < bytes.count {
      guard bytes[cursor] == ASCII.ampersand else {
        cursor += 1
        continue
      }
      decoded += String(decoding: bytes[literalStart..<cursor], as: UTF8.self)
      guard let end = entityEnd(in: bytes, from: cursor, before: bytes.count),
        let scalar = scalar(for: bytes[(cursor + 1)..<(end - 1)])
      else { return nil }
      decoded.unicodeScalars.append(scalar)
      cursor = end
      literalStart = cursor
    }
    decoded += String(decoding: bytes[literalStart..<bytes.count], as: UTF8.self)
    guard decoded.unicodeScalars.allSatisfy({ isXML10Scalar($0.value) }) else { return nil }
    return decoded
  }

  /// Finds and validates one entity reference beginning with `&`.
  ///
  /// - Parameters:
  ///   - bytes: Source bytes containing the reference.
  ///   - start: Offset of the opening ampersand.
  ///   - end: Exclusive search boundary.
  /// - Returns: Offset after the semicolon, or `nil` for an invalid or overly long reference.
  static func entityEnd(
    in bytes: [UInt8],
    from start: Int,
    before end: Int
  ) -> Int? {
    guard start < end, bytes[start] == ASCII.ampersand else { return nil }
    var cursor = start + 1
    while cursor < end, cursor - start <= 12 {
      if bytes[cursor] == 0x3B {
        return scalar(for: bytes[(start + 1)..<cursor]) == nil ? nil : cursor + 1
      }
      cursor += 1
    }
    return nil
  }

  /// Resolves an entity body without its leading ampersand or trailing semicolon.
  private static func scalar(for entity: ArraySlice<UInt8>) -> Unicode.Scalar? {
    let name = String(decoding: entity, as: UTF8.self)
    switch name {
    case "amp": return "&".unicodeScalars.first
    case "lt": return "<".unicodeScalars.first
    case "gt": return ">".unicodeScalars.first
    case "quot": return "\"".unicodeScalars.first
    case "apos": return "'".unicodeScalars.first
    default:
      let number: UInt32?
      if name.hasPrefix("#x") || name.hasPrefix("#X") {
        number = UInt32(name.dropFirst(2), radix: 16)
      } else if name.hasPrefix("#") {
        number = UInt32(name.dropFirst(), radix: 10)
      } else {
        number = nil
      }
      guard let number, isXML10Scalar(number) else { return nil }
      return Unicode.Scalar(number)
    }
  }

  /// Returns whether a Unicode scalar value is permitted by XML 1.0 character production.
  static func isXML10Scalar(_ value: UInt32) -> Bool {
    value == 0x9 || value == 0xA || value == 0xD
      || (value >= 0x20 && value <= 0xD7FF)
      || (value >= 0xE000 && value <= 0xFFFD)
      || (value >= 0x10000 && value <= 0x10FFFF)
  }
}
