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

  /// Parse the body text into a Markdown AST.
  ///
  /// This method uses the MarkdownSyntax library to parse the body content into an Abstract Syntax Tree (AST).
  /// The AST is returned as a `Root` structure containing the parsed markdown elements.
  /// Each call parses fresh - there is no internal caching.
  ///
  /// - Returns: A `Root` structure containing the parsed AST
  /// - Throws: If markdown parsing fails (rare - MarkdownSyntax is very permissive)
  ///
  /// ## Example
  /// ```swift
  /// let doc = try MarkdownDocument(content: "# Hello\n\nWorld")
  /// let ast = try await doc.parseAST()
  /// print(ast.children.count)  // 2 (heading + paragraph)
  /// ```
  public func parseAST() async throws -> Root {
    let markdown = try await Markdown(text: body)
    return await markdown.parse()
  }
}
