import Foundation
import TOML
import Yams

/// Errors raised while parsing or serializing format-neutral frontmatter.
public enum FrontMatterConversionError: Error, Equatable, LocalizedError {
  case invalidTOML(String)
  case unsupportedTOMLValue(path: String, value: String)
  case integerOutOfRange(String)
  case invalidYAMLValue(String)

  public var errorDescription: String? {
    switch self {
    case .invalidTOML(let message):
      "Invalid TOML frontmatter: \(message)"
    case .unsupportedTOMLValue(let path, let value):
      "TOML cannot represent \(value) at \(path)"
    case .integerOutOfRange(let value):
      "Frontmatter integer is outside the supported 64-bit range: \(value)"
    case .invalidYAMLValue(let value):
      "Unsupported YAML frontmatter value: \(value)"
    }
  }
}

/// Converts frontmatter between YAML, TOML, and shared dynamic values.
public enum FrontMatterConversion {
  public static func parse(_ source: String, format: FrontMatterFormat) throws -> FrontMatter {
    switch format {
    case .yaml:
      return try fromYAMLMapping(YAMLConversion.parse(source))
    case .toml:
      do {
        let decoder = TOMLDecoder()
        return try decoder.decode(FrontMatter.self, from: source)
      } catch {
        throw FrontMatterConversionError.invalidTOML(String(describing: error))
      }
    }
  }

  public static func serialize(_ frontMatter: FrontMatter, format: FrontMatterFormat) throws -> String {
    switch format {
    case .yaml:
      return try YAMLConversion.serialize(try toYAMLMapping(frontMatter))
    case .toml:
      try validateTOML(frontMatter)
      let encoder = TOMLEncoder()
      encoder.outputFormatting = .sortedKeys
      let data = try encoder.encode(frontMatter)
      guard let string = String(data: data, encoding: .utf8) else {
        throw FrontMatterConversionError.invalidTOML("Encoder returned non-UTF-8 data")
      }
      return string.hasSuffix("\n") ? string : string + "\n"
    }
  }

  public static func foundationValue(_ frontMatter: FrontMatter) -> [String: Any] {
    frontMatter.dictionary.mapValues(foundationValue)
  }

  public static func foundationValue(_ value: FrontMatterValue) -> Any {
    switch value {
    case .null: NSNull()
    case .boolean(let value): value
    case .integer(let value): value
    case .number(let value): value
    case .string(let value): value
    case .offsetDateTime(let value): ISO8601DateFormatter().string(from: value)
    case .localDateTime(let value): format(value)
    case .localDate(let value): format(value)
    case .localTime(let value): format(value)
    case .array(let values): values.map(foundationValue)
    case .object(let value): foundationValue(value)
    }
  }

  public static func fromFoundationValue(_ value: Any) throws -> FrontMatterValue {
    if value is NSNull { return .null }
    if let value = value as? Bool { return .boolean(value) }
    if let value = value as? Int { return .integer(Int64(value)) }
    if let value = value as? Int64 { return .integer(value) }
    if let value = value as? Double { return .number(value) }
    if let value = value as? Float { return .number(Double(value)) }
    if let value = value as? String { return .string(value) }
    if let value = value as? Date { return .offsetDateTime(value) }
    if let values = value as? [Any] {
      return .array(try values.map(fromFoundationValue))
    }
    if let values = value as? [String: Any] {
      var result = FrontMatter()
      for (key, value) in values {
        result[key] = try fromFoundationValue(value)
      }
      return .object(result)
    }
    throw FrontMatterConversionError.unsupportedTOMLValue(
      path: "value",
      value: String(describing: type(of: value))
    )
  }

  /// Serializes an arbitrary structured value as a TOML document.
  /// Non-object roots use the stable `value` envelope required by TOML.
  public static func serializeTOMLValue(_ value: Any) throws -> String {
    let converted = try fromFoundationValue(value)
    let document: FrontMatter
    if case .object(let object) = converted {
      document = object
    } else {
      document = FrontMatter(["value": converted])
    }
    return try serialize(document, format: .toml)
  }

  public static func fromYAMLMapping(_ mapping: Yams.Node.Mapping) throws -> FrontMatter {
    var result = FrontMatter()
    for (keyNode, valueNode) in mapping {
      guard let key = keyNode.string else {
        throw YAMLConversionError.nonStringKey(String(describing: keyNode))
      }
      result[key] = try fromYAMLNode(valueNode)
    }
    return result
  }

  public static func toYAMLMapping(_ frontMatter: FrontMatter) throws -> Yams.Node.Mapping {
    Yams.Node.Mapping(try frontMatter.map { entry in
      (.scalar(.init(entry.key)), try toYAMLNode(entry.value))
    })
  }

  private static func fromYAMLNode(_ node: Yams.Node) throws -> FrontMatterValue {
    if let mapping = node.mapping { return .object(try fromYAMLMapping(mapping)) }
    if let sequence = node.sequence { return .array(try sequence.map(fromYAMLNode)) }
    if node.tag == Tag(.null) { return .null }
    if let value = node.bool { return .boolean(value) }
    if let value = node.int { return .integer(Int64(value)) }
    if let value = node.float { return .number(value) }
    if let value = node.string { return .string(value) }
    throw FrontMatterConversionError.invalidYAMLValue(String(describing: node))
  }

  private static func toYAMLNode(_ value: FrontMatterValue) throws -> Yams.Node {
    switch value {
    case .null: .scalar(.init("", Tag(.null)))
    case .boolean(let value): .scalar(.init(value ? "true" : "false"))
    case .integer(let value): .scalar(.init(String(value)))
    case .number(let value): .scalar(.init(String(value)))
    case .string(let value): .scalar(.init(value))
    case .offsetDateTime(let value): .scalar(.init(ISO8601DateFormatter().string(from: value)))
    case .localDateTime(let value): .scalar(.init(format(value)))
    case .localDate(let value): .scalar(.init(format(value)))
    case .localTime(let value): .scalar(.init(format(value)))
    case .array(let values): .sequence(.init(try values.map(toYAMLNode)))
    case .object(let value): .mapping(try toYAMLMapping(value))
    }
  }

  private static func validateTOML(_ frontMatter: FrontMatter) throws {
    for (key, value) in frontMatter {
      try validateTOML(value, path: key)
    }
  }

  private static func validateTOML(_ value: FrontMatterValue, path: String) throws {
    switch value {
    case .null:
      throw FrontMatterConversionError.unsupportedTOMLValue(path: path, value: "null")
    case .array(let values):
      for (index, value) in values.enumerated() {
        try validateTOML(value, path: "\(path)[\(index)]")
      }
    case .object(let object):
      for (key, value) in object {
        try validateTOML(value, path: "\(path).\(key)")
      }
    default:
      break
    }
  }

  private static func format(_ value: LocalDateTime) -> String {
    var result = String(
      format: "%04d-%02d-%02dT%02d:%02d:%02d",
      value.year, value.month, value.day, value.hour, value.minute, value.second
    )
    if value.nanosecond > 0 { result += fractionalSeconds(value.nanosecond) }
    return result
  }

  private static func format(_ value: LocalDate) -> String {
    String(format: "%04d-%02d-%02d", value.year, value.month, value.day)
  }

  private static func format(_ value: LocalTime) -> String {
    var result = String(format: "%02d:%02d:%02d", value.hour, value.minute, value.second)
    if value.nanosecond > 0 { result += fractionalSeconds(value.nanosecond) }
    return result
  }

  private static func fractionalSeconds(_ nanosecond: Int) -> String {
    let digits = String(format: "%09d", nanosecond)
      .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    return ".\(digits)"
  }
}
