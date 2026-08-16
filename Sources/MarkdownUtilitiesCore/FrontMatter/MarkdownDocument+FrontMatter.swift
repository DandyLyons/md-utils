//
//  MarkdownDocument+FrontMatter.swift
//  MarkdownUtilities
//
//  Extensions for MarkdownDocument to support frontmatter operations
//

import Foundation
/// Adds frontmatter behavior to ``MarkdownDocument``.
///
/// See <doc:FrontmatterWorkflows> for workflow details.
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
  /// - Throws: If serialization in the selected frontmatter format fails
  public func render() throws -> String {
    guard !frontMatter.isEmpty else { return body }
    let format = frontMatterFormat ?? .yaml

    let serialized = try FrontMatterConversion.serialize(frontMatter, format: format)

    return """
    \(format.delimiter)
    \(serialized)\(format.delimiter)
    \(body)
    """
  }
}
