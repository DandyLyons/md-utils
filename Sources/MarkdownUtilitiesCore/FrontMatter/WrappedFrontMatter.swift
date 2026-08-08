import Foundation
import Parsing

/// A host-language envelope used to contain YAML frontmatter in a text file.
public struct FrontMatterSyntax: Equatable, Sendable {
  /// The stable name used in diagnostics and prompts.
  public let name: String

  /// The complete physical line that opens the host envelope.
  public let openingWrapper: String

  /// The complete physical line that closes the host envelope.
  public let closingWrapper: String

  /// Creates a frontmatter syntax.
  ///
  /// - Parameters:
  ///   - name: The stable syntax name used in diagnostics and prompts.
  ///   - openingWrapper: The exact opening physical line.
  ///   - closingWrapper: The exact closing physical line.
  public init(name: String, openingWrapper: String, closingWrapper: String) {
    self.name = name
    self.openingWrapper = openingWrapper
    self.closingWrapper = closingWrapper
  }

  /// C-family block comments.
  public static let cBlock = FrontMatterSyntax(
    name: "c-block",
    openingWrapper: "/*",
    closingWrapper: "*/"
  )

  /// HTML/XML comments.
  public static let htmlComment = FrontMatterSyntax(
    name: "html-comment",
    openingWrapper: "<!--",
    closingWrapper: "-->"
  )

  /// Python triple-quoted strings.
  public static let pythonDocstring = FrontMatterSyntax(
    name: "python-docstring",
    openingWrapper: "\"\"\"",
    closingWrapper: "\"\"\""
  )

  /// PowerShell block comments.
  public static let powershellBlock = FrontMatterSyntax(
    name: "powershell-block",
    openingWrapper: "<#",
    closingWrapper: "#>"
  )

  /// Lua block comments.
  public static let luaBlock = FrontMatterSyntax(
    name: "lua-block",
    openingWrapper: "--[[",
    closingWrapper: "]]"
  )

  /// Returns the shipped syntax for a file extension, compared case-insensitively.
  ///
  /// - Parameter fileExtension: An extension with or without a leading period.
  /// - Returns: The shipped wrapper syntax, or `nil` when no mapping exists.
  public static func shippedSyntax(forExtension fileExtension: String) -> FrontMatterSyntax? {
    let normalized = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    if cBlockExtensions.contains(normalized) { return .cBlock }
    if htmlCommentExtensions.contains(normalized) { return .htmlComment }
    if pythonDocstringExtensions.contains(normalized) { return .pythonDocstring }
    if powershellBlockExtensions.contains(normalized) { return .powershellBlock }
    if luaBlockExtensions.contains(normalized) { return .luaBlock }
    return nil
  }

  /// All non-Markdown extensions with shipped wrapper mappings.
  public static let shippedExtensions: Set<String> =
    cBlockExtensions
    .union(htmlCommentExtensions)
    .union(pythonDocstringExtensions)
    .union(powershellBlockExtensions)
    .union(luaBlockExtensions)
  /// File extensions for languages that use C-style block comments (`/* ... */`).
  private static let cBlockExtensions: Set<String> = [
    "c", "h", "cc", "cpp", "cxx", "hpp", "hxx", "m", "mm", "swift", "java",
    "kt", "kts", "scala", "js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx",
    "cs", "go", "rs", "dart", "php", "css", "scss", "less", "sql", "jsonc",
  ]

  /// File extensions for languages that use HTML-style comments (`<!-- ... -->`).
  private static let htmlCommentExtensions: Set<String> = [
    "html", "htm", "xhtml", "xml", "svg", "vue", "svelte",
  ]
  /// File extensions for languages that use Python-style triple-quoted strings (`""" ... """`).
  private static let pythonDocstringExtensions: Set<String> = ["py", "pyi"]
  /// File extensions for languages that use PowerShell-style block comments (`<# ... #>`).
  private static let powershellBlockExtensions: Set<String> = ["ps1", "psm1", "psd1"]
  /// File extensions for languages that use Lua-style block comments (`--[[ ... ]]`).
  private static let luaBlockExtensions: Set<String> = ["lua"]
}

/// A complete wrapped frontmatter block located in one exact source snapshot.
public struct WrappedFrontMatterBlock: Equatable, Sendable {
  /// The raw YAML between the two `---` marker lines.
  public let rawYAML: String

  /// The source range spanning both host wrapper lines.
  public let range: Range<String.Index>

  /// The 1-based line containing the opening wrapper.
  public let openingLine: Int
}

/// The result of scanning one source snapshot for wrapped frontmatter.
public struct WrappedFrontMatterScan: Equatable, Sendable {
  /// The first complete block, if one exists.
  public let firstBlock: WrappedFrontMatterBlock?

  /// Opening locations for complete blocks after the first.
  public let additionalOpeningLines: [Int]
}

/// Finds complete delimiter-wrapped YAML frontmatter blocks in LF text.
public struct WrappedFrontMatterParser: Sendable {
  /// The host syntax recognized by this parser.
  public let syntax: FrontMatterSyntax

  /// Creates a parser configured for one host syntax.
  public init(syntax: FrontMatterSyntax) {
    self.syntax = syntax
  }

  /// Scans the whole snapshot, returning the first block and later opening lines.
  ///
  /// The parser recognizes LF input and requires wrapper delimiters and both YAML
  /// markers to occupy complete physical lines. Incomplete candidates are treated
  /// as absent. Returned ranges are valid only for the supplied snapshot.
  ///
  /// - Parameter source: Complete LF text to scan.
  /// - Returns: The first complete block and locations of later complete blocks.
  public func parse(_ source: String) -> WrappedFrontMatterScan {
    let lines = physicalLines(in: source)
    var blocks: [WrappedFrontMatterBlock] = []
    var openingIndex = 0

    while openingIndex < lines.count {
      guard lines[openingIndex].text == syntax.openingWrapper,
        openingIndex + 1 < lines.count,
        lines[openingIndex + 1].text == "---"
      else {
        openingIndex += 1
        continue
      }

      var yamlClosingIndex = openingIndex + 2
      var matchedBlock: WrappedFrontMatterBlock?
      while yamlClosingIndex + 1 < lines.count {
        if lines[yamlClosingIndex].text == "---",
          lines[yamlClosingIndex + 1].text == syntax.closingWrapper
        {
          let range = lines[openingIndex].start..<lines[yamlClosingIndex + 1].contentEnd
          let candidate = String(source[range])
          if let rawYAML = parseCompleteEnvelope(candidate) {
            matchedBlock = WrappedFrontMatterBlock(
              rawYAML: rawYAML,
              range: range,
              openingLine: openingIndex + 1
            )
          }
          break
        }
        yamlClosingIndex += 1
      }

      if let matchedBlock {
        blocks.append(matchedBlock)
        openingIndex = yamlClosingIndex + 2
      } else {
        openingIndex += 1
      }
    }

    return WrappedFrontMatterScan(
      firstBlock: blocks.first,
      additionalOpeningLines: blocks.dropFirst().map(\.openingLine)
    )
  }

  private func parseCompleteEnvelope(_ candidate: String) -> String? {
    var input = Substring(candidate)
    let parser = Parse {
      syntax.openingWrapper
      "\n---\n"
      PrefixUpTo("---\n\(syntax.closingWrapper)").map(String.init)
      "---\n"
      syntax.closingWrapper
      End()
    }
    return try? parser.parse(&input)
  }

  private func physicalLines(in source: String) -> [PhysicalLine] {
    var result: [PhysicalLine] = []
    var start = source.startIndex
    while start < source.endIndex {
      let newline = source[start...].firstIndex(of: "\n")
      let contentEnd = newline ?? source.endIndex
      let nextStart = newline.map { source.index(after: $0) } ?? source.endIndex
      result.append(PhysicalLine(
        text: String(source[start..<contentEnd]),
        start: start,
        contentEnd: contentEnd
      ))
      start = nextStart
    }

    return result
  }

  private struct PhysicalLine {
    let text: String
    let start: String.Index
    let contentEnd: String.Index
  }
}
