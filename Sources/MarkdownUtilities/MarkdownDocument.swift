//
//  MarkdownDocument.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax
import Parsing
import Yams

/// A representation of a Markdown document.
public struct MarkdownDocument {
  /// The YAML frontmatter as a parsed mapping.
  ///
  /// This is an empty mapping if the document has no frontmatter.
  public var frontMatter: Yams.Node.Mapping

  /// The body content of the document (everything after frontmatter, or entire document if no frontmatter).
  ///
  /// This starts immediately after the closing `---` delimiter if frontmatter exists,
  /// otherwise it contains the entire document content.
  public var body: String

  /// Initialize a markdown document by parsing the content to separate frontmatter from body.
  ///
  /// This initializer uses `FrontMatterParser` to detect and separate YAML frontmatter
  /// delimited by `---` markers. The frontmatter is immediately parsed into a `Yams.Node.Mapping`,
  /// and the body contains everything after the closing delimiter.
  ///
  /// - Parameter content: The markdown content to parse
  /// - Throws: `YAMLConversionError` if the frontmatter exists but is invalid YAML or not a mapping
  public init(content: String) throws {
    let parser = FrontMatterParser()
    var input = Substring(content)
    let (rawFrontMatter, body) = try parser.parse(&input)

    self.frontMatter = try YAMLConversion.parse(rawFrontMatter)
    self.body = body
  }
}
