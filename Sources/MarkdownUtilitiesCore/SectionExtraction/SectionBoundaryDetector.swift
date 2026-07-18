//
//  SectionBoundaryDetector.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// Detects the boundaries of a section in a Markdown document.
///
/// A section consists of a heading and all content under it until the next
/// same-level or higher heading.
enum SectionBoundaryDetector {
  /// Information about a section's boundaries.
  struct Boundary: Equatable, Sendable {
    /// The line range of the section (1-based, inclusive).
    let lineRange: ClosedRange<Int>

    /// The indices of child headings within this section.
    let childIndices: [Int]

    /// The total number of lines in the original document.
    let documentLineCount: Int
  }

  /// Detects the boundary of a section starting at the specified heading.
  ///
  /// - Parameters:
  ///   - headings: All headings in the document
  ///   - targetIndex: Index of the target heading (0-based)
  ///   - documentLineCount: Total number of lines in the document
  /// - Returns: Boundary information for the section
  ///
  /// ## Algorithm
  /// 1. Find the target heading
  /// 2. Identify child headings using HeadingScope
  /// 3. Determine section end:
  ///    - If there's a next sibling/parent heading: line before that heading
  ///    - Otherwise: end of document
  static func detect(
    headings: [Heading],
    targetIndex: Int,
    documentLineCount: Int
  ) -> Boundary {
    let targetHeading = headings[targetIndex]
    let targetLevel = targetHeading.depth.rawValue

    // Use HeadingScope to identify children
    let scope = HeadingScope.identify(headings: headings, targetIndex: targetIndex)

    // Start line is the target heading's start line
    let startLine = targetHeading.position.start.line

    // Find the end line
    let endLine: Int

    // Find the next heading at same or higher level (sibling or parent)
    if let nextSiblingIndex = findNextSiblingOrParent(
      headings: headings,
      afterIndex: targetIndex,
      targetLevel: targetLevel
    ) {
      // Section ends at the line before the next sibling/parent
      let nextHeading = headings[nextSiblingIndex]
      endLine = nextHeading.position.start.line - 1
    } else {
      // No sibling/parent found - section extends to end of document
      endLine = documentLineCount
    }

    return Boundary(
      lineRange: startLine...endLine,
      childIndices: scope.childIndices,
      documentLineCount: documentLineCount
    )
  }

  /// Finds the index of the next heading at the same or higher level.
  ///
  /// - Parameters:
  ///   - headings: All headings in the document
  ///   - afterIndex: Index to start searching after
  ///   - targetLevel: The level to compare against
  /// - Returns: Index of the next sibling/parent heading, or nil if none found
  private static func findNextSiblingOrParent(
    headings: [Heading],
    afterIndex: Int,
    targetLevel: Int
  ) -> Int? {
    for index in (afterIndex + 1)..<headings.count {
      let heading = headings[index]
      if heading.depth.rawValue <= targetLevel {
        return index
      }
    }
    return nil
  }
}
