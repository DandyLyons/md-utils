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
    /// Criteria for matching the target heading.
    public enum MatchCriteria: Sendable {
      /// Match by 0-based heading index.
      case index(Int)

      /// Match by heading text name.
      /// - Parameters:
      ///   - name: The heading text to search for
      ///   - caseSensitive: Whether matching should be case-sensitive
      case name(String, caseSensitive: Bool)
    }

    /// The criteria for identifying which heading to extract.
    public let matchCriteria: MatchCriteria

    /// Whether to remove the section from the original content.
    public let removeFromOriginal: Bool

    public init(matchCriteria: MatchCriteria, removeFromOriginal: Bool = false) {
      self.matchCriteria = matchCriteria
      self.removeFromOriginal = removeFromOriginal
    }

    /// Convenience initializer for index-based extraction.
    public init(targetIndex: Int, removeFromOriginal: Bool = false) {
      self.matchCriteria = .index(targetIndex)
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

  /// Finds the index of a heading by name.
  ///
  /// - Parameters:
  ///   - headings: Array of headings to search
  ///   - name: The heading name to search for
  ///   - caseSensitive: Whether to use case-sensitive matching
  /// - Returns: The 0-based index of the first matching heading
  /// - Throws: `SectionExtractorError.headingNotFound` if no match is found
  private static func findHeadingIndex(
    headings: [Heading],
    name: String,
    caseSensitive: Bool
  ) throws -> Int {
    // Extract text from all headings
    let headingTexts = headings.map { HeadingTextExtractor.extractText(from: $0) }

    // Search for matching heading
    let foundIndex: Int?
    if caseSensitive {
      foundIndex = headingTexts.firstIndex(of: name)
    } else {
      foundIndex = headingTexts.firstIndex { $0.lowercased() == name.lowercased() }
    }

    guard let index = foundIndex else {
      throw SectionExtractorError.headingNotFound(
        name: name,
        caseSensitive: caseSensitive,
        availableHeadings: headingTexts
      )
    }

    return index
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

    // Resolve target index based on match criteria
    let targetIndex: Int
    switch options.matchCriteria {
    case .index(let index):
      // Validate target index
      guard index >= 0 && index < headings.count else {
        throw SectionExtractorError.invalidTargetIndex(
          requested: index + 1,  // Convert to 1-based for error message
          totalHeadings: headings.count
        )
      }
      targetIndex = index

    case .name(let name, let caseSensitive):
      // Find heading by name
      targetIndex = try findHeadingIndex(
        headings: headings,
        name: name,
        caseSensitive: caseSensitive
      )
    }

    // Split content into lines
    let lines = originalContent.components(separatedBy: .newlines)
    let documentLineCount = lines.count

    // Detect section boundaries
    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: targetIndex,
      documentLineCount: documentLineCount
    )

    // Extract section lines (convert 1-based line numbers to 0-based array indices)
    let startIndex = boundary.lineRange.lowerBound - 1
    let endIndex = boundary.lineRange.upperBound - 1

    guard startIndex >= 0 && endIndex < lines.count else {
      throw SectionExtractorError.invalidTargetIndex(
        requested: targetIndex + 1,
        totalHeadings: headings.count
      )
    }

    let sectionLines = Array(lines[startIndex...endIndex])
    let sectionText = sectionLines.joined(separator: "\n")

    // Create section content
    let section = SectionContent(
      text: sectionText,
      heading: headings[targetIndex],
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
