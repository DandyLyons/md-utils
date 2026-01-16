//
//  MarkdownDocument+FrontMatter.swift
//  MarkdownUtilities
//
//  Extensions for MarkdownDocument to support frontmatter operations
//

import Foundation
import Yams

extension MarkdownDocument {
  /// Lazily parsed frontmatter as a `Yams.Node.Mapping`.
  ///
  /// This property parses the `rawFrontMatter` string into a structured YAML mapping
  /// only when accessed. If `rawFrontMatter` is empty or contains only whitespace,
  /// this returns an empty mapping.
  ///
  /// - Throws: `YAMLConversionError.invalidYAML` if the YAML syntax is invalid,
  ///           or `YAMLConversionError.notAMapping` if the root is not a mapping
  public var frontMatter: Yams.Node.Mapping {
    get throws {
      try YAMLConversion.parse(rawFrontMatter)
    }
  }

  /// Check if the document has frontmatter.
  ///
  /// Returns `true` if `rawFrontMatter` contains non-whitespace content.
  public var hasFrontMatter: Bool {
    !rawFrontMatter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Reconstruct the full document from frontmatter and body.
  ///
  /// This method combines the frontmatter (with delimiters) and body back into
  /// a single markdown document string. If there's no frontmatter (empty or whitespace-only),
  /// it returns just the body.
  ///
  /// - Returns: The reconstructed markdown document
  public func render() -> String {
    // Only add delimiters if there's actual frontmatter content
    let trimmed = rawFrontMatter.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return body
    }

    // Add delimiters around frontmatter
    return """
    ---
    \(rawFrontMatter)---
    \(body)
    """
  }
}
