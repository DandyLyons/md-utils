import Foundation
import Parsing

/// YAML or TOML frontmatter represented by one leading hash comment per physical line.
public struct LineCommentFrontMatter: Equatable, Sendable {
  /// The logical metadata after removing the hash-comment prefixes.
  public let rawFrontMatter: String

  /// The serialization format selected by the delimiter lines.
  public let format: FrontMatterFormat

  /// The source range spanning the opening through closing delimiter content.
  ///
  /// The range is valid only for the exact source snapshot supplied to the parser.
  public let range: Range<String.Index>

  /// The 1-based physical line containing the opening delimiter.
  public let openingLine: Int

  /// The LF line ending used by the opening delimiter.
  public let lineEnding: String
}

/// A deterministic structural failure in a recognized line-comment candidate.
public enum LineCommentFrontMatterDiagnostic: Error, Equatable, LocalizedError, Sendable {
  /// The closing delimiter selects a different format from the opener.
  case mismatchedDelimiter(
    opening: FrontMatterFormat,
    closing: FrontMatterFormat,
    closingLine: Int
  )

  /// A nonempty candidate line is neither bare `#` nor prefixed by exactly `# `.
  case invalidCommentPrefix(line: Int)

  public var errorDescription: String? {
    switch self {
    case .mismatchedDelimiter(let opening, let closing, let closingLine):
      return "line-comment frontmatter opens as \(opening.rawValue.uppercased()) but closes as \(closing.rawValue.uppercased()) at line \(closingLine)"
    case .invalidCommentPrefix(let line):
      return "line-comment frontmatter line \(line) must be empty, bare #, or begin with exactly # "
    }
  }
}

/// The result of inspecting the legal top-of-file positions for line-comment frontmatter.
public struct LineCommentFrontMatterScan: Equatable, Sendable {
  /// A structurally valid frontmatter block, when present.
  public let frontMatter: LineCommentFrontMatter?

  /// The recognized candidate range, including structurally malformed candidates.
  public let recognizedRange: Range<String.Index>?

  /// A structural diagnostic for a recognized malformed candidate.
  public let diagnostic: LineCommentFrontMatterDiagnostic?

  package let placement: LineCommentFrontMatterPlacement
}

/// Creation placement derived from the same prologue rules used by the parser.
package struct LineCommentFrontMatterPlacement: Equatable, Sendable {
  package let insertionIndex: String.Index
  package let lineEnding: String
  package let needsLeadingLineEnding: Bool
  package let reusesFollowingEmptyLine: Bool
}

/// Finds fixed-`# ` YAML or TOML frontmatter in the legal file prologue.
public struct LineCommentFrontMatterParser: Parsing.Parser, Sendable {
  public typealias Input = Substring
  public typealias Output = LineCommentFrontMatterScan

  /// Creates a line-comment frontmatter parser.
  public init() {}

  /// Parses and consumes one source snapshot without constructing an array of all physical lines.
  ///
  /// A lone legal opener is absent frontmatter. Structural diagnostics are returned
  /// only after the contiguous leading comment region contains a second exact YAML
  /// or TOML delimiter.
  public func parse(_ input: inout Substring) -> LineCommentFrontMatterScan {
    let source = input
    input = input[input.endIndex...]
    let prologue = legalPrologue(in: source)
    let placement = prologue.placement
    guard let opener = prologue.opener,
      let openingFormat = Self.format(forPhysicalLine: opener.line.text)
    else {
      return LineCommentFrontMatterScan(
        frontMatter: nil,
        recognizedRange: nil,
        diagnostic: nil,
        placement: placement
      )
    }

    guard let candidate = preflightCandidate(
      in: source,
      after: opener.line.fullEnd,
      openingLine: opener.lineNumber
    ) else {
      return LineCommentFrontMatterScan(
        frontMatter: nil,
        recognizedRange: nil,
        diagnostic: nil,
        placement: placement
      )
    }

    let recognizedRange = opener.contentStart..<candidate.endIndex
    guard openingFormat == candidate.closingFormat else {
      return LineCommentFrontMatterScan(
        frontMatter: nil,
        recognizedRange: recognizedRange,
        diagnostic: .mismatchedDelimiter(
          opening: openingFormat,
          closing: candidate.closingFormat,
          closingLine: candidate.closingLine
        ),
        placement: placement
      )
    }

    let parsedPayload = parseCompleteCandidate(
      String(source[recognizedRange]),
      format: openingFormat
    )
    guard case .success(let rawFrontMatter) = parsedPayload else {
      let invalidOffset: Int
      if case .invalidCommentPrefix(let offset) = parsedPayload {
        invalidOffset = offset
      } else {
        invalidOffset = 1
      }
      return LineCommentFrontMatterScan(
        frontMatter: nil,
        recognizedRange: recognizedRange,
        diagnostic: .invalidCommentPrefix(line: opener.lineNumber + invalidOffset),
        placement: placement
      )
    }

    let frontMatter = LineCommentFrontMatter(
      rawFrontMatter: rawFrontMatter,
      format: openingFormat,
      range: recognizedRange,
      openingLine: opener.lineNumber,
      lineEnding: opener.line.lineEnding.isEmpty ? placement.lineEnding : opener.line.lineEnding
    )
    return LineCommentFrontMatterScan(
      frontMatter: frontMatter,
      recognizedRange: recognizedRange,
      diagnostic: nil,
      placement: placement
    )
  }

  /// Convenience entry point for parsing a complete Swift string.
  ///
  /// Returned ranges and creation placement remain valid for `source` because
  /// parsing operates on its original substring storage rather than a copied string.
  public func parse(_ source: String) -> LineCommentFrontMatterScan {
    var input = source[...]
    return parse(&input)
  }

  private func legalPrologue(in source: Substring) -> LegalPrologue {
    let sourceStart = source.startIndex
    let contentStart = source.first == "\u{FEFF}"
      ? source.index(after: sourceStart)
      : sourceStart
    let preferredLineEnding = "\n"

    guard source[contentStart...].hasPrefix("#!") else {
      return LegalPrologue(
        opener: delimiterPhysicalLine(in: source, startingAt: contentStart).map {
          Opener(line: $0, contentStart: contentStart, lineNumber: 1)
        },
        placement: LineCommentFrontMatterPlacement(
          insertionIndex: contentStart,
          lineEnding: preferredLineEnding,
          needsLeadingLineEnding: false,
          reusesFollowingEmptyLine: false
        )
      )
    }

    let firstLine = physicalLine(in: source, startingAt: contentStart)
      ?? PhysicalLine(
        start: contentStart,
        contentEnd: source.endIndex,
        fullEnd: source.endIndex,
        text: String(source[contentStart...]),
        lineEnding: ""
      )
    let immediateOpener = delimiterPhysicalLine(
      in: source,
      startingAt: firstLine.fullEnd
    ).map { line in
      Opener(line: line, contentStart: line.start, lineNumber: 2)
    }
    let gapOpener: Opener?
    if firstLine.fullEnd < source.endIndex,
      source[firstLine.fullEnd] == "\n"
    {
      let thirdLineStart = source.index(after: firstLine.fullEnd)
      gapOpener = delimiterPhysicalLine(in: source, startingAt: thirdLineStart).map { line in
        Opener(line: line, contentStart: line.start, lineNumber: 3)
      }
    } else {
      gapOpener = nil
    }

    return LegalPrologue(
      opener: immediateOpener ?? gapOpener,
      placement: LineCommentFrontMatterPlacement(
        insertionIndex: firstLine.fullEnd,
        lineEnding: preferredLineEnding,
        needsLeadingLineEnding: firstLine.lineEnding.isEmpty,
        reusesFollowingEmptyLine: firstLine.fullEnd < source.endIndex
          && source[firstLine.fullEnd] == "\n"
      )
    )
  }

  private func delimiterPhysicalLine(
    in source: Substring,
    startingAt start: String.Index
  ) -> PhysicalLine? {
    var input = source[start...]
    guard (try? anyDelimiterParser.parse(&input)) != nil else { return nil }
    let contentEnd = input.startIndex
    let hasLineEnding = contentEnd < source.endIndex && source[contentEnd] == "\n"
    return PhysicalLine(
      start: start,
      contentEnd: contentEnd,
      fullEnd: hasLineEnding ? source.index(after: contentEnd) : contentEnd,
      text: String(source[start..<contentEnd]),
      lineEnding: hasLineEnding ? "\n" : ""
    )
  }

  private static func format(forPhysicalLine line: String) -> FrontMatterFormat? {
    switch line {
    case "# ---": .yaml
    case "# +++": .toml
    default: nil
    }
  }

  /// Proves that the contiguous leading hash-comment region has a second exact
  /// delimiter. `Many` stops as soon as its comment-line element cannot parse,
  /// and its `Peek` terminator distinguishes a delimiter from an ordinary host
  /// line without consuming the delimiter twice.
  private func preflightCandidate(
    in source: Substring,
    after openingLineEnd: String.Index,
    openingLine: Int
  ) -> PreflightCandidate? {
    var input = source[openingLineEnd...]
    let parser = Parse {
      Many(into: 0) { lineCount, _ in
        lineCount += 1
      } element: {
        Parse {
          Not { anyDelimiterParser }
          OneOf {
            Parse {
              "#"
              Prefix<Substring> { $0 != "\n" }
              physicalLineEndingParser
            }
            .map { _ in () }
            physicalLineEndingParser
          }
        }
      } terminator: {
        Peek { anyDelimiterParser }
      }
      anyDelimiterParser
    }

    guard let (payloadLineCount, closingFormat) = try? parser.parse(&input) else {
      return nil
    }
    return PreflightCandidate(
      closingFormat: closingFormat,
      closingLine: openingLine + payloadLineCount + 1,
      endIndex: input.startIndex
    )
  }

  /// Constructs and validates a recognized candidate with swift-parsing.
  ///
  /// Candidate recognition remains a streaming source-index scan so large
  /// noncandidates exit without allocating a physical-line array. Only the
  /// recognized prologue slice reaches this result-builder parser.
  private func parseCompleteCandidate(
    _ candidate: String,
    format: FrontMatterFormat
  ) -> CandidatePayload {
    let delimiter = "# \(format.delimiter)"
    var input = Substring(candidate)
    let envelope = Parse {
      delimiter
      "\n"
      Many {
        Parse {
          Not { exactDelimiter(delimiter) }
          commentLineParser
          "\n"
        }
      } terminator: {
        exactDelimiter(delimiter)
        End()
      }
    }
    if let logicalLines = try? envelope.parse(&input) {
      return .success(logicalLines.joined(separator: "\n"))
    }

    var fallbackInput = Substring(candidate)
    let fallbackEnvelope = Parse {
      delimiter
      "\n"
      PrefixUpTo("\n\(delimiter)").map(String.init)
      "\n"
      delimiter
      End()
    }
    guard let physicalPayload = try? fallbackEnvelope.parse(&fallbackInput) else {
      return .invalidEnvelope
    }
    let physicalLines = physicalPayload.split(
      separator: "\n",
      omittingEmptySubsequences: false
    ).map(String.init)
    var logicalLines: [String] = []
    logicalLines.reserveCapacity(physicalLines.count)
    for (offset, line) in physicalLines.enumerated() {
      guard let logicalLine = parseCommentLine(line) else {
        return .invalidCommentPrefix(offset: offset + 1)
      }
      logicalLines.append(logicalLine)
    }
    return .success(logicalLines.joined(separator: "\n"))
  }

  private var physicalLineEndingParser: some Parser<Substring, Void> {
    "\n"
  }

  private var delimiterBoundaryParser: some Parser<Substring, Void> {
    Peek {
      OneOf {
        "\n"
        End()
      }
    }
  }

  private var anyDelimiterParser: some Parser<Substring, FrontMatterFormat> {
    OneOf {
      Parse {
        "# ---"
        delimiterBoundaryParser
      }
      .map { FrontMatterFormat.yaml }
      Parse {
        "# +++"
        delimiterBoundaryParser
      }
      .map { FrontMatterFormat.toml }
    }
  }

  private func exactDelimiter(
    _ delimiter: String
  ) -> some Parser<Substring, Void> {
    Parse {
      delimiter
      Peek {
        OneOf {
          "\n"
          End()
        }
      }
    }
  }

  private var commentLineParser: some Parser<Substring, String> {
    OneOf {
      Parse {
        "# "
        Prefix<Substring> { $0 != "\n" }
      }
      .map(String.init)
      Parse {
        "#"
        Peek { "\n" }
      }
      .map { "" }
      Peek { "\n" }
        .map { "" }
    }
  }

  private func parseCommentLine(_ line: String) -> String? {
    if line.isEmpty || line == "#" || line == "# " { return "" }
    var input = Substring(line)
    let parser = Parse {
      "# "
      Rest<Substring>().map(String.init)
      End()
    }
    return try? parser.parse(&input)
  }

  private func physicalLine(
    in source: Substring,
    startingAt start: String.Index
  ) -> PhysicalLine? {
    guard start < source.endIndex else { return nil }
    var cursor = start
    while cursor < source.endIndex, source[cursor] != "\n" {
      cursor = source.index(after: cursor)
    }
    let contentEnd = cursor
    let lineEnding: String
    let fullEnd: String.Index
    if cursor == source.endIndex {
      lineEnding = ""
      fullEnd = cursor
    } else {
      lineEnding = "\n"
      fullEnd = source.index(after: cursor)
    }
    return PhysicalLine(
      start: start,
      contentEnd: contentEnd,
      fullEnd: fullEnd,
      text: String(source[start..<contentEnd]),
      lineEnding: lineEnding
    )
  }

  private struct PhysicalLine {
    let start: String.Index
    let contentEnd: String.Index
    let fullEnd: String.Index
    let text: String
    let lineEnding: String
  }

  private struct Opener {
    let line: PhysicalLine
    let contentStart: String.Index
    let lineNumber: Int
  }

  private struct LegalPrologue {
    let opener: Opener?
    let placement: LineCommentFrontMatterPlacement
  }

  private struct PreflightCandidate {
    let closingFormat: FrontMatterFormat
    let closingLine: Int
    let endIndex: String.Index
  }

  private enum CandidatePayload {
    case success(String)
    case invalidCommentPrefix(offset: Int)
    case invalidEnvelope
  }
}
