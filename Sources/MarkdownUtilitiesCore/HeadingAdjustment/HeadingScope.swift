import MarkdownSyntax

/// Identifies a heading and its children in a document hierarchy.
///
/// A heading's children are all subsequent headings with a greater depth (more nested)
/// until we encounter a heading with depth <= the target heading's depth (sibling or parent).
struct HeadingScope: Equatable, Sendable {
  /// Index of the target heading in the headings array
  let targetIndex: Int

  /// Depth of the target heading
  let targetDepth: Int

  /// Indices of all child headings that should be adjusted along with the target
  let childIndices: [Int]

  /// Identifies the scope of headings affected by an adjustment operation.
  ///
  /// - Parameters:
  ///   - headings: Array of all headings in the document
  ///   - targetIndex: Index of the heading to adjust
  /// - Returns: A HeadingScope containing the target and its children
  ///
  /// # Algorithm
  /// Children are identified as all headings after the target with depth > target.depth,
  /// stopping when we encounter a heading with depth <= target.depth (new section boundary).
  ///
  /// # Example
  /// ```
  /// # H1          <- target (index 0, depth 1)
  /// ## H2         <- child (depth 2 > 1)
  /// ### H3        <- child (depth 3 > 1)
  /// ## H2         <- child (depth 2 > 1)
  /// # H1          <- STOP (depth 1 <= 1, sibling section)
  /// ```
  static func identify(headings: [Heading], targetIndex: Int) -> HeadingScope {
    let target = headings[targetIndex]
    let targetLevel = target.depth.rawValue

    var childIndices: [Int] = []

    // Scan all headings after the target
    for index in (targetIndex + 1)..<headings.count {
      let heading = headings[index]
      let headingLevel = heading.depth.rawValue

      // Stop when we encounter a heading at the same or higher level (sibling or parent)
      if headingLevel <= targetLevel {
        break
      }

      // This heading is a child (deeper nesting)
      childIndices.append(index)
    }

    return HeadingScope(
      targetIndex: targetIndex,
      targetDepth: targetLevel,
      childIndices: childIndices
    )
  }
}
