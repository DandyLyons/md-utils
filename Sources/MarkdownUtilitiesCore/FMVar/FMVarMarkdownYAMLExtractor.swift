import Foundation
import Parsing

/// Result of locating YAML frontmatter in one Markdown source snapshot.
public enum FMVarMarkdownYAMLExtraction: Equatable, Sendable {
  /// Exact text between the YAML delimiter lines.
  case yaml(String)
  /// The Markdown source did not begin with a frontmatter delimiter.
  case missing
  /// The Markdown source began with TOML frontmatter.
  case unsupportedTOML
  /// A YAML opening delimiter did not have a complete closing delimiter line.
  case malformed
}

/// Extracts the authoritative YAML substring from Markdown without normalizing its contents.
///
/// This parser intentionally follows the package's LF-only Markdown frontmatter delimiter policy.
/// Standalone YAML decoding is unaffected and may contain any YAML-supported line endings.
public struct FMVarMarkdownYAMLExtractor: Parsing.Parser, Sendable {
  public typealias Input = Substring
  public typealias Output = FMVarMarkdownYAMLExtraction

  /// Creates a lossless Markdown YAML-frontmatter extractor.
  public init() {}

  /// Consumes one complete Markdown snapshot and returns its frontmatter extraction outcome.
  public func parse(_ input: inout Substring) -> FMVarMarkdownYAMLExtraction {
    let source = String(input)
    input = input[input.endIndex...]
    if source.hasPrefix("+++\n") { return .unsupportedTOML }
    guard source.hasPrefix("---\n") else { return .missing }

    let contentStart = source.index(source.startIndex, offsetBy: 4)
    var lineStart = contentStart
    while lineStart <= source.endIndex {
      let lineEnd = source[lineStart...].firstIndex(of: "\n") ?? source.endIndex
      let line = source[lineStart..<lineEnd]
      if line == "---" {
        var contentEnd = lineStart
        if contentEnd > contentStart {
          let prior = source.index(before: contentEnd)
          if source[prior] == "\n" { contentEnd = prior }
        }
        return .yaml(String(source[contentStart..<contentEnd]))
      }
      guard lineEnd < source.endIndex else { break }
      lineStart = source.index(after: lineEnd)
    }
    return .malformed
  }
}
