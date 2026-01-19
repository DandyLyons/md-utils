//
//  SectionContent.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// Represents an extracted section from a Markdown document.
///
/// A section consists of a heading and all content nested under it until the next
/// same-level or higher heading.
public struct SectionContent: Sendable {
  /// The extracted section text (heading + all nested content).
  public let text: String

  /// The heading that starts this section.
  public let heading: Heading

  /// The line range of the section in the original document (1-based, inclusive).
  public let lineRange: ClosedRange<Int>

  /// The number of child headings contained in this section.
  public let childHeadingCount: Int

  public init(
    text: String,
    heading: Heading,
    lineRange: ClosedRange<Int>,
    childHeadingCount: Int
  ) {
    self.text = text
    self.heading = heading
    self.lineRange = lineRange
    self.childHeadingCount = childHeadingCount
  }
}
