import Foundation
import Parsing

/// Delimiters that wrap one YAML frontmatter block in a non-Markdown text file.
///
/// The inner YAML delimiters are always `---` and are intentionally not configurable.
public struct WrappedFrontMatterSyntax: Equatable, Sendable {
  public let openingCommentDelimiter: String
  public let closingCommentDelimiter: String

  public init(
    openingCommentDelimiter: String,
    closingCommentDelimiter: String
  ) throws {
    guard openingCommentDelimiter.isEmpty == false else {
      throw WrappedFrontMatterSyntaxError.emptyOpeningDelimiter
    }
    guard closingCommentDelimiter.isEmpty == false else {
      throw WrappedFrontMatterSyntaxError.emptyClosingDelimiter
    }
    guard openingCommentDelimiter.contains(where: \.isNewline) == false else {
      throw WrappedFrontMatterSyntaxError.multilineOpeningDelimiter
    }
    guard closingCommentDelimiter.contains(where: \.isNewline) == false else {
      throw WrappedFrontMatterSyntaxError.multilineClosingDelimiter
    }
    self.openingCommentDelimiter = openingCommentDelimiter
    self.closingCommentDelimiter = closingCommentDelimiter
  }

  private init(uncheckedOpening: String, uncheckedClosing: String) {
    self.openingCommentDelimiter = uncheckedOpening
    self.closingCommentDelimiter = uncheckedClosing
  }

  public static let cBlock = Self(
    uncheckedOpening: "/*",
    uncheckedClosing: "*/"
  )

  public static let htmlComment = Self(
    uncheckedOpening: "<!--",
    uncheckedClosing: "-->"
  )

  public static let pythonDocstring = Self(
    uncheckedOpening: "\"\"\"",
    uncheckedClosing: "\"\"\""
  )

  public static let powershellBlock = Self(
    uncheckedOpening: "<#",
    uncheckedClosing: "#>"
  )

  public static let luaBlock = Self(
    uncheckedOpening: "--[[",
    uncheckedClosing: "]]"
  )
}

/// Invalid host-language delimiters for wrapped frontmatter.
public enum WrappedFrontMatterSyntaxError: Error, Equatable, LocalizedError {
  case emptyOpeningDelimiter
  case emptyClosingDelimiter
  case multilineOpeningDelimiter
  case multilineClosingDelimiter

  public var errorDescription: String? {
    switch self {
    case .emptyOpeningDelimiter:
      return "The opening frontmatter comment delimiter cannot be empty"
    case .emptyClosingDelimiter:
      return "The closing frontmatter comment delimiter cannot be empty"
    case .multilineOpeningDelimiter:
      return "The opening frontmatter comment delimiter must fit on one line"
    case .multilineClosingDelimiter:
      return "The closing frontmatter comment delimiter must fit on one line"
    }
  }
}

/// Built-in host-language wrappers used by extension inference.
public enum WrappedFrontMatterPreset: String, CaseIterable, Sendable {
  case cBlock = "c-block"
  case htmlComment = "html-comment"
  case pythonDocstring = "python-docstring"
  case powershellBlock = "powershell-block"
  case luaBlock = "lua-block"

  public var syntax: WrappedFrontMatterSyntax {
    switch self {
    case .cBlock: return .cBlock
    case .htmlComment: return .htmlComment
    case .pythonDocstring: return .pythonDocstring
    case .powershellBlock: return .powershellBlock
    case .luaBlock: return .luaBlock
    }
  }

  public var extensions: Set<String> {
    switch self {
    case .cBlock:
      return [
        "c", "h", "cc", "cpp", "cxx", "hpp", "hxx", "m", "mm", "swift",
        "java", "kt", "kts", "scala", "js", "mjs", "cjs", "jsx", "ts", "mts",
        "cts", "tsx", "cs", "go", "rs", "dart", "php", "css", "scss", "less", "sql",
      ]
    case .htmlComment:
      return ["html", "htm", "xhtml", "xml", "svg", "vue", "svelte"]
    case .pythonDocstring:
      return ["py", "pyi"]
    case .powershellBlock:
      return ["ps1", "psm1", "psd1"]
    case .luaBlock:
      return ["lua"]
    }
  }

  public static func inferred(forExtension pathExtension: String) -> Self? {
    let normalized = pathExtension
      .lowercased()
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return allCases.first { $0.extensions.contains(normalized) }
  }
}

/// A source location belonging to the exact source snapshot that was scanned.
public struct WrappedFrontMatterLocation: Equatable, Sendable {
  /// Zero-based UTF-8 offsets containing the complete wrapped block.
  public let utf8Range: Range<Int>
  /// One-based line containing the opening comment delimiter.
  public let openingLine: Int
  /// One-based line containing the closing comment delimiter.
  public let closingLine: Int
}

/// The result of scanning one source snapshot for wrapped frontmatter.
public struct WrappedFrontMatterScanResult: Equatable, Sendable {
  /// Normalized YAML from the first complete wrapped block, or `nil` when none was found.
  public let rawFrontMatter: String?
  /// Location of the first complete wrapped block.
  public let firstBlock: WrappedFrontMatterLocation?
  /// Locations of later complete blocks. Their YAML payloads are intentionally not exposed.
  public let additionalBlocks: [WrappedFrontMatterLocation]

  public var hasMultipleBlocks: Bool {
    additionalBlocks.isEmpty == false
  }
}

/// Parses one complete comment-wrapped `---` YAML `---` envelope.
///
/// This parser must be invoked at the beginning of a physical line. It extracts text only;
/// `YAMLConversion` remains responsible for validating YAML and requiring a mapping root.
public struct WrappedFrontMatterParser: Parsing.Parser {
  public typealias Input = Substring
  public typealias Output = String

  public let syntax: WrappedFrontMatterSyntax

  public init(syntax: WrappedFrontMatterSyntax) {
    self.syntax = syntax
  }

  public var body: some Parsing.Parser<Substring, String> {
    Parse {
      syntax.openingCommentDelimiter
      "\n"
      "---"
      "\n"
      Many(into: [String](), { lines, line in
        lines.append(line)
      }) {
        Parse {
          Not {
            WrappedFrontMatterClosingBoundaryParser(syntax: syntax)
          }
          Prefix { character in
            character.isNewline == false
          }
          .map(String.init)
          "\n"
        }
      } terminator: {
        WrappedFrontMatterClosingBoundaryParser(syntax: syntax)
      }
    }
    .map { lines in
      lines.joined(separator: "\n")
    }
  }
}

/// Finds every complete wrapped block while exposing YAML only from the first one.
public struct WrappedFrontMatterScanner {
  public let syntax: WrappedFrontMatterSyntax

  public init(syntax: WrappedFrontMatterSyntax) {
    self.syntax = syntax
  }

  public func scan(_ source: String) -> WrappedFrontMatterScanResult {
    var rawFrontMatter: String?
    var firstBlock: WrappedFrontMatterLocation?
    var additionalBlocks: [WrappedFrontMatterLocation] = []
    var lineStart = source.startIndex
    var lineNumber = 1

    while lineStart < source.endIndex {
      let candidate = source[lineStart...]
      if candidate.starts(with: syntax.openingCommentDelimiter) {
        var input = candidate
        if let rawYAML = try? WrappedFrontMatterParser(syntax: syntax).parse(&input) {
          let blockEnd = input.startIndex
          let location = location(
            in: source,
            from: lineStart,
            to: blockEnd,
            openingLine: lineNumber
          )

          if firstBlock == nil {
            rawFrontMatter = rawYAML
            firstBlock = location
          } else {
            additionalBlocks.append(location)
          }

          guard let next = nextLineStart(in: source, after: blockEnd) else {
            break
          }
          lineNumber = location.closingLine + 1
          lineStart = next
          continue
        }
      }

      guard let next = nextLineStart(in: source, after: lineStart) else {
        break
      }
      lineNumber += 1
      lineStart = next
    }

    return WrappedFrontMatterScanResult(
      rawFrontMatter: rawFrontMatter,
      firstBlock: firstBlock,
      additionalBlocks: additionalBlocks
    )
  }

  private func location(
    in source: String,
    from start: String.Index,
    to end: String.Index,
    openingLine: Int
  ) -> WrappedFrontMatterLocation {
    let newlineCount = source[start..<end].reduce(into: 0) { count, character in
      if character == "\n" {
        count += 1
      }
    }
    let lowerOffset = source.utf8.distance(from: source.startIndex, to: start)
    let upperOffset = source.utf8.distance(from: source.startIndex, to: end)
    return WrappedFrontMatterLocation(
      utf8Range: lowerOffset..<upperOffset,
      openingLine: openingLine,
      closingLine: openingLine + newlineCount
    )
  }

  private func nextLineStart(in source: String, after index: String.Index) -> String.Index? {
    guard index < source.endIndex,
      let newline = source[index...].firstIndex(of: "\n")
    else {
      return nil
    }
    return source.index(after: newline)
  }
}

/// Parses the complete inner YAML and outer comment closing boundary.
private struct WrappedFrontMatterClosingBoundaryParser: Parsing.Parser {
  let syntax: WrappedFrontMatterSyntax

  var body: some Parsing.Parser<Substring, Void> {
    Parse {
      "---"
      "\n"
      syntax.closingCommentDelimiter
      Peek {
        OneOf {
          End()
          "\n"
        }
      }
    }
  }
}
