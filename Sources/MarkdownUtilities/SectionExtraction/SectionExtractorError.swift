//
//  SectionExtractorError.swift
//  MarkdownUtilities
//

import Foundation

/// Errors that can occur during section extraction.
public enum SectionExtractorError: Error, Equatable, Sendable {
  /// The requested heading index is invalid.
  ///
  /// - Parameters:
  ///   - requestedIndex: The index that was requested (1-based)
  ///   - totalHeadings: The total number of headings in the document
  case invalidTargetIndex(requested: Int, totalHeadings: Int)

  /// The document contains no headings.
  case noHeadingsInDocument

  /// The document is empty (no content).
  case emptyDocument

  /// The requested heading name was not found.
  ///
  /// - Parameters:
  ///   - name: The heading name that was searched for
  ///   - caseSensitive: Whether the search was case-sensitive
  ///   - availableHeadings: List of available heading texts in the document
  case headingNotFound(name: String, caseSensitive: Bool, availableHeadings: [String])
}

extension SectionExtractorError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidTargetIndex(let requested, let totalHeadings):
      return "Invalid heading index \(requested). Document has \(totalHeadings) heading(s). Use 1-based indexing (1 = first heading)."
    case .noHeadingsInDocument:
      return "Cannot extract section: document contains no headings."
    case .emptyDocument:
      return "Cannot extract section: document is empty."
    case .headingNotFound(let name, let caseSensitive, let availableHeadings):
      let sensitivity = caseSensitive ? "case-sensitive" : "case-insensitive"
      var message = "Heading '\(name)' not found (\(sensitivity))."

      if !availableHeadings.isEmpty {
        let headingsToShow = availableHeadings.prefix(10)
        let headingsList = headingsToShow.map { "  - \($0)" }.joined(separator: "\n")
        message += "\nAvailable headings:\n\(headingsList)"

        if availableHeadings.count > 10 {
          message += "\n  ... and \(availableHeadings.count - 10) more"
        }
      }

      return message
    }
  }
}
