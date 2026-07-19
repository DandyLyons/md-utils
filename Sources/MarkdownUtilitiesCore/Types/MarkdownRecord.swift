import Foundation

/// Stable identity associated with a Markdown record.
public struct MarkdownRecordIdentity: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

/// Revision or content-hash value associated with a Markdown record.
public struct MarkdownRecordRevision: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

/// A collection-relative logical path that does not require a filesystem.
public struct MarkdownRecordPath: Codable, Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) throws {
    let normalized = rawValue.hasPrefix("./") ? String(rawValue.dropFirst(2)) : rawValue
    guard normalized.isEmpty == false else {
      throw MarkdownRecordPathError.empty
    }
    guard normalized.hasPrefix("/") == false else {
      throw MarkdownRecordPathError.absolute(rawValue)
    }
    guard normalized.hasSuffix("/") == false else {
      throw MarkdownRecordPathError.directory(rawValue)
    }
    guard normalized.contains("\\") == false else {
      throw MarkdownRecordPathError.invalidSeparator(rawValue)
    }
    let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." }) else {
      throw MarkdownRecordPathError.invalidComponent(rawValue)
    }
    self.rawValue = normalized
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// Returns whether this logical path matches the supplied portable glob.
  public func matches(glob: String) -> Bool {
    MarkdownGlob.matches(rawValue, pattern: glob)
  }
}

/// Errors produced while normalizing a logical record path.
public enum MarkdownRecordPathError: Error, Equatable, LocalizedError {
  case empty
  case absolute(String)
  case directory(String)
  case invalidSeparator(String)
  case invalidComponent(String)

  public var errorDescription: String? {
    switch self {
    case .empty:
      return "A Markdown record path cannot be empty"
    case .absolute(let path):
      return "A Markdown record path must be collection-relative: \(path)"
    case .directory(let path):
      return "A Markdown record path must identify a record, not a directory: \(path)"
    case .invalidSeparator(let path):
      return "A Markdown record path must use forward slashes: \(path)"
    case .invalidComponent(let path):
      return "A Markdown record path contains an invalid component: \(path)"
    }
  }
}

/// A type claim supplied by record content or an external persistence adapter.
public struct MarkdownTypeHint: Codable, Equatable, Hashable, Sendable {
  public var name: String
  public var version: String?

  public init(name: String, version: String? = nil) {
    self.name = name
    self.version = version
  }
}

/// External information about where or how a Markdown record is held.
public struct MarkdownRecordContext: Codable, Equatable, Sendable {
  public var path: MarkdownRecordPath?
  public var storage: JSONValue?
  public var typeHints: [MarkdownTypeHint]
  public var attributes: [String: JSONValue]

  public init(
    path: MarkdownRecordPath? = nil,
    storage: JSONValue? = nil,
    typeHints: [MarkdownTypeHint] = [],
    attributes: [String: JSONValue] = [:]
  ) {
    self.path = path
    self.storage = storage
    self.typeHints = typeHints
    self.attributes = attributes
  }
}

/// A canonical, addressable Markdown resource and its external context.
public struct MarkdownRecord: Codable, Equatable, Sendable {
  public var identity: MarkdownRecordIdentity?
  public var content: String
  public var context: MarkdownRecordContext
  public var revision: MarkdownRecordRevision?

  public init(
    identity: MarkdownRecordIdentity? = nil,
    content: String,
    context: MarkdownRecordContext = MarkdownRecordContext(),
    revision: MarkdownRecordRevision? = nil
  ) {
    self.identity = identity
    self.content = content
    self.context = context
    self.revision = revision
  }
}

private enum MarkdownGlob {
  static func matches(_ value: String, pattern: String) -> Bool {
    let value = Array(value)
    let pattern = Array(pattern)
    var memo: [Index: Bool] = [:]

    func evaluate(_ valueIndex: Int, _ patternIndex: Int) -> Bool {
      let index = Index(value: valueIndex, pattern: patternIndex)
      if let cached = memo[index] {
        return cached
      }

      let result: Bool
      if patternIndex == pattern.count {
        result = valueIndex == value.count
      } else if pattern[patternIndex] == "*" {
        let isDoubleStar = patternIndex + 1 < pattern.count && pattern[patternIndex + 1] == "*"
        if isDoubleStar {
          let followedBySlash = patternIndex + 2 < pattern.count && pattern[patternIndex + 2] == "/"
          if followedBySlash {
            result = evaluate(valueIndex, patternIndex + 3)
              || (valueIndex < value.count && evaluate(valueIndex + 1, patternIndex))
          } else {
            result = evaluate(valueIndex, patternIndex + 2)
              || (valueIndex < value.count && evaluate(valueIndex + 1, patternIndex))
          }
        } else {
          result = evaluate(valueIndex, patternIndex + 1)
            || (valueIndex < value.count && value[valueIndex] != "/" && evaluate(valueIndex + 1, patternIndex))
        }
      } else if pattern[patternIndex] == "?" {
        result = valueIndex < value.count && value[valueIndex] != "/" && evaluate(valueIndex + 1, patternIndex + 1)
      } else {
        result = valueIndex < value.count
          && value[valueIndex] == pattern[patternIndex]
          && evaluate(valueIndex + 1, patternIndex + 1)
      }

      memo[index] = result
      return result
    }

    return evaluate(0, 0)
  }

  private struct Index: Hashable {
    var value: Int
    var pattern: Int
  }
}
