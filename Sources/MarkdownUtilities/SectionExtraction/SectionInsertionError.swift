//
//  SectionInsertionError.swift
//  MarkdownUtilities
//

import Foundation

/// Errors raised while preparing or inserting a Markdown section.
public enum SectionInsertionError: Error, Equatable, Sendable, CustomStringConvertible {
  /// A heading level outside Markdown's supported h1...h6 range was requested.
  case invalidHeadingLevel(Int)

  /// The inserted content starts with a heading that does not match the requested section name.
  case mismatchedInputHeading(actual: String, expected: String)

  /// The inserted content cannot be shifted without exceeding Markdown heading limits.
  case headingShiftOutOfRange(title: String, requestedLevel: Int)

  /// Human-readable error text.
  public var description: String {
    switch self {
    case .invalidHeadingLevel(let level):
      return "Heading level must be between 1 and 6, got \(level)."
    case .mismatchedInputHeading(let actual, let expected):
      return "Inserted content starts with heading \"\(actual)\", but --name is \"\(expected)\". Use --name \"\(actual)\", remove the heading from the input, or update the input heading to match."
    case .headingShiftOutOfRange(let title, let requestedLevel):
      return "Inserted content cannot be safely shifted because heading \"\(title)\" would become level \(requestedLevel), outside Markdown's h1...h6 range. Choose a higher-level insertion target, pass --level with a smaller value, or adjust the input headings."
    }
  }
}
