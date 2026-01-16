//
//  MarkdownDocument.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax
import Parsing

/// A representation of a Markdown document.
public struct MarkdownDocument {
  /// The raw markdown content (full document including frontmatter and body).
  public var content: String

  /// The raw frontmatter content (without delimiters).
  ///
  /// This is an empty string if the document has no frontmatter.
  /// The frontmatter is the YAML content between `---` delimiters at the start of the document.
  public var rawFrontMatter: String

  /// The body content of the document (everything after frontmatter, or entire document if no frontmatter).
  ///
  /// This starts immediately after the closing `---` delimiter if frontmatter exists,
  /// otherwise it contains the entire document content.
  public var body: String

  /// The root initializer for a markdown document.
  ///
  /// This is a simple initializer that does not parse frontmatter.
  /// Use `init(parsing:)` to automatically separate frontmatter from body.
  public init(content: String) {
    self.content = content
    // For backward compatibility, treat entire content as body with no frontmatter
    self.rawFrontMatter = ""
    self.body = content
  }

  /// Initialize a markdown document by parsing the content to separate frontmatter from body.
  ///
  /// This initializer uses `FrontMatterParser` to detect and separate YAML frontmatter
  /// delimited by `---` markers. The frontmatter is stored as a raw string (not parsed),
  /// and the body contains everything after the closing delimiter.
  ///
  /// - Parameter parsing: The markdown content to parse
  /// - Throws: Only throws if the parser encounters an unexpected error (normally this doesn't throw)
  public init(parsing content: String) throws {
    let parser = FrontMatterParser()
    var input = Substring(content)
    let (rawFrontMatter, body) = try parser.parse(&input)

    self.content = content
    self.rawFrontMatter = rawFrontMatter
    self.body = body
  }
}
