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
}
