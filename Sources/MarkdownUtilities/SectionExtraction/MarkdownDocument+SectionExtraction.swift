//
//  MarkdownDocument+SectionExtraction.swift
//  MarkdownUtilities
//

import Foundation
import Yams

extension MarkdownDocument {
  /// Extracts a section from the document.
  ///
  /// A section consists of a heading and all content nested under it until the next
  /// same-level or higher heading.
  ///
  /// - Parameters:
  ///   - index: The 1-based index of the heading to extract (1 = first heading, 2 = second heading, etc.)
  ///   - removeFromOriginal: Whether to remove the section from the original document
  /// - Returns: A tuple containing:
  ///   - extracted: A new MarkdownDocument containing only the extracted section (no frontmatter)
  ///   - updated: A new MarkdownDocument with the section removed (preserves frontmatter), or nil if removeFromOriginal is false
  /// - Throws: `SectionExtractorError` if extraction fails
  ///
  /// ## Example
  /// ```swift
  /// let doc = try MarkdownDocument(content: """
  ///   # Section 1
  ///   Content 1.
  ///   ## Subsection 1.1
  ///   Nested content.
  ///   # Section 2
  ///   Content 2.
  ///   """)
  ///
  /// // Extract first section
  /// let (extracted, _) = try await doc.extractSection(at: 1)
  /// // extracted.body contains:
  /// // # Section 1
  /// // Content 1.
  /// // ## Subsection 1.1
  /// // Nested content.
  ///
  /// // Extract and remove second section
  /// let (extracted, updated) = try await doc.extractSection(at: 2, removeFromOriginal: true)
  /// // extracted.body contains section 2
  /// // updated.body contains only section 1
  /// ```
  public func extractSection(
    at index: Int,
    removeFromOriginal: Bool = false
  ) async throws -> (extracted: MarkdownDocument, updated: MarkdownDocument?) {
    // Parse the body to AST
    let root = try await parseAST()

    // Convert 1-based index to 0-based for internal processing
    let zeroBasedIndex = index - 1

    // Perform extraction
    let options = SectionExtractor.Options(
      targetIndex: zeroBasedIndex,
      removeFromOriginal: removeFromOriginal
    )

    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: body,
      options: options
    )

    // Create extracted document (no frontmatter - sections are content fragments)
    let extractedDoc = try MarkdownDocument(content: result.section.text)

    // Create updated document if removal was requested
    let updatedDoc: MarkdownDocument?
    if let remainingContent = result.remainingContent {
      // Reconstruct the full document with frontmatter
      let fullContent = try reconstructFullDocument(
        frontMatter: frontMatter,
        body: remainingContent
      )
      updatedDoc = try MarkdownDocument(content: fullContent)
    } else {
      updatedDoc = nil
    }

    return (extracted: extractedDoc, updated: updatedDoc)
  }

  /// Extracts a section from the document by heading name.
  ///
  /// A section consists of a heading and all content nested under it until the next
  /// same-level or higher heading. This method searches for the first heading that matches
  /// the given name.
  ///
  /// - Parameters:
  ///   - name: The text of the heading to extract
  ///   - caseSensitive: Whether to use case-sensitive matching (default: false)
  ///   - removeFromOriginal: Whether to remove the section from the original document
  /// - Returns: A tuple containing:
  ///   - extracted: A new MarkdownDocument containing only the extracted section (no frontmatter)
  ///   - updated: A new MarkdownDocument with the section removed (preserves frontmatter), or nil if removeFromOriginal is false
  /// - Throws: `SectionExtractorError` if extraction fails or heading not found
  ///
  /// ## Example
  /// ```swift
  /// let doc = try MarkdownDocument(content: """
  ///   # Introduction
  ///   Welcome text.
  ///   # Contributing
  ///   How to contribute.
  ///   # License
  ///   MIT License.
  ///   """)
  ///
  /// // Extract by heading name (case-insensitive)
  /// let (extracted, _) = try await doc.extractSection(byName: "contributing")
  /// // extracted.body contains the Contributing section
  ///
  /// // Extract and remove (case-sensitive)
  /// let (extracted, updated) = try await doc.extractSection(
  ///   byName: "License",
  ///   caseSensitive: true,
  ///   removeFromOriginal: true
  /// )
  /// ```
  public func extractSection(
    byName name: String,
    caseSensitive: Bool = false,
    removeFromOriginal: Bool = false
  ) async throws -> (extracted: MarkdownDocument, updated: MarkdownDocument?) {
    // Parse the body to AST
    let root = try await parseAST()

    // Perform extraction with name-based matching
    let options = SectionExtractor.Options(
      matchCriteria: .name(name, caseSensitive: caseSensitive),
      removeFromOriginal: removeFromOriginal
    )

    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: body,
      options: options
    )

    // Create extracted document (no frontmatter - sections are content fragments)
    let extractedDoc = try MarkdownDocument(content: result.section.text)

    // Create updated document if removal was requested
    let updatedDoc: MarkdownDocument?
    if let remainingContent = result.remainingContent {
      // Reconstruct the full document with frontmatter
      let fullContent = try reconstructFullDocument(
        frontMatter: frontMatter,
        body: remainingContent
      )
      updatedDoc = try MarkdownDocument(content: fullContent)
    } else {
      updatedDoc = nil
    }

    return (extracted: extractedDoc, updated: updatedDoc)
  }

  /// Reconstructs the full markdown document with frontmatter and body.
  ///
  /// - Parameters:
  ///   - frontMatter: The frontmatter mapping
  ///   - body: The body content
  /// - Returns: Complete markdown content with frontmatter (if non-empty) and body
  private func reconstructFullDocument(
    frontMatter: Yams.Node.Mapping,
    body: String
  ) throws -> String {
    // If frontmatter is empty, return just the body
    guard !frontMatter.isEmpty else {
      return body
    }

    // Serialize frontmatter to YAML
    let yamlContent = try YAMLConversion.serialize(frontMatter)

    // Reconstruct with frontmatter delimiters
    return """
      ---
      \(yamlContent)---
      \(body)
      """
  }
}
