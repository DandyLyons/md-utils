import Foundation

/// Recursive rule selection. Leaves preserve existing flat matcher semantics.
public indirect enum MarkdownRuleMatchExpression: Equatable, Sendable {
  case leaf(MarkdownRuleApplicability)
  case allOf([Self])
  case anyOf([Self])
  case oneOf([Self])
  case not(Self)

  package var leaves: [MarkdownRuleApplicability] {
    switch self {
    case .leaf(let leaf): return [leaf]
    case .allOf(let children), .anyOf(let children), .oneOf(let children): return children.flatMap(\.leaves)
    case .not(let child): return child.leaves
    }
  }

  /// Rejects invalid programmatic groups as well as malformed serialized groups.
  package func validate(source: String, location: String = "match") throws {
    switch self {
    case .leaf: return
    case .not(let child): try child.validate(source: source, location: location + ".not")
    case .allOf(let children), .anyOf(let children), .oneOf(let children):
      guard children.isEmpty == false else {
        throw MarkdownRuleFileError(source: source, location: location, message: "Composition arrays must not be empty")
      }
      for (index, child) in children.enumerated() {
        try child.validate(source: source, location: "\(location)[\(index)]")
      }
    }
  }

  /// Parses the RFC 0002 matcher without enabling a new legacy config version.
  public static func decode(_ value: JSONValue, source: String = "rule", location: String = "match") throws -> Self {
    guard case .object(let object) = value else {
      throw MarkdownRuleFileError(source: source, location: location, message: "Expected a matcher object")
    }
    let operators = Set(object.keys).intersection(["allOf", "anyOf", "oneOf", "not"])
    guard let key = operators.sorted().first else {
      do {
        return .leaf(try MarkdownRuleConfigurationDecoder.decodeMatchLeaf(object, location: location))
      } catch {
        throw MarkdownRuleFileError(source: source, location: location, message: error.localizedDescription)
      }
    }
    guard object.count == 1, let operand = object[key] else {
      throw MarkdownRuleFileError(source: source, location: location, message: "A group requires exactly one operator and no leaf fields")
    }
    if key == "not" { return .not(try decode(operand, source: source, location: location + ".not")) }
    guard case .array(let values) = operand, values.isEmpty == false else {
      throw MarkdownRuleFileError(source: source, location: location, message: "\(key) requires a nonempty array")
    }
    let children = try values.enumerated().map {
      try decode($0.element, source: source, location: "\(location).\(key)[\($0.offset)]")
    }
    switch key {
    case "allOf": return .allOf(children)
    case "anyOf": return .anyOf(children)
    default: return .oneOf(children)
    }
  }
}

/// Order-independent composition, also used for conservative path prefiltering.
package enum MarkdownRuleMatchComposition {
  package static func all(_ values: [MarkdownRuleEvidenceStatus]) -> MarkdownRuleEvidenceStatus {
    if values.contains(.notMatched) { return .notMatched }
    return values.contains(.unavailable) ? .unavailable : .matched
  }
  package static func any(_ values: [MarkdownRuleEvidenceStatus]) -> MarkdownRuleEvidenceStatus {
    if values.contains(.matched) { return .matched }
    return values.contains(.unavailable) ? .unavailable : .notMatched
  }
  package static func one(_ values: [MarkdownRuleEvidenceStatus]) -> MarkdownRuleEvidenceStatus {
    let successes = values.filter { $0 == .matched }.count
    if successes > 1 { return .notMatched }
    if values.contains(.unavailable) { return .unavailable }
    return successes == 1 ? .matched : .notMatched
  }
  package static func not(_ value: MarkdownRuleEvidenceStatus) -> MarkdownRuleEvidenceStatus {
    switch value {
    case .matched: return .notMatched
    case .notMatched: return .matched
    case .unavailable: return .unavailable
    }
  }
}
