//
//  SectionReordererError.swift
//  MarkdownUtilities
//

import Foundation

/// Errors that can occur during section reordering.
public enum SectionReordererError: Error, Equatable, Sendable {
  /// The section is already the first sibling and cannot be moved up.
  case cannotMoveUp

  /// The section is already the last sibling and cannot be moved down.
  case cannotMoveDown

  /// The section has no siblings to swap with.
  case noSiblings

  /// The target position is invalid for this set of siblings.
  ///
  /// - Parameters:
  ///   - requested: The requested position (1-based)
  ///   - totalSiblings: The total number of siblings
  case invalidTargetPosition(requested: Int, totalSiblings: Int)

  /// The requested heading index is invalid.
  ///
  /// - Parameters:
  ///   - requested: The index that was requested (1-based)
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

extension SectionReordererError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .cannotMoveUp:
      return "Cannot move section up: it is already the first sibling."
    case .cannotMoveDown:
      return "Cannot move section down: it is already the last sibling."
    case .noSiblings:
      return "Cannot reorder section: it has no siblings at the same level."
    case .invalidTargetPosition(let requested, let totalSiblings):
      return "Invalid target position \(requested). There are \(totalSiblings) sibling(s). Use 1-based positioning."
    case .invalidTargetIndex(let requested, let totalHeadings):
      return "Invalid heading index \(requested). Document has \(totalHeadings) heading(s). Use 1-based indexing (1 = first heading)."
    case .noHeadingsInDocument:
      return "Cannot reorder section: document contains no headings."
    case .emptyDocument:
      return "Cannot reorder section: document is empty."
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
