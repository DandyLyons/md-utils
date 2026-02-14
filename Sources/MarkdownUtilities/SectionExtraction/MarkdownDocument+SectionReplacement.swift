//
//  MarkdownDocument+SectionReplacement.swift
//  MarkdownUtilities
//

import Foundation
import Yams

extension MarkdownDocument {
  /// Replaces a section's body content, preserving the heading.
  ///
  /// The heading line is kept intact; only the content lines beneath it (up to the next
  /// same-level or higher heading) are replaced with `newContent`.
  ///
  /// - Parameters:
  ///   - index: The 1-based index of the heading (1 = first heading, 2 = second heading, etc.)
  ///   - newContent: The replacement body content (everything below the heading)
  /// - Returns: A new MarkdownDocument with the section body replaced
  /// - Throws: `SectionExtractorError` if the section cannot be found
  public func replaceSection(
    at index: Int,
    with newContent: String
  ) async throws -> MarkdownDocument {
    let root = try await parseAST()
    let zeroBasedIndex = index - 1

    let options = SectionExtractor.Options(
      targetIndex: zeroBasedIndex,
      removeFromOriginal: false
    )

    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: body,
      options: options
    )

    let replacedBody = replaceSectionBody(
      in: body,
      sectionRange: result.section.lineRange,
      with: newContent
    )

    return try rebuildDocument(withBody: replacedBody)
  }

  /// Replaces a section's body content, preserving the heading.
  ///
  /// The heading line is kept intact; only the content lines beneath it (up to the next
  /// same-level or higher heading) are replaced with `newContent`.
  ///
  /// - Parameters:
  ///   - name: The text of the heading whose body to replace
  ///   - caseSensitive: Whether to use case-sensitive matching (default: false)
  ///   - newContent: The replacement body content (everything below the heading)
  /// - Returns: A new MarkdownDocument with the section body replaced
  /// - Throws: `SectionExtractorError` if the section cannot be found
  public func replaceSection(
    byName name: String,
    caseSensitive: Bool = false,
    with newContent: String
  ) async throws -> MarkdownDocument {
    let root = try await parseAST()

    let options = SectionExtractor.Options(
      matchCriteria: .name(name, caseSensitive: caseSensitive),
      removeFromOriginal: false
    )

    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: body,
      options: options
    )

    let replacedBody = replaceSectionBody(
      in: body,
      sectionRange: result.section.lineRange,
      with: newContent
    )

    return try rebuildDocument(withBody: replacedBody)
  }

  /// Replaces the body lines of a section (everything after the heading line).
  ///
  /// - Parameters:
  ///   - content: The original document body
  ///   - sectionRange: The 1-based inclusive line range of the full section (heading + body)
  ///   - replacement: The new body content to place after the heading
  /// - Returns: The content with the section body replaced
  private func replaceSectionBody(
    in content: String,
    sectionRange: ClosedRange<Int>,
    with replacement: String
  ) -> String {
    var lines = content.components(separatedBy: .newlines)

    let headingLineIndex = sectionRange.lowerBound - 1  // 0-based
    let bodyStartIndex = headingLineIndex + 1
    let bodyEndIndex = sectionRange.upperBound - 1  // 0-based, inclusive

    let replacementLines = replacement.isEmpty ? [] : replacement.components(separatedBy: .newlines)

    if bodyStartIndex <= bodyEndIndex {
      // Section has body lines — replace them
      lines.replaceSubrange(bodyStartIndex...bodyEndIndex, with: replacementLines)
    } else {
      // Section is heading-only — insert after the heading
      lines.insert(contentsOf: replacementLines, at: bodyStartIndex)
    }

    return lines.joined(separator: "\n")
  }

  /// Rebuilds the document with a new body, preserving frontmatter.
  private func rebuildDocument(withBody newBody: String) throws -> MarkdownDocument {
    guard !frontMatter.isEmpty else {
      return try MarkdownDocument(content: newBody)
    }

    let yamlContent = try YAMLConversion.serialize(frontMatter)

    let fullContent = """
      ---
      \(yamlContent)---
      \(newBody)
      """

    return try MarkdownDocument(content: fullContent)
  }
}
