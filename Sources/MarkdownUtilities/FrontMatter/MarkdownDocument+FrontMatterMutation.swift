import Foundation
import Yams

extension MarkdownDocument {
  /// Get value for key from frontmatter
  ///
  /// - Parameter key: The frontmatter key to retrieve
  /// - Returns: The Yams.Node value if the key exists, nil otherwise
  public func getValue(forKey key: String) -> Yams.Node? {
    return frontMatter[key]
  }

  /// Set string value for key in frontmatter
  ///
  /// This method converts the provided string value to a YAML scalar node
  /// and assigns it to the specified key in the frontmatter mapping.
  ///
  /// - Parameters:
  ///   - value: The string value to set
  ///   - key: The frontmatter key
  public mutating func setValue(_ value: String, forKey key: String) {
    frontMatter[key] = Yams.Node.scalar(.init(value))
  }

  /// Check if key exists in frontmatter
  ///
  /// - Parameter key: The frontmatter key to check
  /// - Returns: true if the key exists in frontmatter, false otherwise
  public func hasKey(_ key: String) -> Bool {
    return frontMatter[key] != nil
  }

  /// Remove key from frontmatter
  ///
  /// This operation is idempotent - removing a non-existent key is a no-op.
  ///
  /// - Parameter key: The frontmatter key to remove
  public mutating func removeValue(forKey key: String) {
    frontMatter[key] = nil
  }

  /// Rename a key in frontmatter
  ///
  /// Renames an existing frontmatter key to a new name, preserving the value.
  /// If the old key doesn't exist, throws an error.
  /// If the new key already exists, throws an error to avoid overwriting.
  ///
  /// - Parameters:
  ///   - oldKey: The current key name to rename
  ///   - newKey: The new key name
  /// - Throws: `RenameKeyError.oldKeyNotFound` if oldKey doesn't exist,
  ///           `RenameKeyError.newKeyAlreadyExists` if newKey already exists
  public mutating func renameKey(from oldKey: String, to newKey: String) throws {
    enum RenameKeyError: Error, LocalizedError {
      case oldKeyNotFound
      case newKeyAlreadyExists

      var errorDescription: String? {
        switch self {
        case .oldKeyNotFound:
          return "Old key not found in frontmatter"
        case .newKeyAlreadyExists:
          return "New key already exists in frontmatter"
        }
      }
    }

    guard let value = getValue(forKey: oldKey) else {
      throw RenameKeyError.oldKeyNotFound
    }
    guard !hasKey(newKey) else {
      throw RenameKeyError.newKeyAlreadyExists
    }
    removeValue(forKey: oldKey)
    frontMatter[newKey] = value
  }

  /// Sort keys in frontmatter
  ///
  /// Sorts the frontmatter keys alphabetically or by key length.
  /// The sorting can be reversed using the `reverse` parameter.
  ///
  /// - Parameters:
  ///   - method: The sorting method to use (alphabetical or by length)
  ///   - reverse: Whether to reverse the sorting order (default: false)
  public mutating func sortKeys(by method: SortMethod = .alphabetical, reverse: Bool = false) {
    let sorted: [(Yams.Node, Yams.Node)]

    switch method {
    case .alphabetical:
      sorted = frontMatter.sorted { lhs, rhs in
        guard let lhsKey = lhs.key.string, let rhsKey = rhs.key.string else {
          return false
        }
        return reverse ? lhsKey > rhsKey : lhsKey < rhsKey
      }
    case .length:
      sorted = frontMatter.sorted { lhs, rhs in
        guard let lhsKey = lhs.key.string, let rhsKey = rhs.key.string else {
          return false
        }
        return reverse ? lhsKey.count > rhsKey.count : lhsKey.count < rhsKey.count
      }
    }

    frontMatter = Yams.Node.Mapping(sorted)
  }

  /// Sorting method for frontmatter keys
  public enum SortMethod: String, Sendable {
    /// Sort keys alphabetically
    case alphabetical
    /// Sort keys by length
    case length
  }
}
