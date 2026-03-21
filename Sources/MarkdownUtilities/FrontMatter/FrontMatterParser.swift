//
//  FrontMatterParser.swift
//  MarkdownUtilities
//
//  Created by Claude Code
//

import Foundation
import Parsing

/// Parser for separating frontmatter from markdown body content.
///
/// This parser detects YAML frontmatter delimited by `---` markers and separates
/// it from the body content without parsing the YAML itself.
struct FrontMatterParser: Parsing.Parser {
  typealias Input = Substring
  typealias Output = (rawFrontMatter: String, body: String)

  func parse(_ input: inout Substring) throws -> Output {
    // Check if input starts with frontmatter delimiter (Unix line endings only)
    if input.starts(with: "---\n") {
      var workingInput = input
      do {
        // Try to extract just the frontmatter (up to and including closing delimiter)
        let rawFrontMatter = try frontMatterOnlyParser.parse(&workingInput)
        // Whatever remains in workingInput is the body
        let body = String(workingInput)
        input = ""
        return (rawFrontMatter, body)
      } catch {
        // No closing delimiter found - treat entire content as body with empty frontmatter
        let body = String(input)
        input = ""
        return ("", body)
      }
    } else {
      // No opening delimiter - empty frontmatter, entire content is body
      let body = String(input)
      input = ""
      return ("", body)
    }
  }

  /// Returns true if the raw YAML string contains any YAML comments.
  ///
  /// This is a naive check that detects standalone comment lines — lines where
  /// the first non-whitespace character is `#`. It does not detect inline
  /// comments (e.g. `key: value # comment`).
  ///
  /// Detection runs on the raw frontmatter string before Yams parses it,
  /// because Yams (via libYAML) discards comments and they are unrecoverable
  /// from the parsed AST.
  static func containsYAMLComments(_ rawYAML: String) -> Bool {
    // Use swift-parsing's Prefix to consume leading horizontal whitespace,
    // then check if the first remaining character is '#'.
    // This catches standalone comment lines; inline comments (key: value # …)
    // are out of scope for this naive check.
    let whitespace = Prefix<Substring>(while: { $0 == " " || $0 == "\t" })
    for line in rawYAML.split(separator: "\n", omittingEmptySubsequences: false) {
      var lineInput = line[...]
      _ = try? whitespace.parse(&lineInput)
      if lineInput.first == "#" {
        return true
      }
    }
    return false
  }

  /// Parser that extracts only the frontmatter content (between delimiters)
  private var frontMatterOnlyParser: some Parsing.Parser<Substring, String> {
    Parse {
      "---\n"                              // Opening delimiter with newline
      PrefixUpTo("---").map { String($0) } // Content until closing delimiter
      "---"                                // Closing delimiter
      Optionally { "\n" }                  // Optional newline after closing
    }
    .map { (frontMatter, _) in
      frontMatter
    }
  }
}
