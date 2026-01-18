import Foundation
import Yams

extension MarkdownDocument {
  /// Promotes a heading (decreases its level by 1) and optionally its children.
  ///
  /// Promotion decreases the heading level (e.g., H2 → H1). Headings at H1 cannot be promoted further
  /// and will remain at H1 (clamping behavior).
  ///
  /// - Parameters:
  ///   - index: The 0-based index of the heading to promote
  ///   - includeChildren: Whether to promote child headings as well (default: true)
  /// - Returns: A new MarkdownDocument with the adjusted headings
  /// - Throws: `HeadingAdjusterError` if the operation cannot be performed
  ///
  /// ## Example
  /// ```swift
  /// let doc = try MarkdownDocument(content: """
  ///   # Main
  ///   ## Section
  ///   ### Subsection
  ///   """)
  ///
  /// // Promote "Section" and its children
  /// let promoted = try await doc.promoteHeading(at: 1)
  /// // Result:
  /// // # Main
  /// // # Section      (H2→H1)
  /// // ## Subsection  (H3→H2)
  /// ```
  public func promoteHeading(at index: Int, includeChildren: Bool = true) async throws -> MarkdownDocument {
    try await adjustHeading(at: index, by: -1, includeChildren: includeChildren)
  }

  /// Demotes a heading (increases its level by 1) and optionally its children.
  ///
  /// Demotion increases the heading level (e.g., H1 → H2). Headings at H6 cannot be demoted further
  /// and will remain at H6 (clamping behavior).
  ///
  /// - Parameters:
  ///   - index: The 0-based index of the heading to demote
  ///   - includeChildren: Whether to demote child headings as well (default: true)
  /// - Returns: A new MarkdownDocument with the adjusted headings
  /// - Throws: `HeadingAdjusterError` if the operation cannot be performed
  ///
  /// ## Example
  /// ```swift
  /// let doc = try MarkdownDocument(content: """
  ///   # Main
  ///   ## Section
  ///   ### Subsection
  ///   """)
  ///
  /// // Demote "Main" and its children
  /// let demoted = try await doc.demoteHeading(at: 0)
  /// // Result:
  /// // ## Main        (H1→H2)
  /// // ### Section    (H2→H3)
  /// // #### Subsection (H3→H4)
  /// ```
  public func demoteHeading(at index: Int, includeChildren: Bool = true) async throws -> MarkdownDocument {
    try await adjustHeading(at: index, by: 1, includeChildren: includeChildren)
  }

  /// Adjusts a heading's level by a specified amount and optionally its children.
  ///
  /// This is the generalized method that both `promoteHeading` and `demoteHeading` use.
  /// Positive amounts increase the level (demote), negative amounts decrease it (promote).
  /// Levels are clamped to the valid range [H1, H6].
  ///
  /// - Parameters:
  ///   - index: The 0-based index of the heading to adjust
  ///   - amount: The amount to adjust by (negative to promote, positive to demote)
  ///   - includeChildren: Whether to adjust child headings as well (default: true)
  /// - Returns: A new MarkdownDocument with the adjusted headings
  /// - Throws: `HeadingAdjusterError` if the operation cannot be performed
  ///
  /// ## Example
  /// ```swift
  /// // Promote by 2 levels
  /// let promoted = try await doc.adjustHeading(at: 1, by: -2)
  ///
  /// // Demote by 3 levels
  /// let demoted = try await doc.adjustHeading(at: 0, by: 3)
  /// ```
  public func adjustHeading(
    at index: Int,
    by amount: Int,
    includeChildren: Bool = true
  ) async throws -> MarkdownDocument {
    // Parse the body to AST
    let root = try await parseAST()

    // Perform the adjustment
    let options = HeadingAdjuster.Options(
      targetIndex: index,
      adjustment: amount,
      includeChildren: includeChildren
    )

    let result = try await HeadingAdjuster.adjust(
      root: root,
      originalContent: body,
      options: options
    )

    // Reconstruct the full document with frontmatter
    let fullContent = try reconstructFullDocument(
      frontMatter: frontMatter,
      body: result.content
    )

    return try MarkdownDocument(content: fullContent)
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
