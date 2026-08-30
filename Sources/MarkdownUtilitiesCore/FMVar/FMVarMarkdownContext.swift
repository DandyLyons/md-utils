import Foundation

/// Precomputed byte-level Markdown regions that suppress fm-var element recognition.
///
/// This deliberately models only contexts relevant to custom-element safety: front matter, code,
/// comments, and raw HTML code containers. All indices are absolute offsets into ``bytes``.
struct FMVarMarkdownContext: Sendable {
  /// Complete immutable source snapshot as UTF-8 bytes.
  let bytes: [UInt8]
  /// Byte-for-byte mask whose set entries belong to excluded Markdown regions.
  let excluded: [Bool]
  /// First byte after valid YAML front matter, or `nil` when YAML front matter is absent.
  let yamlFrontMatterEnd: Int?

  /// Builds a context mask for one immutable Markdown source snapshot.
  ///
  /// Exclusion passes share one mask so later passes ignore syntax already classified by an
  /// earlier block-level construct.
  ///
  /// - Parameter source: Complete Markdown text parsed by ``FMVarParser``.
  init(source: String) {
    let bytes = Array(source.utf8)
    self.bytes = bytes
    var excluded = Array(repeating: false, count: bytes.count)

    let frontMatter = Self.markFrontMatter(in: bytes, excluded: &excluded)
    Self.markFencedAndIndentedCode(in: bytes, excluded: &excluded)
    Self.markInlineCode(in: bytes, excluded: &excluded)
    Self.markHTMLComments(in: bytes, excluded: &excluded)
    Self.markHTMLCodeContainers(in: bytes, excluded: &excluded)

    self.excluded = excluded
    self.yamlFrontMatterEnd = frontMatter?.isYAML == true ? frontMatter?.end : nil
  }

  /// Returns whether an in-bounds byte belongs to a context where fm-var syntax is literal.
  ///
  /// Out-of-bounds offsets return `false`, keeping scan boundary probes total.
  func isExcluded(_ offset: Int) -> Bool {
    guard offset >= 0, offset < excluded.count else { return false }
    return excluded[offset]
  }

  /// Returns whether the byte at an offset is preceded by an odd run of backslashes.
  ///
  /// - Parameter offset: Absolute byte offset of the prospective escaped token.
  /// - Returns: `true` when Markdown backslash parity makes the token literal.
  func isEscaped(_ offset: Int) -> Bool {
    guard offset > 0, offset <= bytes.count else { return false }
    var cursor = offset
    var slashCount = 0
    while cursor > 0, bytes[cursor - 1] == ASCII.backslash {
      slashCount += 1
      cursor -= 1
    }
    return slashCount % 2 == 1
  }

  /// Finds the line content bounds containing an offset, excluding the LF byte.
  ///
  /// The offset is clamped through end of file so callers can inspect empty ranges at EOF.
  func lineBounds(containing offset: Int) -> Range<Int> {
    let boundedOffset = min(max(offset, 0), bytes.count)
    var start = boundedOffset
    while start > 0, bytes[start - 1] != ASCII.lineFeed { start -= 1 }
    var end = boundedOffset
    while end < bytes.count, bytes[end] != ASCII.lineFeed { end += 1 }
    return start..<end
  }

  /// Checks whether a forward byte interval contains only ASCII whitespace.
  func isOnlyWhitespace(from start: Int, to end: Int) -> Bool {
    guard start <= end else { return false }
    return bytes[start..<end].allSatisfy(ASCII.isWhitespace)
  }

  /// Checks whether a source range is surrounded only by whitespace on its boundary lines.
  ///
  /// Multi-line content is allowed; only bytes before its start and after its end on the
  /// respective lines determine standalone placement.
  func isStandalone(_ range: Range<Int>) -> Bool {
    let startLine = lineBounds(containing: range.lowerBound)
    let endOffset = range.isEmpty ? range.lowerBound : range.upperBound - 1
    let endLine = lineBounds(containing: endOffset)
    return isOnlyWhitespace(from: startLine.lowerBound, to: range.lowerBound)
      && isOnlyWhitespace(from: range.upperBound, to: endLine.upperBound)
  }

  /// Marks a complete leading YAML or TOML front-matter block as excluded.
  ///
  /// A delimiter is recognized only on the first line and requires a later exact closing line.
  ///
  /// - Returns: The byte after the closing line and whether the delimiter denotes YAML, or `nil`
  ///   when no complete supported front matter exists.
  private static func markFrontMatter(
    in bytes: [UInt8],
    excluded: inout [Bool]
  ) -> (end: Int, isYAML: Bool)? {
    guard let first = lines(in: bytes).first else { return nil }
    let firstLine = lineWithoutCarriageReturn(bytes[first])
    let delimiter: [UInt8]
    let isYAML: Bool
    if firstLine == Array("---".utf8) {
      delimiter = firstLine
      isYAML = true
    } else if firstLine == Array("+++".utf8) {
      delimiter = firstLine
      isYAML = false
    } else {
      return nil
    }

    let sourceLines = lines(in: bytes)
    guard let closing = sourceLines.dropFirst().first(where: {
      lineWithoutCarriageReturn(bytes[$0]) == delimiter
    }) else { return nil }

    let end = closing.upperBound < bytes.count && bytes[closing.upperBound] == ASCII.lineFeed
      ? closing.upperBound + 1
      : closing.upperBound
    mark(0..<end, in: &excluded)
    return (end, isYAML)
  }

  /// Copies line content after removing one CR from a CRLF line ending.
  private static func lineWithoutCarriageReturn(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
    guard bytes.last == ASCII.carriageReturn else { return Array(bytes) }
    return Array(bytes.dropLast())
  }

  /// Marks CommonMark-style fenced and indented code lines as excluded.
  ///
  /// Fence recognition supports backticks, tildes, and block-quote prefixes. A closing fence must
  /// use the same byte with at least the opening run length and only trailing horizontal space.
  private static func markFencedAndIndentedCode(
    in bytes: [UInt8],
    excluded: inout [Bool]
  ) {
    let sourceLines = lines(in: bytes)
    var activeFence: (byte: UInt8, count: Int, start: Int)?

    for line in sourceLines {
      let contentEnd = lineContentEnd(line, in: bytes)
      let prefix = blockPrefix(in: bytes, line: line, contentEnd: contentEnd)

      if let fence = activeFence {
        mark(lineWithEnding(line, in: bytes), in: &excluded)
        if let closing = fenceRun(in: bytes, from: prefix.contentStart, to: contentEnd),
          closing.byte == fence.byte,
          closing.count >= fence.count,
          bytes[closing.end..<contentEnd].allSatisfy(ASCII.isHorizontalWhitespace)
        {
          activeFence = nil
        }
        continue
      }

      if let opening = fenceRun(in: bytes, from: prefix.contentStart, to: contentEnd),
        opening.count >= 3,
        opening.byte != ASCII.backtick
          || bytes[opening.end..<contentEnd].contains(ASCII.backtick) == false
      {
        activeFence = (opening.byte, opening.count, line.lowerBound)
        mark(lineWithEnding(line, in: bytes), in: &excluded)
        continue
      }

      if prefix.indentation >= 4 || prefix.hasTabIndent {
        mark(lineWithEnding(line, in: bytes), in: &excluded)
      }
    }
  }

  /// Marks matched inline code spans using equal-length backtick runs.
  ///
  /// Existing exclusions are skipped so backticks inside block constructs cannot open spans.
  private static func markInlineCode(in bytes: [UInt8], excluded: inout [Bool]) {
    var cursor = 0
    while cursor < bytes.count {
      guard excluded[cursor] == false, bytes[cursor] == ASCII.backtick else {
        cursor += 1
        continue
      }

      let runStart = cursor
      while cursor < bytes.count, bytes[cursor] == ASCII.backtick { cursor += 1 }
      let runLength = cursor - runStart
      var search = cursor
      var closingRange: Range<Int>?
      while search < bytes.count {
        guard excluded[search] == false, bytes[search] == ASCII.backtick else {
          search += 1
          continue
        }
        let candidateStart = search
        while search < bytes.count, bytes[search] == ASCII.backtick { search += 1 }
        if search - candidateStart == runLength {
          closingRange = candidateStart..<search
          break
        }
      }
      if let closingRange {
        mark(runStart..<closingRange.upperBound, in: &excluded)
        cursor = closingRange.upperBound
      }
    }
  }

  /// Marks HTML comments, extending an unterminated comment through end of input.
  private static func markHTMLComments(in bytes: [UInt8], excluded: inout [Bool]) {
    let opening = Array("<!--".utf8)
    let closing = Array("-->".utf8)
    var cursor = 0
    while let start = find(opening, in: bytes, from: cursor) {
      let searchStart = start + opening.count
      let end = find(closing, in: bytes, from: searchStart).map { $0 + closing.count }
        ?? bytes.count
      mark(start..<end, in: &excluded)
      cursor = end
    }
  }

  /// Marks case-insensitive `<code>` and `<pre>` containers as literal HTML regions.
  ///
  /// Escaped openings and incomplete containers are left available to later scanning.
  private static func markHTMLCodeContainers(in bytes: [UInt8], excluded: inout [Bool]) {
    for name in ["code", "pre"] {
      let opening = Array("<\(name)".utf8)
      let closing = Array("</\(name)>".utf8)
      var cursor = 0
      while let start = findCaseInsensitive(opening, in: bytes, from: cursor) {
        guard start == 0 || bytes[start - 1] != ASCII.backslash,
          let openingEnd = bytes[start...].firstIndex(of: ASCII.greaterThan),
          let closingStart = findCaseInsensitive(closing, in: bytes, from: openingEnd + 1)
        else {
          cursor = start + opening.count
          continue
        }
        let end = closingStart + closing.count
        mark(start..<end, in: &excluded)
        cursor = end
      }
    }
  }

  /// Analyzes indentation and block-quote markers before a line's meaningful content.
  ///
  /// - Returns: Fence-scan start, space indentation count, and whether a tab indents the line.
  private static func blockPrefix(
    in bytes: [UInt8],
    line: Range<Int>,
    contentEnd: Int
  ) -> (contentStart: Int, indentation: Int, hasTabIndent: Bool) {
    var cursor = line.lowerBound
    var indentation = 0
    var hasTabIndent = false

    while cursor < contentEnd, bytes[cursor] == ASCII.space, indentation < 4 {
      cursor += 1
      indentation += 1
    }
    if cursor < contentEnd, bytes[cursor] == ASCII.tab {
      hasTabIndent = true
      cursor += 1
    }

    // CommonMark fenced blocks can be nested in block quotes. Consume quote markers only for
    // fence recognition; the prefix still prevents custom elements from being considered top-level.
    var quoteCursor = cursor
    while quoteCursor < contentEnd, bytes[quoteCursor] == ASCII.greaterThan {
      quoteCursor += 1
      if quoteCursor < contentEnd, bytes[quoteCursor] == ASCII.space { quoteCursor += 1 }
    }
    return (quoteCursor, indentation, hasTabIndent)
  }

  /// Measures a backtick or tilde fence run beginning at an exact byte offset.
  ///
  /// - Returns: Fence byte, run length, and first byte after the run, or `nil` for no fence.
  private static func fenceRun(
    in bytes: [UInt8],
    from start: Int,
    to end: Int
  ) -> (byte: UInt8, count: Int, end: Int)? {
    guard start < end, bytes[start] == ASCII.backtick || bytes[start] == ASCII.tilde else {
      return nil
    }
    let byte = bytes[start]
    var cursor = start
    while cursor < end, bytes[cursor] == byte { cursor += 1 }
    return (byte, cursor - start, cursor)
  }

  /// Splits UTF-8 bytes into line-content ranges excluding LF separators.
  ///
  /// The result always contains a final range, including for empty input and trailing LF.
  private static func lines(in bytes: [UInt8]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    var start = 0
    for (offset, byte) in bytes.enumerated() where byte == ASCII.lineFeed {
      result.append(start..<offset)
      start = offset + 1
    }
    result.append(start..<bytes.count)
    return result
  }

  /// Returns a line's content end after excluding a CR from a CRLF ending.
  private static func lineContentEnd(_ line: Range<Int>, in bytes: [UInt8]) -> Int {
    if line.upperBound > line.lowerBound, bytes[line.upperBound - 1] == ASCII.carriageReturn {
      return line.upperBound - 1
    }
    return line.upperBound
  }

  /// Extends a line-content range through its following LF when present.
  private static func lineWithEnding(_ line: Range<Int>, in bytes: [UInt8]) -> Range<Int> {
    if line.upperBound < bytes.count, bytes[line.upperBound] == ASCII.lineFeed {
      return line.lowerBound..<(line.upperBound + 1)
    }
    return line
  }

  /// Finds the first exact byte sequence at or after an absolute start offset.
  private static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
    guard needle.isEmpty == false, start <= bytes.count - needle.count else { return nil }
    for offset in start...(bytes.count - needle.count)
    where bytes[offset..<(offset + needle.count)].elementsEqual(needle) {
      return offset
    }
    return nil
  }

  /// Finds an ASCII case-insensitive byte sequence at or after a start offset.
  private static func findCaseInsensitive(
    _ needle: [UInt8],
    in bytes: [UInt8],
    from start: Int
  ) -> Int? {
    guard needle.isEmpty == false, start <= bytes.count - needle.count else { return nil }
    for offset in start...(bytes.count - needle.count) {
      let matches = needle.indices.allSatisfy {
        ASCII.lowercased(bytes[offset + $0]) == ASCII.lowercased(needle[$0])
      }
      if matches { return offset }
    }
    return nil
  }

  /// Sets all in-bounds mask entries intersecting a half-open range.
  private static func mark(_ range: Range<Int>, in excluded: inout [Bool]) {
    guard range.isEmpty == false else { return }
    for offset in range where offset >= 0 && offset < excluded.count {
      excluded[offset] = true
    }
  }
}

/// ASCII constants and byte predicates shared by the fm-var lexer and Markdown context scanner.
enum ASCII {
  static let tab: UInt8 = 0x09
  static let lineFeed: UInt8 = 0x0A
  static let carriageReturn: UInt8 = 0x0D
  static let space: UInt8 = 0x20
  static let doubleQuote: UInt8 = 0x22
  static let ampersand: UInt8 = 0x26
  static let singleQuote: UInt8 = 0x27
  static let slash: UInt8 = 0x2F
  static let zero: UInt8 = 0x30
  static let nine: UInt8 = 0x39
  static let colon: UInt8 = 0x3A
  static let lessThan: UInt8 = 0x3C
  static let equals: UInt8 = 0x3D
  static let greaterThan: UInt8 = 0x3E
  static let uppercaseA: UInt8 = 0x41
  static let uppercaseZ: UInt8 = 0x5A
  static let backslash: UInt8 = 0x5C
  static let underscore: UInt8 = 0x5F
  static let backtick: UInt8 = 0x60
  static let lowercaseA: UInt8 = 0x61
  static let lowercaseZ: UInt8 = 0x7A
  static let tilde: UInt8 = 0x7E
  static let hyphen: UInt8 = 0x2D

  /// Returns whether a byte is horizontal whitespace, LF, or CR.
  static func isWhitespace(_ byte: UInt8) -> Bool {
    isHorizontalWhitespace(byte) || byte == lineFeed || byte == carriageReturn
  }

  /// Returns whether a byte is an ASCII space or tab.
  static func isHorizontalWhitespace(_ byte: UInt8) -> Bool {
    byte == space || byte == tab
  }

  /// Returns whether a byte is allowed in a recoverable fm-var attribute name.
  static func isAttributeNameByte(_ byte: UInt8) -> Bool {
    (byte >= lowercaseA && byte <= lowercaseZ)
      || (byte >= uppercaseA && byte <= uppercaseZ)
      || (byte >= zero && byte <= nine)
      || byte == hyphen || byte == underscore || byte == colon
  }

  /// Lowercases one ASCII uppercase letter and leaves every other byte unchanged.
  static func lowercased(_ byte: UInt8) -> UInt8 {
    guard byte >= uppercaseA, byte <= uppercaseZ else { return byte }
    return byte + (lowercaseA - uppercaseA)
  }
}
