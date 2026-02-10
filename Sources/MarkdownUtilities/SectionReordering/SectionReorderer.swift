//
//  SectionReorderer.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// Reorders sections within a Markdown document.
///
/// Sections can be moved up or down among their siblings, or to a specific position.
/// A section includes its heading and all nested content until the next same-level
/// or higher heading.
public enum SectionReorderer {
  /// The direction to move a section.
  public enum Direction: Sendable {
    case up
    case down
  }

  /// Options for identifying the section to reorder.
  public struct Options: Sendable {
    /// The criteria for identifying which heading to move.
    public let matchCriteria: SectionExtractor.Options.MatchCriteria

    /// The direction to move the section.
    public let direction: Direction

    /// The number of positions to move (must be >= 1).
    public let count: Int

    public init(
      matchCriteria: SectionExtractor.Options.MatchCriteria,
      direction: Direction,
      count: Int = 1
    ) {
      self.matchCriteria = matchCriteria
      self.direction = direction
      self.count = max(1, count)
    }
  }

  /// Options for moving a section to a specific position.
  public struct MoveToOptions: Sendable {
    /// The criteria for identifying which heading to move.
    public let matchCriteria: SectionExtractor.Options.MatchCriteria

    /// The target position among siblings (1-based).
    public let targetPosition: Int

    public init(matchCriteria: SectionExtractor.Options.MatchCriteria, targetPosition: Int) {
      self.matchCriteria = matchCriteria
      self.targetPosition = targetPosition
    }
  }

  /// Moves a section up or down among its siblings.
  ///
  /// - Parameters:
  ///   - root: The Markdown AST root
  ///   - originalContent: The original document content (body only, no frontmatter)
  ///   - options: Options specifying which section to move, direction, and count
  /// - Returns: The reordered document content
  /// - Throws: `SectionReordererError` if the operation fails
  public static func reorder(
    root: Root,
    originalContent: String,
    options: Options
  ) throws -> String {
    guard !originalContent.isEmpty else {
      throw SectionReordererError.emptyDocument
    }

    let headings = extractHeadings(from: root.children)

    guard !headings.isEmpty else {
      throw SectionReordererError.noHeadingsInDocument
    }

    let targetIndex = try resolveTargetIndex(headings: headings, matchCriteria: options.matchCriteria)

    let siblingInfo = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: targetIndex)

    guard siblingInfo.siblingIndices.count > 1 else {
      throw SectionReordererError.noSiblings
    }

    // Validate direction is possible
    switch options.direction {
    case .up:
      guard siblingInfo.canMoveUp else {
        throw SectionReordererError.cannotMoveUp
      }
    case .down:
      guard siblingInfo.canMoveDown else {
        throw SectionReordererError.cannotMoveDown
      }
    }

    // Compute target position, clamping to valid bounds
    let targetPosition: Int
    switch options.direction {
    case .up:
      targetPosition = max(0, siblingInfo.positionAmongSiblings - options.count)
    case .down:
      targetPosition = min(
        siblingInfo.siblingIndices.count - 1,
        siblingInfo.positionAmongSiblings + options.count
      )
    }

    // For a single-position swap, use the faster swap path
    if options.count == 1 {
      let swapTargetIndex: Int
      switch options.direction {
      case .up:
        guard let previousIndex = siblingInfo.previousSiblingIndex else {
          throw SectionReordererError.cannotMoveUp
        }
        swapTargetIndex = previousIndex
      case .down:
        guard let nextIndex = siblingInfo.nextSiblingIndex else {
          throw SectionReordererError.cannotMoveDown
        }
        swapTargetIndex = nextIndex
      }

      return swapSections(
        originalContent: originalContent,
        headings: headings,
        indexA: min(targetIndex, swapTargetIndex),
        indexB: max(targetIndex, swapTargetIndex)
      )
    }

    // For multi-position moves, use the general reorder path
    return reorderSiblings(
      originalContent: originalContent,
      headings: headings,
      siblingInfo: siblingInfo,
      targetPosition: targetPosition
    )
  }

  /// Moves a section to a specific position among its siblings.
  ///
  /// - Parameters:
  ///   - root: The Markdown AST root
  ///   - originalContent: The original document content (body only, no frontmatter)
  ///   - options: Options specifying which section to move and the target position
  /// - Returns: The reordered document content
  /// - Throws: `SectionReordererError` if the operation fails
  public static func moveTo(
    root: Root,
    originalContent: String,
    options: MoveToOptions
  ) throws -> String {
    guard !originalContent.isEmpty else {
      throw SectionReordererError.emptyDocument
    }

    let headings = extractHeadings(from: root.children)

    guard !headings.isEmpty else {
      throw SectionReordererError.noHeadingsInDocument
    }

    let targetIndex = try resolveTargetIndex(headings: headings, matchCriteria: options.matchCriteria)

    let siblingInfo = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: targetIndex)

    guard siblingInfo.siblingIndices.count > 1 else {
      throw SectionReordererError.noSiblings
    }

    // Convert 1-based target position to 0-based
    let zeroBasedPosition = options.targetPosition - 1

    guard zeroBasedPosition >= 0 && zeroBasedPosition < siblingInfo.siblingIndices.count else {
      throw SectionReordererError.invalidTargetPosition(
        requested: options.targetPosition,
        totalSiblings: siblingInfo.siblingIndices.count
      )
    }

    // If already at the target position, return unchanged
    if zeroBasedPosition == siblingInfo.positionAmongSiblings {
      return originalContent
    }

    // Reorder by collecting all sibling sections and rebuilding with new order
    return reorderSiblings(
      originalContent: originalContent,
      headings: headings,
      siblingInfo: siblingInfo,
      targetPosition: zeroBasedPosition
    )
  }

  // MARK: - Private Helpers

  /// Resolves the target heading index from match criteria.
  private static func resolveTargetIndex(
    headings: [Heading],
    matchCriteria: SectionExtractor.Options.MatchCriteria
  ) throws -> Int {
    switch matchCriteria {
    case .index(let index):
      guard index >= 0 && index < headings.count else {
        throw SectionReordererError.invalidTargetIndex(
          requested: index + 1,
          totalHeadings: headings.count
        )
      }
      return index

    case .name(let name, let caseSensitive):
      return try findHeadingIndex(headings: headings, name: name, caseSensitive: caseSensitive)
    }
  }

  /// Finds a heading index by name.
  private static func findHeadingIndex(
    headings: [Heading],
    name: String,
    caseSensitive: Bool
  ) throws -> Int {
    let headingTexts = headings.map { HeadingTextExtractor.extractText(from: $0) }

    let foundIndex: Int?
    if caseSensitive {
      foundIndex = headingTexts.firstIndex(of: name)
    } else {
      foundIndex = headingTexts.firstIndex { $0.lowercased() == name.lowercased() }
    }

    guard let index = foundIndex else {
      throw SectionReordererError.headingNotFound(
        name: name,
        caseSensitive: caseSensitive,
        availableHeadings: headingTexts
      )
    }

    return index
  }

  /// Swaps two sibling sections in the document.
  ///
  /// indexA must be less than indexB.
  private static func swapSections(
    originalContent: String,
    headings: [Heading],
    indexA: Int,
    indexB: Int
  ) -> String {
    let lines = originalContent.components(separatedBy: "\n")
    let documentLineCount = lines.count

    let boundaryA = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: indexA,
      documentLineCount: documentLineCount
    )

    let boundaryB = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: indexB,
      documentLineCount: documentLineCount
    )

    // Convert 1-based line ranges to 0-based array indices
    let startA = boundaryA.lineRange.lowerBound - 1
    let endA = boundaryA.lineRange.upperBound - 1
    let startB = boundaryB.lineRange.lowerBound - 1
    let endB = boundaryB.lineRange.upperBound - 1

    let sectionALines = Array(lines[startA...endA])
    let sectionBLines = Array(lines[startB...endB])

    // Content between section A and section B
    let betweenLines: [String]
    if endA + 1 < startB {
      betweenLines = Array(lines[(endA + 1)..<startB])
    } else {
      betweenLines = []
    }

    // Reconstruct: before A + B + between + A + after B
    var result: [String] = []
    if startA > 0 {
      result.append(contentsOf: lines[0..<startA])
    }
    result.append(contentsOf: sectionBLines)
    result.append(contentsOf: betweenLines)
    result.append(contentsOf: sectionALines)
    if endB + 1 < lines.count {
      result.append(contentsOf: lines[(endB + 1)...])
    }

    return result.joined(separator: "\n")
  }

  /// Reorders sibling sections by moving one to a new position.
  ///
  /// Detects boundaries for all siblings, creates the new ordering, and
  /// reconstructs the document.
  private static func reorderSiblings(
    originalContent: String,
    headings: [Heading],
    siblingInfo: SectionSiblingFinder.SiblingInfo,
    targetPosition: Int
  ) -> String {
    let lines = originalContent.components(separatedBy: "\n")
    let documentLineCount = lines.count

    // Detect boundaries for all sibling sections
    let boundaries = siblingInfo.siblingIndices.map { index in
      SectionBoundaryDetector.detect(
        headings: headings,
        targetIndex: index,
        documentLineCount: documentLineCount
      )
    }

    // Extract the lines for each sibling section
    let siblingLineSets = boundaries.map { boundary -> [String] in
      let start = boundary.lineRange.lowerBound - 1
      let end = boundary.lineRange.upperBound - 1
      return Array(lines[start...end])
    }

    // Create new ordering: remove from current position, insert at target position
    var reorderedSets = siblingLineSets
    let movedSection = reorderedSets.remove(at: siblingInfo.positionAmongSiblings)
    reorderedSets.insert(movedSection, at: targetPosition)

    // Reconstruct the document:
    // - Content before first sibling
    // - All siblings in new order (preserving gaps between them)
    // - Content after last sibling
    let firstSiblingStart = boundaries[0].lineRange.lowerBound - 1
    let lastSiblingEnd = boundaries[boundaries.count - 1].lineRange.upperBound - 1

    // Collect gaps between adjacent siblings
    var gaps: [[String]] = []
    for i in 0..<(boundaries.count - 1) {
      let gapStart = boundaries[i].lineRange.upperBound - 1 + 1
      let gapEnd = boundaries[i + 1].lineRange.lowerBound - 1 - 1
      if gapStart <= gapEnd {
        gaps.append(Array(lines[gapStart...gapEnd]))
      } else {
        gaps.append([])
      }
    }

    var result: [String] = []

    // Content before first sibling
    if firstSiblingStart > 0 {
      result.append(contentsOf: lines[0..<firstSiblingStart])
    }

    // Interleave reordered sections with preserved gaps
    for (i, sectionLines) in reorderedSets.enumerated() {
      result.append(contentsOf: sectionLines)
      if i < gaps.count {
        result.append(contentsOf: gaps[i])
      }
    }

    // Content after last sibling
    if lastSiblingEnd + 1 < lines.count {
      result.append(contentsOf: lines[(lastSiblingEnd + 1)...])
    }

    return result.joined(separator: "\n")
  }

  /// Extracts all heading elements from content nodes.
  private static func extractHeadings(from content: [Content]) -> [Heading] {
    content.compactMap { $0 as? Heading }
  }
}
