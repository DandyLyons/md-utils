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
    }
  }
}
