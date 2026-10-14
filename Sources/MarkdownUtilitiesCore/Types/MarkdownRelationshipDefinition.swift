import Foundation

/// A literal object key or explicit array traversal; names never imply domain semantics.
public enum MarkdownRelationshipSelector: Equatable, Sendable {
  case key(String)
  case each
}

/// An authored assertion about selected whole-value wikilinks.
public struct MarkdownRelationshipDefinition: Equatable, Sendable {
  public var select: [MarkdownRelationshipSelector]
  public var target: String
  public var minimum: Int = 0
  public var maximum: Int?
  public var forbidDuplicates = false
  public var ignoreNulls = false
  public var forbidEmbeds = false
  public var forbidAnchors = false
  public var severity: MarkdownDiagnosticSeverity = .error

  public init(select: [MarkdownRelationshipSelector], target: String) {
    self.select = select
    self.target = target
  }

  /// Canonical authored envelope shared by exports and evaluator fingerprints.
  public var jsonValue: JSONValue {
    var count: [String: JSONValue] = ["min": .integer(minimum)]
    if let maximum { count["max"] = .integer(maximum) }
    return .object([
      "select": .array(select.map { step in
        switch step { case .key(let key): .string(key); case .each: .object(["each": .boolean(true)]) }
      }),
      "target": .object(["type": .string(target)]),
      "cardinality": .object(count),
      "duplicates": .string(forbidDuplicates ? "forbid" : "allow"),
      "nulls": .string(ignoreNulls ? "ignore" : "forbid"),
      "embeds": .string(forbidEmbeds ? "forbid" : "allow"),
      "anchors": .string(forbidAnchors ? "forbid" : "allow"),
      "severity": .string(severity.rawValue),
    ])
  }

  package static func decode(_ value: JSONValue) throws -> [String: Self] {
    guard case .object(let declarations) = value else { throw invalid("relationships must be an object") }
    return try declarations.mapValues { value in
      guard case .object(let object) = value,
        Set(object.keys).isSubset(of: ["select", "target", "cardinality", "duplicates", "nulls", "embeds", "anchors", "severity"]),
        case .array(let steps) = object["select"], !steps.isEmpty,
        case .object(let target) = object["target"], target.count == 1,
        let reference = target["type"]?.stringValue else { throw invalid("invalid relationship envelope") }
      var result = Self(select: try steps.map { step in
        if case .string(let key) = step { return .key(key) }
        if step == .object(["each": .boolean(true)]) { return .each }
        throw invalid("select requires literal keys or {each: true}")
      }, target: reference)
      if let cardinality = object["cardinality"] {
        guard case .object(let count) = cardinality,
          Set(count.keys).isSubset(of: ["min", "max"]) else { throw invalid("invalid cardinality") }
        for (key, value) in count {
          guard case .integer(let number) = value, number >= 0 else { throw invalid("cardinality requires nonnegative integers") }
          if key == "min" { result.minimum = number } else { result.maximum = number }
        }
      }
      func option(_ key: String, _ values: [String], _ fallback: String) throws -> String {
        guard let value = object[key] else { return fallback }
        guard let string = value.stringValue, values.contains(string) else { throw invalid("invalid \(key)") }
        return string
      }
      result.forbidDuplicates = try option("duplicates", ["allow", "forbid"], "allow") == "forbid"
      result.ignoreNulls = try option("nulls", ["ignore", "forbid"], "forbid") == "ignore"
      result.forbidEmbeds = try option("embeds", ["allow", "forbid"], "allow") == "forbid"
      result.forbidAnchors = try option("anchors", ["allow", "forbid"], "allow") == "forbid"
      result.severity = try option("severity", ["error", "advisory"], "error") == "error" ? .error : .advisory
      try result.validate()
      return result
    }
  }

  package func validate() throws {
    guard !select.isEmpty, select.count <= 128, minimum >= 0, maximum.map({ $0 >= minimum }) ?? true,
      (try? MarkdownRecordPath(target)) != nil,
      [".mdtype.yaml", ".mdtype.yml", ".mdtype.json", ".mdtype.toml"].contains(where: target.hasSuffix) else {
      throw Self.invalid("invalid selector, cardinality or explicit target type resource: \(target)")
    }
  }

  package static func invalid(_ message: String) -> MarkdownTypeDefinitionError {
    .invalidField("relationship.definition.invalid: \(message)")
  }
}
