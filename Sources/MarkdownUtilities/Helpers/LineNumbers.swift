//
//  LineNumbers.swift
//  MarkdownUtilities
//
//  Line number utilities for string manipulation
//

import Foundation

extension StringProtocol {
  /// Calculates the 1-based line number for a given `String.Index` within this string.
  /// This method can be called on `String` or `Substring` (as both conform to `StringProtocol`).
  /// - Parameter index: The index within the string for which to determine the line number.
  /// - Returns: The 1-based line number where the given index is located.
  public func lineNumber(for index: String.Index) -> Int {
    var lineNumber = 1
    var currentIndex = self.startIndex
    while currentIndex < index {
      if self[currentIndex] == "\n" {
        lineNumber += 1
      }
      currentIndex = self.index(after: currentIndex)
    }
    return lineNumber
  }
}

extension Substring {
  /// Calculates the 1-based starting and ending line numbers for this `Substring`,
  /// relative to its original full `String`.
  /// - Returns: A `ClosedRange<Int>` representing the inclusive range of line numbers.
  public var lineRange: ClosedRange<Int> {
    // We use 'base' as the context
    // to count line numbers from its beginning up to our Substring's indices.
    // The Substring's indices are valid within its 'base'.

    // Determine the start line number using the base string
    let startLine = self.base.lineNumber(for: self.startIndex)

    // The endIndex of a Substring points *after* its last character.
    // To get the line number of the *last character* of the substring,
    // we need to get the index of the character *before* endIndex.
    let lastCharIndex = if self.isEmpty {
      self.startIndex
    } else {
      self.index(before: self.endIndex)
    }
    let endLine = self.base.lineNumber(for: lastCharIndex)

    // Ensure valid range (handle edge cases)
    guard startLine <= endLine else {
      fatalError("lineRange internal error: startLine (\(startLine)) > endLine (\(endLine)) for substring '\(String(self))' at indices \(self.startIndex)..<\(self.endIndex) in base string of length \(self.base.count)")
    }
    return startLine...endLine
  }

  /// The 1-based line number for the start of this `Substring` within its original full `String`.
  public var startingLineNumber: Int {
    return self.lineRange.lowerBound
  }

  /// The 1-based line number for the end of this `Substring` within its original full `String`.
  public var endingLineNumber: Int {
    return self.lineRange.upperBound
  }
}

extension String {
  /// Extracts a substring corresponding to the specified 1-based line number range.
  ///
  /// If the ending line number exceeds the total number of lines in the string,
  /// the substring will include all lines up to the end of the string.
  ///
  /// - Parameter lines: A closed range of 1-based line numbers to extract where the lowerbound represents the starting line number and the upperbound represents the ending line number (within the original string).
  /// - Returns: A `Substring` containing the lines in the specified range, or `nil` if the range is invalid or exceeds the string bounds.
  public func substring(lines: ClosedRange<Int>) -> Substring? {
    guard lines.lowerBound >= 1, lines.upperBound >= lines.lowerBound else {
      return nil // Invalid range
    }

    var currentLine = 1
    var startIndex: String.Index? = nil
    var endIndex: String.Index? = nil

    for index in self.indices {
      if currentLine == lines.lowerBound && startIndex == nil {
        startIndex = index
      }
      if self[index] == "\n" {
        currentLine += 1
        if currentLine > lines.upperBound {
          endIndex = index
          break
        }
      }
    }

    // If we reached the end of the string and haven't set endIndex yet,
    // it means we want to include until the end of the string.
    if endIndex == nil && currentLine <= lines.upperBound {
      endIndex = self.endIndex
    }

    if let start = startIndex, let end = endIndex {
      return self[start..<end]
    } else {
      return nil // Range exceeds string bounds
    }
  }
}
