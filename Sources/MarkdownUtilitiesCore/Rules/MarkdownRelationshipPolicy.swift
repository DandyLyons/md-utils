import Foundation

/// An explicit type resource and local relationship name, never an inferred domain relation.
public struct MarkdownPolicyRelation: Codable, Hashable, Sendable {
  public var type: String
  public var name: String

  public init(type: String, name: String) {
    self.type = type
    self.name = name
  }

  public var jsonValue: JSONValue { .object(["type": .string(type), "name": .string(name)]) }
}

public enum MarkdownPolicyScope: String, Codable, Sendable { case selected, reachable }
public enum MarkdownCycleWitnessMode: String, Codable, Sendable { case perComponent, first }

/// The independently opted-in RFC 0004 policy envelope.
public struct MarkdownRelationshipPolicy: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case cycles([MarkdownPolicyRelation], CycleMode)
    case selfLinks([MarkdownPolicyRelation], forbid: Bool)
    case reciprocity(MarkdownPolicyRelation)
    case inverse(from: MarkdownPolicyRelation, to: MarkdownPolicyRelation)
  }
  public enum CycleMode: String, Codable, Sendable { case allowed, discouraged, forbidden }

  public var id: String
  public var scope: MarkdownPolicyScope
  public var kind: Kind
  public var severity: MarkdownDiagnosticSeverity

  public init(id: String, scope: MarkdownPolicyScope, kind: Kind, severity: MarkdownDiagnosticSeverity = .error) {
    self.id = id
    self.scope = scope
    self.kind = kind
    if case .cycles(_, let mode) = kind {
      self.severity = mode == .discouraged ? .advisory : .error
    } else { self.severity = severity }
  }

  public var relations: [MarkdownPolicyRelation] {
    switch kind {
    case .cycles(let values, _), .selfLinks(let values, _): values
    case .reciprocity(let value): [value]
    case .inverse(let from, let to): from == to ? [from] : [from, to]
    }
  }

  public var isNoOp: Bool {
    switch kind {
    case .cycles(_, .allowed), .selfLinks(_, false): true
    default: false
    }
  }

  public var jsonValue: JSONValue {
    var object: [String: JSONValue] = ["id": .string(id), "scope": .string(scope.rawValue)]
    switch kind {
    case .cycles(let values, let mode):
      object["kind"] = .string("cycles")
      object["relations"] = .array(values.map(\.jsonValue))
      object["mode"] = .string(mode.rawValue)
    case .selfLinks(let values, let forbid):
      object["kind"] = .string("selfLinks")
      object["relations"] = .array(values.map(\.jsonValue))
      object["mode"] = .string(forbid ? "forbid" : "allow")
      object["severity"] = .string(severity.rawValue)
    case .reciprocity(let value):
      object["kind"] = .string("reciprocity")
      object["relation"] = value.jsonValue
      object["severity"] = .string(severity.rawValue)
    case .inverse(let from, let to):
      object["kind"] = .string("inverse")
      object["from"] = from.jsonValue
      object["to"] = to.jsonValue
      object["severity"] = .string(severity.rawValue)
    }
    return .object(object)
  }

  package static func decode(_ value: JSONValue, source: String) throws -> [Self] {
    func invalid(_ location: String, _ message: String) -> MarkdownRuleFileError {
      .init(source: source, location: location, message: "relationship.definition.invalid: " + message)
    }
    guard case .array(let values) = value else { throw invalid("relationshipPolicies", "Expected an array") }
    var ids: Set<String> = []
    return try values.enumerated().map { index, value in
      let location = "relationshipPolicies[\(index)]"
      guard case .object(let object) = value,
        let id = object["id"]?.stringValue, !id.isEmpty,
        id == id.trimmingCharacters(in: .whitespacesAndNewlines), ids.insert(id).inserted,
        let scope = object["scope"]?.stringValue.flatMap(MarkdownPolicyScope.init(rawValue:)),
        let kind = object["kind"]?.stringValue else {
        throw invalid(location, "Expected unique nonempty id, kind and explicit scope")
      }
      func relation(_ value: JSONValue?) throws -> MarkdownPolicyRelation {
        guard case .object(let entry) = value, Set(entry.keys) == ["type", "name"],
          let type = entry["type"]?.stringValue, let name = entry["name"]?.stringValue,
          !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines) else {
          throw invalid(location, "Expected {type: resource, name: relationship}")
        }
        _ = try MarkdownRuleTypeExpression.decode(.string(type), source: source, location: location)
        return .init(type: type, name: name)
      }
      func relations() throws -> [MarkdownPolicyRelation] {
        guard case .array(let entries) = object["relations"], !entries.isEmpty else {
          throw invalid(location, "Expected nonempty relations")
        }
        let refs = try entries.map { try relation($0) }
        guard Set(refs).count == refs.count else { throw invalid(location, "Duplicate relation reference") }
        return refs
      }
      var fields: Set<String> = ["id", "kind", "scope", "severity"]
      let severity: MarkdownDiagnosticSeverity
      switch object["severity"] {
      case nil, .string("error"): severity = .error
      case .string("advisory"): severity = .advisory
      default: throw invalid(location, "Severity must be error or advisory")
      }
      let policyKind: Kind
      switch kind {
      case "cycles":
        fields.remove("severity")
        fields.formUnion(["relations", "mode"])
        guard let mode = object["mode"]?.stringValue.flatMap(CycleMode.init(rawValue:)) else {
          throw invalid(location, "Expected allowed, discouraged or forbidden cycle mode")
        }
        policyKind = .cycles(try relations(), mode)
      case "selfLinks":
        fields.formUnion(["relations", "mode"])
        guard let mode = object["mode"]?.stringValue, ["allow", "forbid"].contains(mode) else {
          throw invalid(location, "Expected allow or forbid self-link mode")
        }
        policyKind = .selfLinks(try relations(), forbid: mode == "forbid")
      case "reciprocity":
        fields.insert("relation")
        policyKind = .reciprocity(try relation(object["relation"]))
      case "inverse":
        fields.formUnion(["from", "to"])
        policyKind = .inverse(from: try relation(object["from"]), to: try relation(object["to"]))
      default: throw invalid(location, "Unknown policy kind: \(kind)")
      }
      guard Set(object.keys).isSubset(of: fields) else { throw invalid(location, "Unknown or inapplicable policy fields") }
      return Self(id: id, scope: scope, kind: policyKind, severity: severity)
    }
  }
}
