import Foundation

/// A type-file reference or recursive conformance expression in a standalone rule.
public indirect enum MarkdownRuleTypeExpression: Equatable, Sendable {
  case reference(String)
  case allOf([Self])
  case anyOf([Self])
  case oneOf([Self])
  case not(Self)

  public var references: [String] {
    switch self {
    case .reference(let reference): return [reference]
    case .allOf(let children), .anyOf(let children), .oneOf(let children):
      return children.flatMap(\.references)
    case .not(let child): return child.references
    }
  }

  public var jsonValue: JSONValue {
    switch self {
    case .reference(let value): return .string(value)
    case .allOf(let children): return .object(["allOf": .array(children.map(\.jsonValue))])
    case .anyOf(let children): return .object(["anyOf": .array(children.map(\.jsonValue))])
    case .oneOf(let children): return .object(["oneOf": .array(children.map(\.jsonValue))])
    case .not(let child): return .object(["not": child.jsonValue])
    }
  }

  private static let suffixes = [".mdtype.json", ".mdtype.yaml", ".mdtype.yml", ".mdtype.toml"]

  public static func decode(_ value: JSONValue, source: String, location: String = "types") throws -> Self {
    if case .string(let reference) = value {
      let segments = reference.split(separator: "/", omittingEmptySubsequences: false)
      guard suffixes.contains(where: reference.lowercased().hasSuffix),
        reference.contains("\\") == false, reference.contains(":") == false,
        segments.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." }) else {
        throw MarkdownRuleFileError(source: source, location: location,
          message: "Expected a relative .mdtype.json/.yaml/.yml/.toml filename under types/")
      }
      return .reference(reference)
    }
    guard case .object(let object) = value, object.count == 1,
      let (key, operand) = object.first else {
      throw MarkdownRuleFileError(source: source, location: location,
        message: "Expected a type filename or exactly one composition operator")
    }
    if key == "not" {
      return .not(try decode(operand, source: source, location: "\(location).not"))
    }
    guard ["allOf", "anyOf", "oneOf"].contains(key),
      case .array(let values) = operand, values.isEmpty == false else {
      throw MarkdownRuleFileError(source: source, location: location,
        message: "allOf, anyOf, and oneOf require nonempty arrays")
    }
    var children: [Self] = []
    for (index, value) in values.enumerated() {
      let child = try decode(value, source: source, location: "\(location).\(key)[\(index)]")
      guard let earlier = children.firstIndex(of: child) else {
        children.append(child)
        continue
      }
      throw MarkdownRuleFileError(source: source, location: "\(location).\(key)[\(index)]",
        message: "Duplicates \(location).\(key)[\(earlier)]")
    }
    switch key {
    case "allOf": return .allOf(children)
    case "anyOf": return .anyOf(children)
    default: return .oneOf(children)
    }
  }
}

/// Validated standalone rule data. Evaluation and filesystem discovery are separate.
public struct MarkdownRuleFile: Equatable, Sendable {
  public let name: String
  public let match: JSONValue?
  public let types: MarkdownRuleTypeExpression
  public let schemaReference: String?
  public let source: String

  public static func decode(_ content: String, source: String) throws -> Self {
    do {
      let value = try JSONValue(any: JSONSerialization.jsonObject(with: Data(content.utf8)))
      guard case .object(let object) = value else {
        throw MarkdownRuleFileError(source: source, location: "$", message: "Expected one rule object")
      }
      let unknown = Set(object.keys).subtracting(["$schema", "name", "match", "types"])
      guard unknown.isEmpty else {
        throw MarkdownRuleFileError(source: source, location: "$", message: "Unknown fields: \(unknown.sorted().joined(separator: ", "))")
      }
      guard let name = object["name"]?.stringValue, name.isEmpty == false,
        name == name.trimmingCharacters(in: .whitespacesAndNewlines) else {
        throw MarkdownRuleFileError(source: source, location: "name", message: "Expected a nonempty name without surrounding whitespace")
      }
      if let schema = object["$schema"], schema.stringValue?.isEmpty != false {
        throw MarkdownRuleFileError(source: source, location: "$schema", message: "Expected a nonempty string")
      }
      guard let rawTypes = object["types"] else {
        throw MarkdownRuleFileError(source: source, location: "types", message: "A type expression is required")
      }
      if let match = object["match"] { try validateMatch(match, source: source, location: "match") }
      return Self(name: name, match: object["match"],
        types: try .decode(rawTypes, source: source), schemaReference: object["$schema"]?.stringValue,
        source: source)
    } catch let error as MarkdownRuleFileError {
      throw error
    } catch {
      throw MarkdownRuleFileError(source: source, location: "$", message: error.localizedDescription)
    }
  }

  public func encoded() throws -> String {
    var object: [String: Any] = ["name": name, "types": types.jsonValue.foundationValue]
    if let match { object["match"] = match.foundationValue }
    if let schemaReference { object["$schema"] = schemaReference }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self) + "\n"
  }

  private static func validateMatch(_ value: JSONValue, source: String, location: String) throws {
    guard case .object(let object) = value else {
      throw MarkdownRuleFileError(source: source, location: location, message: "Expected a matcher object")
    }
    let operators = Set(object.keys).intersection(["allOf", "anyOf", "oneOf", "not"])
    if let key = operators.sorted().first {
      guard object.count == 1, let operand = object[key] else {
        throw MarkdownRuleFileError(source: source, location: location, message: "A group must contain exactly one operator and no leaf fields")
      }
      if key == "not" { return try validateMatch(operand, source: source, location: "\(location).not") }
      guard case .array(let children) = operand, children.isEmpty == false else {
        throw MarkdownRuleFileError(source: source, location: location, message: "\(key) requires a nonempty array")
      }
      for (index, child) in children.enumerated() {
        try validateMatch(child, source: source, location: "\(location).\(key)[\(index)]")
      }
      return
    }
    if object.isEmpty { return }
    // Reuse versioned leaf validation; temporary defaults only satisfy the old
    // decoder's required selection/check envelope and are never persisted.
    var leaf = object.mapValues(\.foundationValue)
    if leaf["paths"] == nil || (leaf["paths"] as? [String])?.isEmpty == true {
      leaf["paths"] = ["**"]
    }
    let envelope: [String: Any] = ["configVersion": "0.2.0", "rules": [[
      "name": "rule-file-leaf", "match": leaf,
      "checks": [["type": "maxBodyWords", "max": 0]],
    ]]]
    do {
      let data = try JSONSerialization.data(withJSONObject: envelope)
      _ = try MarkdownRuleConfigurationDecoder.decode(String(decoding: data, as: UTF8.self))
    } catch {
      throw MarkdownRuleFileError(source: source, location: location, message: error.localizedDescription)
    }
  }
}

public struct MarkdownRuleFileError: Error, Equatable, Sendable, LocalizedError {
  public let source: String
  public let location: String
  public let message: String

  public init(source: String, location: String, message: String) {
    self.source = source
    self.location = location
    self.message = message
  }

  public var errorDescription: String? { "\(source): \(location): \(message)" }
}
