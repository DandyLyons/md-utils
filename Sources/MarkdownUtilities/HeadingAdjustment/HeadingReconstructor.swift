import MarkdownSyntax
import Foundation

/// Reconstructs markdown content with adjusted heading levels.
enum HeadingReconstructor {
  /// Rebuilds markdown content with adjusted heading levels.
  ///
  /// - Parameters:
  ///   - root: The original Markdown AST
  ///   - adjustments: Map of heading indices to their new depths
  /// - Returns: Reconstructed markdown content as a string
  ///
  /// # Strategy
  /// Uses a line-based approach:
  /// 1. Split original content into lines
  /// 2. Extract all headings from AST with their positions
  /// 3. For each heading that needs adjustment, find its line and replace the heading marker
  /// 4. Rejoin lines into final content
  static func reconstruct(
    root: Root,
    originalContent: String,
    adjustments: [Int: Heading.Depth]
  ) async throws -> String {
    // If no adjustments needed, return original
    guard !adjustments.isEmpty else {
      return originalContent
    }

    // Split content into lines
    var lines = originalContent.components(separatedBy: .newlines)

    // Extract all headings from the AST
    let headings = extractHeadings(from: root.children)

    // Process adjustments (in reverse order to preserve line numbers)
    let sortedIndices = adjustments.keys.sorted(by: >)

    for headingIndex in sortedIndices {
      guard let newDepth = adjustments[headingIndex],
            headingIndex < headings.count else {
        continue
      }

      let heading = headings[headingIndex]

      // Get the line number (position is 1-indexed)
      let position = heading.position
      guard position.start.line >= 1,
            position.start.line - 1 < lines.count else {
        continue
      }

      let lineIndex = position.start.line - 1
      let line = lines[lineIndex]

      // Replace the heading marker
      let adjustedLine = replaceHeadingMarker(in: line, with: newDepth)
      lines[lineIndex] = adjustedLine
    }

    // Rejoin lines
    return lines.joined(separator: "\n")
  }

  /// Extracts all heading elements from content nodes.
  private static func extractHeadings(from content: [Content]) -> [Heading] {
    content.compactMap { $0 as? Heading }
  }

  /// Replaces the heading marker in a line with a new depth.
  ///
  /// - Parameters:
  ///   - line: The line containing a heading
  ///   - depth: The new heading depth
  /// - Returns: The line with the heading marker replaced
  ///
  /// # Example
  /// ```
  /// "## Old Heading" -> "### Old Heading"  (depth .h3)
  /// ```
  private static func replaceHeadingMarker(in line: String, with depth: Heading.Depth) -> String {
    // Count leading whitespace
    let leadingWhitespace = line.prefix(while: { $0.isWhitespace })

    // Remove leading whitespace
    let trimmedLine = line.drop(while: { $0.isWhitespace })

    // Remove existing heading markers
    let withoutMarker = trimmedLine.drop(while: { $0 == "#" })

    // Remove space after marker (if present)
    let content = withoutMarker.drop(while: { $0 == " " })

    // Build new heading marker
    let newMarker = String(repeating: "#", count: depth.rawValue)

    // Reconstruct the line
    return "\(leadingWhitespace)\(newMarker) \(content)"
  }
}
