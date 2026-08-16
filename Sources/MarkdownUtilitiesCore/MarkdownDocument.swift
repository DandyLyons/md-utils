//
//  MarkdownDocument.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax
import Parsing

/// A parsed representation of Markdown content.
///
/// A document contains only concepts encoded in the Markdown text: parsed YAML
/// frontmatter, body text, and a derived Markdown AST. It has no persistent
/// identity, logical path, revision, or storage context. Use ``MarkdownRecord``
/// for canonical, addressable content that must remain representable even when
/// its frontmatter is invalid.
public struct MarkdownDocument: @unchecked Sendable {
  /// The YAML or TOML frontmatter as a format-neutral parsed mapping.
  ///
  /// This is an empty mapping if the document has no frontmatter.
  public var frontMatter: FrontMatter

  /// The serialization format of the physical frontmatter block, or `nil` when absent.
  public var frontMatterFormat: FrontMatterFormat?

  /// The body content of the document (everything after frontmatter, or entire document if no frontmatter).
  ///
  /// This starts immediately after the closing `---` delimiter if frontmatter exists,
  /// otherwise it contains the entire document content.
  public var body: String

  /// Initialize a markdown document by parsing the content to separate frontmatter from body.
  ///
  /// This initializer detects YAML (`---`) or TOML (`+++`) frontmatter, parses it
  /// into ``FrontMatter``, and retains the source format for rendering.
  ///
  /// - Parameter content: The markdown content to parse
  /// - Throws: If frontmatter is invalid or its root is not a mapping
  public init(content: String) throws {
    let parser = FrontMatterParser()
    var input = Substring(content)
    let (rawFrontMatter, body, format) = try parser.parse(&input)

    self.frontMatter = try format.map { try FrontMatterConversion.parse(rawFrontMatter, format: $0) }
      ?? FrontMatter()
    self.frontMatterFormat = format
    self.body = body
  }

  /// Initialize a markdown document directly from its parsed components.
  ///
  /// Use this when frontmatter and body are already available as structured data,
  /// avoiding the YAML serialize/parse round-trip that `init(content:)` performs.
  ///
  /// - Parameters:
  ///   - frontMatter: The parsed format-neutral frontmatter mapping (empty if none)
  ///   - body: The markdown body text
  public init(
    frontMatter: FrontMatter,
    body: String,
    frontMatterFormat: FrontMatterFormat? = nil
  ) {
    self.frontMatter = frontMatter
    self.frontMatterFormat = frontMatterFormat ?? (frontMatter.isEmpty ? nil : .yaml)
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
