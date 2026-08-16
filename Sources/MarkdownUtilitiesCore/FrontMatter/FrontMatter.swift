import Foundation
import TOML
import Yams

/// The serialization format used by a Markdown frontmatter block.
public enum FrontMatterFormat: String, CaseIterable, Codable, Equatable, Sendable {
  case yaml
  case toml

  /// The complete line used to delimit this format in Markdown.
  public var delimiter: String {
    switch self {
    case .yaml: "---"
    case .toml: "+++"
    }
  }
}

/// An ordered, format-neutral frontmatter mapping.
public struct FrontMatter: Equatable, Sendable {
  private var entries: [(key: String, value: FrontMatterValue)]

  public init() {
    entries = []
  }

  public init(_ values: [String: FrontMatterValue]) {
    entries = values.map { (key: $0.key, value: $0.value) }
  }

  public init(_ entries: [(String, FrontMatterValue)]) {
    self.entries = []
    for (key, value) in entries {
      self[key] = value
    }
  }

  public var isEmpty: Bool { entries.isEmpty }
  public var count: Int { entries.count }
  public var keys: [String] { entries.map(\.key) }

  public subscript(key: String) -> FrontMatterValue? {
    get { entries.first(where: { $0.key == key })?.value }
    set {
      if let index = entries.firstIndex(where: { $0.key == key }) {
        if let newValue {
          entries[index].value = newValue
        } else {
          entries.remove(at: index)
        }
      } else if let newValue {
        entries.append((key, newValue))
      }
    }
  }

  public mutating func sort(
    by areInIncreasingOrder: ((key: String, value: FrontMatterValue), (key: String, value: FrontMatterValue)) -> Bool
  ) {
    entries.sort(by: areInIncreasingOrder)
  }

  public var dictionary: [String: FrontMatterValue] {
    Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
  }

  public static func == (lhs: FrontMatter, rhs: FrontMatter) -> Bool {
    guard lhs.entries.count == rhs.entries.count else { return false }
    return zip(lhs.entries, rhs.entries).allSatisfy { left, right in
      left.key == right.key && left.value == right.value
    }
  }
}

extension FrontMatter: Sequence {
  public func makeIterator() -> IndexingIterator<[(key: String, value: FrontMatterValue)]> {
    entries.makeIterator()
  }
}

extension FrontMatter: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: FrontMatterCodingKey.self)
    entries = try container.allKeys.map { key in
      (key.stringValue, try container.decode(FrontMatterValue.self, forKey: key))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: FrontMatterCodingKey.self)
    for (key, value) in entries {
      try container.encode(value, forKey: FrontMatterCodingKey(key))
    }
  }
}

/// A format-neutral frontmatter value, including TOML's native date/time types.
public enum FrontMatterValue: Equatable, Sendable {
  case null
  case boolean(Bool)
  case integer(Int64)
  case number(Double)
  case string(String)
  case offsetDateTime(Date)
  case localDateTime(LocalDateTime)
  case localDate(LocalDate)
  case localTime(LocalTime)
  case array([FrontMatterValue])
  case object(FrontMatter)

  /// The string payload when this value is a string.
  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  public var int: Int? {
    guard case .integer(let value) = self else { return nil }
    return Int(exactly: value)
  }

  public var float: Double? {
    switch self {
    case .number(let value): value
    case .integer(let value): Double(value)
    default: nil
    }
  }

  public var bool: Bool? {
    guard case .boolean(let value) = self else { return nil }
    return value
  }

  public var sequence: [FrontMatterValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  public var mapping: FrontMatter? {
    guard case .object(let value) = self else { return nil }
    return value
  }
}

extension FrontMatterValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode(LocalDateTime.self) {
      self = .localDateTime(value)
    } else if let value = try? container.decode(LocalDate.self) {
      self = .localDate(value)
    } else if let value = try? container.decode(LocalTime.self) {
      self = .localTime(value)
    } else if let value = try? container.decode(Date.self) {
      self = .offsetDateTime(value)
    } else if let value = try? container.decode([FrontMatterValue].self) {
      self = .array(value)
    } else if let value = try? container.decode(FrontMatter.self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported frontmatter value"
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .boolean(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .offsetDateTime(let value): try container.encode(value)
    case .localDateTime(let value): try container.encode(value)
    case .localDate(let value): try container.encode(value)
    case .localTime(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}

private struct FrontMatterCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init(_ string: String) { stringValue = string }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
