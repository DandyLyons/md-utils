//
//  MarkdownDocument+FrontMatter.swift
//  MarkdownUtilities
//
//  Extensions for MarkdownDocument to support frontmatter operations
//

import Foundation
import Yams

extension MarkdownDocument {
  /// Check if the document has frontmatter.
  ///
  /// Returns `true` if the frontmatter mapping is not empty.
  public var hasFrontMatter: Bool {
    !frontMatter.isEmpty
  }

  /// Reconstruct the full document from frontmatter and body.
  ///
  /// This method combines the frontmatter (with delimiters) and body back into
  /// a single markdown document string. If there's no frontmatter (empty mapping),
  /// it returns just the body.
  ///
  /// - Returns: The reconstructed markdown document
  /// - Throws: If YAML serialization fails
  public func render() throws -> String {
    // Only add delimiters if there's actual frontmatter content
    if frontMatter.isEmpty {
      return body
    }

    // Serialize frontmatter back to YAML
    let yamlString = try YAMLConversion.serialize(frontMatter)

    // Add delimiters around frontmatter
    return """
    ---
    \(yamlString)---
    \(body)
    """
  }
}
