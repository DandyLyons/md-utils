//
//  SectionExtractor.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// Extracts sections from Markdown documents.
///
/// A section consists of a heading and all content nested under it until the next
/// same-level or higher heading.
public enum SectionExtractor {
  /// Options for section extraction.
  public struct Options: Sendable {
    /// The 0-based index of the heading to extract.
    public let targetIndex: Int

    /// Whether to remove the section from the original content.
    public let removeFromOriginal: Bool

    public init(targetIndex: Int, removeFromOriginal: Bool = false) {
      self.targetIndex = targetIndex
      self.removeFromOriginal = removeFromOriginal
    }
  }

  /// Result of a section extraction operation.
  public struct Result: Sendable {
    /// The extracted section.
    public let section: SectionContent

    /// The remaining content after removal (nil if removeFromOriginal was false).
    public let remainingContent: String?

    public init(section: SectionContent, remainingContent: String? = nil) {
      self.section = section
      self.remainingContent = remainingContent
    }
  }

  /// Extracts a section from a Markdown document.
  ///
  /// - Parameters:
  ///   - root: The Markdown AST root
  ///   - originalContent: The original document content
  ///   - options: Extraction options
  /// - Returns: Extraction result containing the section and optionally the remaining content
  /// - Throws: `SectionExtractorError` if extraction fails
  public static func extract(
    root: Root,
    originalContent: String,
    options: Options
  ) async throws -> Result {
    // Validate document has content
    guard !originalContent.isEmpty else {
      throw SectionExtractorError.emptyDocument
    }

    // Extract headings from AST
    let headings = extractHeadings(from: root.children)

    guard !headings.isEmpty else {
      throw SectionExtractorError.noHeadingsInDocument
    }

    // Validate target index
    guard options.targetIndex >= 0 && options.targetIndex < headings.count else {
      throw SectionExtractorError.invalidTargetIndex(
        requested: options.targetIndex + 1,  // Convert to 1-based for error message
        totalHeadings: headings.count
      )
    }

    // Split content into lines
    let lines = originalContent.components(separatedBy: .newlines)
    let documentLineCount = lines.count

    // Detect section boundaries
    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: options.targetIndex,
      documentLineCount: documentLineCount
    )

    // Extract section lines (convert 1-based line numbers to 0-based array indices)
    let startIndex = boundary.lineRange.lowerBound - 1
    let endIndex = boundary.lineRange.upperBound - 1

    guard startIndex >= 0 && endIndex < lines.count else {
      throw SectionExtractorError.invalidTargetIndex(
        requested: options.targetIndex + 1,
        totalHeadings: headings.count
      )
    }

    let sectionLines = Array(lines[startIndex...endIndex])
    let sectionText = sectionLines.joined(separator: "\n")

    // Create section content
    let section = SectionContent(
      text: sectionText,
      heading: headings[options.targetIndex],
      lineRange: boundary.lineRange,
      childHeadingCount: boundary.childIndices.count
    )

    // Optionally build remaining content
    let remainingContent: String?
    if options.removeFromOriginal {
      var remainingLines = lines
      remainingLines.removeSubrange(startIndex...endIndex)
      remainingContent = remainingLines.joined(separator: "\n")
    } else {
      remainingContent = nil
    }

    return Result(section: section, remainingContent: remainingContent)
  }

  /// Extracts all heading elements from content nodes.
  private static func extractHeadings(from content: [Content]) -> [Heading] {
    content.compactMap { $0 as? Heading }
  }
}
