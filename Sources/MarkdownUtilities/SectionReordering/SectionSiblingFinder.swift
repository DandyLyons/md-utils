//
//  SectionSiblingFinder.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// Finds sibling sections for a given heading in a Markdown document.
///
/// Siblings are headings at the same depth level under the same parent.
/// For example, in a document with `# A`, `## A.1`, `## A.2`, `# B`,
/// headings `# A` and `# B` are siblings, and `## A.1` and `## A.2` are siblings.
enum SectionSiblingFinder {
  /// Information about a heading's sibling relationships.
  struct SiblingInfo: Equatable, Sendable {
    /// The 0-based index of the target heading in the headings array.
    let targetIndex: Int

    /// The 0-based indices of all sibling headings (including the target) in order.
    let siblingIndices: [Int]

    /// The position of the target among its siblings (0-based).
    let positionAmongSiblings: Int

    /// The index of the previous sibling heading, or nil if the target is the first sibling.
    var previousSiblingIndex: Int? {
      guard positionAmongSiblings > 0 else { return nil }
      return siblingIndices[positionAmongSiblings - 1]
    }

    /// The index of the next sibling heading, or nil if the target is the last sibling.
    var nextSiblingIndex: Int? {
      guard positionAmongSiblings < siblingIndices.count - 1 else { return nil }
      return siblingIndices[positionAmongSiblings + 1]
    }

    /// Whether the target can be moved up (has a previous sibling).
    var canMoveUp: Bool {
      previousSiblingIndex != nil
    }

    /// Whether the target can be moved down (has a next sibling).
    var canMoveDown: Bool {
      nextSiblingIndex != nil
    }
  }

  /// Finds all sibling headings for a target heading.
  ///
  /// Siblings are defined as headings at the same depth level that share the same parent scope.
  /// For top-level headings (nothing with a smaller depth before them), all same-depth headings
  /// at the top level are siblings.
  ///
  /// - Parameters:
  ///   - headings: All headings in the document
  ///   - targetIndex: The 0-based index of the target heading
  /// - Returns: SiblingInfo describing the target's sibling relationships
  static func findSiblings(
    headings: [Heading],
    targetIndex: Int
  ) -> SiblingInfo {
    let targetDepth = headings[targetIndex].depth.rawValue

    // Find the parent boundary: scan backward to find a heading with depth < target
    let parentBoundaryStart = findParentBoundaryStart(
      headings: headings,
      targetIndex: targetIndex,
      targetDepth: targetDepth
    )

    // Find the parent boundary end: scan forward from parent to find end of parent scope
    let parentBoundaryEnd = findParentBoundaryEnd(
      headings: headings,
      startIndex: parentBoundaryStart,
      targetDepth: targetDepth
    )

    // Collect all headings at the target depth within the parent boundary
    var siblingIndices: [Int] = []
    var positionAmongSiblings = 0

    for index in parentBoundaryStart..<parentBoundaryEnd {
      let heading = headings[index]
      if heading.depth.rawValue == targetDepth {
        if index == targetIndex {
          positionAmongSiblings = siblingIndices.count
        }
        siblingIndices.append(index)
      }
    }

    return SiblingInfo(
      targetIndex: targetIndex,
      siblingIndices: siblingIndices,
      positionAmongSiblings: positionAmongSiblings
    )
  }

  /// Finds the start index for scanning siblings.
  ///
  /// Scans backward from the target to find the first heading with depth < targetDepth (parent),
  /// then returns the index after that parent. If no parent is found, returns 0 (document start).
  private static func findParentBoundaryStart(
    headings: [Heading],
    targetIndex: Int,
    targetDepth: Int
  ) -> Int {
    for index in stride(from: targetIndex - 1, through: 0, by: -1) {
      if headings[index].depth.rawValue < targetDepth {
        return index + 1
      }
    }
    return 0
  }

  /// Finds the end index (exclusive) for scanning siblings.
  ///
  /// Scans forward from startIndex to find the next heading with depth < targetDepth (parent's sibling),
  /// or returns headings.count if no such heading exists.
  private static func findParentBoundaryEnd(
    headings: [Heading],
    startIndex: Int,
    targetDepth: Int
  ) -> Int {
    for index in startIndex..<headings.count {
      if headings[index].depth.rawValue < targetDepth {
        return index
      }
    }
    return headings.count
  }
}
