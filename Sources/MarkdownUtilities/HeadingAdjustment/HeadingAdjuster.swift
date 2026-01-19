import MarkdownSyntax

/// Adjusts heading levels in a Markdown document while preserving relative hierarchy.
public enum HeadingAdjuster {
  /// Options for heading adjustment operations.
  public struct Options: Equatable, Sendable {
    /// Index of the heading to adjust (0-based)
    public var targetIndex: Int

    /// Amount to adjust heading levels by (-1 for promote, +1 for demote)
    public var adjustment: Int

    /// Whether to adjust child headings along with the target
    public var includeChildren: Bool

    public init(targetIndex: Int, adjustment: Int, includeChildren: Bool = true) {
      self.targetIndex = targetIndex
      self.adjustment = adjustment
      self.includeChildren = includeChildren
    }
  }

  /// Result of a heading adjustment operation.
  public struct Result: Equatable, Sendable {
    /// The adjusted markdown content
    public let content: String

    /// Number of headings that were adjusted
    public let adjustedCount: Int

    /// Whether any headings were clamped at H1 or H6 boundaries
    public let hadClampedHeadings: Bool

    public init(content: String, adjustedCount: Int, hadClampedHeadings: Bool) {
      self.content = content
      self.adjustedCount = adjustedCount
      self.hadClampedHeadings = hadClampedHeadings
    }
  }

  /// Adjusts heading levels in a Markdown AST.
  ///
  /// - Parameters:
  ///   - root: The parsed Markdown AST
  ///   - originalContent: The original markdown content (for reconstruction)
  ///   - options: Adjustment options
  /// - Returns: Result containing adjusted content and metadata
  /// - Throws: `HeadingAdjusterError` if the operation cannot be performed
  public static func adjust(
    root: Root,
    originalContent: String,
    options: Options
  ) async throws -> Result {
    // Extract all headings from the document
    let headings = extractHeadings(from: root.children)

    // Validate we have headings
    guard !headings.isEmpty else {
      throw HeadingAdjusterError.noHeadingsInDocument
    }

    // Validate target index
    guard options.targetIndex >= 0 && options.targetIndex < headings.count else {
      throw HeadingAdjusterError.invalidTargetIndex(
        options.targetIndex,
        totalHeadings: headings.count
      )
    }

    // Identify the scope of headings to adjust
    let scope = HeadingScope.identify(headings: headings, targetIndex: options.targetIndex)

    // Determine which indices to adjust
    let indicesToAdjust = options.includeChildren
      ? [options.targetIndex] + scope.childIndices
      : [options.targetIndex]

    // Calculate new depths for each heading
    var adjustments: [Int: Heading.Depth] = [:]
    var hadClampedHeadings = false

    for index in indicesToAdjust {
      let heading = headings[index]
      let currentLevel = heading.depth.rawValue
      let newLevel = currentLevel + options.adjustment

      // Clamp to valid heading range [1, 6]
      let clampedLevel = min(max(newLevel, 1), 6)

      // Track if we had to clamp
      if clampedLevel != newLevel {
        hadClampedHeadings = true
      }

      adjustments[index] = Heading.Depth(rawValue: clampedLevel)!
    }

    // Reconstruct the document with adjusted headings
    let adjustedContent = try await HeadingReconstructor.reconstruct(
      root: root,
      originalContent: originalContent,
      adjustments: adjustments
    )

    return Result(
      content: adjustedContent,
      adjustedCount: adjustments.count,
      hadClampedHeadings: hadClampedHeadings
    )
  }

  /// Extracts all heading elements from an array of content nodes.
  ///
  /// - Parameter content: Array of markdown content nodes
  /// - Returns: Array of Heading nodes in document order
  private static func extractHeadings(from content: [Content]) -> [Heading] {
    content.compactMap { $0 as? Heading }
  }
}
