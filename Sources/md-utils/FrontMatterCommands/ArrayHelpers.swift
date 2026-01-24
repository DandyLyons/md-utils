//
//  ArrayHelpers.swift
//  md-utils
//
//  Shared utilities for array manipulation commands
//

import Foundation
import MarkdownUtilities
import PathKit
import Yams

/// Shared utilities for array manipulation commands
enum ArrayHelpers {

  /// Validates that a key exists and contains an array/sequence value
  /// - Parameters:
  ///   - key: The front matter key to validate
  ///   - doc: The MarkdownDocument to check
  ///   - path: The file path (for error messages)
  /// - Returns: The Yams.Node.Sequence if valid
  /// - Throws: ArrayError if key doesn't exist, can't be retrieved, or is not an array
  static func validateArrayKey(
    _ key: String,
    in doc: MarkdownDocument,
    path: Path
  ) throws -> Yams.Node.Sequence {
    guard doc.hasKey(key) else {
      throw ArrayError.keyNotFound(key: key, path: path.string)
    }

    guard let node = doc.getValue(forKey: key) else {
      throw ArrayError.cannotRetrieveValue(key: key, path: path.string)
    }

    guard case .sequence(let sequence) = node else {
      throw ArrayError.notAnArray(key: key, path: path.string)
    }

    return sequence
  }

  /// Gets the array for a key, creating it if it doesn't exist
  /// - Parameters:
  ///   - key: The front matter key
  ///   - doc: The MarkdownDocument to check
  ///   - path: The file path (for error messages)
  /// - Returns: The Yams.Node.Sequence (empty if key doesn't exist)
  /// - Throws: ArrayError if key exists but is not an array
  static func getOrCreateArrayKey(
    _ key: String,
    in doc: MarkdownDocument,
    path: Path
  ) throws -> Yams.Node.Sequence {
    // If key doesn't exist, return empty sequence
    guard doc.hasKey(key) else {
      return Yams.Node.Sequence()
    }

    guard let node = doc.getValue(forKey: key) else {
      throw ArrayError.cannotRetrieveValue(key: key, path: path.string)
    }

    // If key exists but is not an array, throw error
    guard case .sequence(let sequence) = node else {
      throw ArrayError.notAnArray(key: key, path: path.string)
    }

    return sequence
  }

  /// Checks if a value exists in a sequence
  /// - Parameters:
  ///   - searchValue: The value to search for
  ///   - sequence: The Yams.Node.Sequence to search in
  ///   - caseInsensitive: Whether to perform case-insensitive comparison
  /// - Returns: True if the value is found, false otherwise
  static func containsValue(
    _ searchValue: String,
    in sequence: Yams.Node.Sequence,
    caseInsensitive: Bool
  ) -> Bool {
    let compareValue = caseInsensitive ? searchValue.lowercased() : searchValue

    for i in 0..<sequence.count {
      let element = sequence[i]

      // Only compare scalar (string) values
      guard case .scalar(let scalar) = element else {
        continue
      }

      let elementString = scalar.string
      let compareElement = caseInsensitive ? elementString.lowercased() : elementString

      if compareElement == compareValue {
        return true
      }
    }

    return false
  }

  /// Appends a value to a sequence
  /// - Parameters:
  ///   - value: The value to append
  ///   - sequence: The sequence to append to
  /// - Returns: A new sequence with the value appended
  static func append(
    value: String,
    to sequence: Yams.Node.Sequence
  ) -> Yams.Node.Sequence {
    var newSequence = sequence
    newSequence.append(.scalar(.init(value)))
    return newSequence
  }

  /// Prepends a value to a sequence
  /// - Parameters:
  ///   - value: The value to prepend
  ///   - sequence: The sequence to prepend to
  /// - Returns: A new sequence with the value prepended
  static func prepend(
    value: String,
    to sequence: Yams.Node.Sequence
  ) -> Yams.Node.Sequence {
    var newSequence = sequence
    newSequence.insert(.scalar(.init(value)), at: 0)
    return newSequence
  }

  /// Removes first occurrence of value from sequence
  /// - Parameters:
  ///   - value: The value to remove
  ///   - sequence: The sequence to remove from
  ///   - caseInsensitive: Whether to perform case-insensitive comparison
  /// - Returns: A new sequence with the first occurrence removed, or nil if value not found
  static func removeFirst(
    value: String,
    from sequence: Yams.Node.Sequence,
    caseInsensitive: Bool
  ) -> Yams.Node.Sequence? {
    let compareValue = caseInsensitive ? value.lowercased() : value
    var newSequence = sequence

    for i in 0..<newSequence.count {
      let element = newSequence[i]

      // Only compare scalar (string) values
      guard case .scalar(let scalar) = element else {
        continue
      }

      let elementString = scalar.string
      let compareElement = caseInsensitive ? elementString.lowercased() : elementString

      if compareElement == compareValue {
        newSequence.remove(at: i)
        return newSequence
      }
    }

    return nil  // Value not found
  }
}

/// Custom errors for array operations
enum ArrayError: Error, LocalizedError {
  case keyNotFound(key: String, path: String)
  case cannotRetrieveValue(key: String, path: String)
  case notAnArray(key: String, path: String)
  case valueNotFound(value: String, key: String, path: String)

  var errorDescription: String? {
    switch self {
    case .keyNotFound(let key, let path):
      return "Key '\(key)' not found in \(path)"
    case .cannotRetrieveValue(let key, let path):
      return "Could not retrieve value for key '\(key)' in \(path)"
    case .notAnArray(let key, let path):
      return "Value for key '\(key)' is not an array in \(path)"
    case .valueNotFound(let value, let key, let path):
      return "Value '\(value)' not found in array '\(key)' in \(path)"
    }
  }
}
