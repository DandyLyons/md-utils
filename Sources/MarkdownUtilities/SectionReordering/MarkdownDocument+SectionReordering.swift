//
//  MarkdownDocument+SectionReordering.swift
//  MarkdownUtilities
//

import Foundation
import Yams

extension MarkdownDocument {
  /// Moves a section up among its siblings.
  ///
  /// - Parameters:
  ///   - index: The 1-based index of the heading to move (1 = first heading)
  ///   - count: Number of positions to move (default: 1). Clamped to available positions.
  /// - Returns: A new MarkdownDocument with the section moved up
  /// - Throws: `SectionReordererError` if the section cannot be moved
  public func moveSectionUp(at index: Int, count: Int = 1) async throws -> MarkdownDocument {
    let root = try await parseAST()
    let zeroBasedIndex = index - 1

    let options = SectionReorderer.Options(
      matchCriteria: .index(zeroBasedIndex),
      direction: .up,
      count: count
    )

    let newBody = try SectionReorderer.reorder(
      root: root,
      originalContent: body,
      options: options
    )

    let fullContent = try reconstructFullDocument(frontMatter: frontMatter, body: newBody)
    return try MarkdownDocument(content: fullContent)
  }

  /// Moves a section up among its siblings, identified by name.
  ///
  /// - Parameters:
  ///   - name: The text of the heading to move
  ///   - caseSensitive: Whether to use case-sensitive matching (default: false)
  ///   - count: Number of positions to move (default: 1). Clamped to available positions.
  /// - Returns: A new MarkdownDocument with the section moved up
  /// - Throws: `SectionReordererError` if the section cannot be moved
  public func moveSectionUp(
    byName name: String,
    caseSensitive: Bool = false,
    count: Int = 1
  ) async throws -> MarkdownDocument {
    let root = try await parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .name(name, caseSensitive: caseSensitive),
      direction: .up,
      count: count
    )

    let newBody = try SectionReorderer.reorder(
      root: root,
      originalContent: body,
      options: options
    )

    let fullContent = try reconstructFullDocument(frontMatter: frontMatter, body: newBody)
    return try MarkdownDocument(content: fullContent)
  }

  /// Moves a section down among its siblings.
  ///
  /// - Parameters:
  ///   - index: The 1-based index of the heading to move (1 = first heading)
  ///   - count: Number of positions to move (default: 1). Clamped to available positions.
  /// - Returns: A new MarkdownDocument with the section moved down
  /// - Throws: `SectionReordererError` if the section cannot be moved
  public func moveSectionDown(at index: Int, count: Int = 1) async throws -> MarkdownDocument {
    let root = try await parseAST()
    let zeroBasedIndex = index - 1

    let options = SectionReorderer.Options(
      matchCriteria: .index(zeroBasedIndex),
      direction: .down,
      count: count
    )

    let newBody = try SectionReorderer.reorder(
      root: root,
      originalContent: body,
      options: options
    )

    let fullContent = try reconstructFullDocument(frontMatter: frontMatter, body: newBody)
    return try MarkdownDocument(content: fullContent)
  }

  /// Moves a section down among its siblings, identified by name.
  ///
  /// - Parameters:
  ///   - name: The text of the heading to move
  ///   - caseSensitive: Whether to use case-sensitive matching (default: false)
  ///   - count: Number of positions to move (default: 1). Clamped to available positions.
  /// - Returns: A new MarkdownDocument with the section moved down
  /// - Throws: `SectionReordererError` if the section cannot be moved
  public func moveSectionDown(
    byName name: String,
    caseSensitive: Bool = false,
    count: Int = 1
  ) async throws -> MarkdownDocument {
    let root = try await parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .name(name, caseSensitive: caseSensitive),
      direction: .down,
      count: count
    )

    let newBody = try SectionReorderer.reorder(
      root: root,
      originalContent: body,
      options: options
    )

    let fullContent = try reconstructFullDocument(frontMatter: frontMatter, body: newBody)
    return try MarkdownDocument(content: fullContent)
  }

  /// Moves a section to a specific position among its siblings.
  ///
  /// - Parameters:
  ///   - index: The 1-based index of the heading to move (1 = first heading)
  ///   - position: The target position among siblings (1-based)
  /// - Returns: A new MarkdownDocument with the section at the new position
  /// - Throws: `SectionReordererError` if the section cannot be moved
  public func moveSection(at index: Int, toPosition position: Int) async throws -> MarkdownDocument {
    let root = try await parseAST()
    let zeroBasedIndex = index - 1

    let options = SectionReorderer.MoveToOptions(
      matchCriteria: .index(zeroBasedIndex),
      targetPosition: position
    )

    let newBody = try SectionReorderer.moveTo(
      root: root,
      originalContent: body,
      options: options
    )

    let fullContent = try reconstructFullDocument(frontMatter: frontMatter, body: newBody)
    return try MarkdownDocument(content: fullContent)
  }

  /// Moves a section to a specific position among its siblings, identified by name.
  ///
  /// - Parameters:
  ///   - name: The text of the heading to move
  ///   - caseSensitive: Whether to use case-sensitive matching (default: false)
  ///   - position: The target position among siblings (1-based)
  /// - Returns: A new MarkdownDocument with the section at the new position
  /// - Throws: `SectionReordererError` if the section cannot be moved
  public func moveSection(
    byName name: String,
    caseSensitive: Bool = false,
    toPosition position: Int
  ) async throws -> MarkdownDocument {
    let root = try await parseAST()

    let options = SectionReorderer.MoveToOptions(
      matchCriteria: .name(name, caseSensitive: caseSensitive),
      targetPosition: position
    )

    let newBody = try SectionReorderer.moveTo(
      root: root,
      originalContent: body,
      options: options
    )

    let fullContent = try reconstructFullDocument(frontMatter: frontMatter, body: newBody)
    return try MarkdownDocument(content: fullContent)
  }

  /// Reconstructs the full markdown document with frontmatter and body.
  private func reconstructFullDocument(
    frontMatter: Yams.Node.Mapping,
    body: String
  ) throws -> String {
    guard !frontMatter.isEmpty else {
      return body
    }

    let yamlContent = try YAMLConversion.serialize(frontMatter)

    return """
      ---
      \(yamlContent)---
      \(body)
      """
  }
}
