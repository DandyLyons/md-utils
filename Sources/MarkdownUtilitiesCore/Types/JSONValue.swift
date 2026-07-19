import CoreFoundation
import Foundation

/// A portable, sendable representation of a JSON value.
public enum JSONValue: Equatable, Sendable {
  case null
  case boolean(Bool)
  case integer(Int)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  /// Creates a JSON value from values produced by `JSONSerialization` or Yams.
  public init(any value: Any) throws {
    if value is NSNull {
      self = .null
    } else if let value = value as? Bool {
      self = .boolean(value)
    } else if let value = value as? Int {
      self = .integer(value)
    } else if let value = value as? NSNumber {
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        self = .boolean(value.boolValue)
      } else if value.doubleValue.rounded() == value.doubleValue,
                value.doubleValue >= Double(Int.min),
                value.doubleValue <= Double(Int.max) {
        self = .integer(value.intValue)
      } else {
        self = .number(value.doubleValue)
      }
    } else if let value = value as? Double {
      self = .number(value)
    } else if let value = value as? String {
      self = .string(value)
    } else if let value = value as? [Any] {
      self = .array(try value.map { try JSONValue(any: $0) })
    } else if let value = value as? [String: Any] {
      self = .object(try value.mapValues { try JSONValue(any: $0) })
    } else {
      throw JSONValueError.unsupportedValue(String(describing: type(of: value)))
    }
  }

  /// Returns a Foundation representation suitable for JSON Schema validation.
  public var foundationValue: Any {
    switch self {
    case .null:
      return NSNull()
    case .boolean(let value):
      return value
    case .integer(let value):
      return value
    case .number(let value):
      return value
    case .string(let value):
      return value
    case .array(let values):
      return values.map(\.foundationValue)
    case .object(let values):
      return values.mapValues(\.foundationValue)
    }
  }

  /// The object value, when this value is an object.
  public var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  /// The string value, when this value is a string.
  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }
}

extension JSONValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .boolean(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }
}

/// Errors produced while converting dynamic values to ``JSONValue``.
public enum JSONValueError: Error, Equatable, LocalizedError {
  case unsupportedValue(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedValue(let type):
      return "Unsupported JSON value of type \(type)"
    }
  }
}
