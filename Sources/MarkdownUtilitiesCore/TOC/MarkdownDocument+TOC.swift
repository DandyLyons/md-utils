//
//  MarkdownDocument+TOC.swift
//  MarkdownUtilities
//

import Foundation

/// Convenience methods for generating table of contents from MarkdownDocument.
extension MarkdownDocument {

  /// Generate a table of contents from this document's body.
  ///
  /// Parses the document body into an AST and generates a TOC from the headings.
  ///
  /// - Parameter options: TOC generation options (default: all defaults)
  /// - Returns: A TableOfContents structure
  /// - Throws: If AST parsing fails or options are invalid
  ///
  /// ## Example
  /// ```swift
  /// let doc = try MarkdownDocument(content: markdownText)
  /// let toc = try await doc.generateTOC()
  /// ```
  public func generateTOC(
    options: TOCGenerator.Options = TOCGenerator.Options()
  ) async throws -> TableOfContents {
    let root = try await parseAST()
    return try TOCGenerator.generate(from: root, options: options)
  }
}
