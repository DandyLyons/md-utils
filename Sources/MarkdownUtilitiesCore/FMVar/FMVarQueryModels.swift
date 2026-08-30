import Foundation

/// Opaque identity retained for one node in an fm-var JSONPath query argument.
///
/// Providers assign identities while projecting YAML. Evaluators preserve them when a query
/// selects the same node more than once, allowing later stages to recover source scalar spelling.
public struct FMVarQueryNodeID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  /// Provider-defined stable identity within one query argument.
  public let rawValue: String

  /// Creates an opaque node identity.
  public init(rawValue: String) { self.rawValue = rawValue }
}

/// Original YAML scalar content retained beside its projected I-JSON value.
public struct FMVarSourceScalar: Codable, Equatable, Sendable {
  /// Exact scalar content needed for later coercion and default formatting.
  public let content: String

  /// Creates retained source-scalar metadata.
  public init(content: String) { self.content = content }
}

/// One ordered member in an I-JSON object query value.
///
/// YAML projection rejects duplicate member names before constructing a valid query argument.
/// Member order is retained for source association but is not a portable JSONPath ordering
/// guarantee when a selector enumerates object members.
public struct FMVarQueryObjectMember: Codable, Equatable, Sendable {
  /// Unique JSON object member name.
  public let name: String
  /// Projected child node.
  public let node: FMVarQueryNode

  /// Creates one projected object member.
  public init(name: String, node: FMVarQueryNode) {
    self.name = name
    self.node = node
  }
}

/// I-JSON-compatible value supplied to RFC 9535 JSONPath evaluation.
///
/// Integer and floating-point bounds are validated by the YAML projection layer. Arrays and
/// objects contain identified nodes so evaluation can preserve duplicates and source association.
public indirect enum FMVarQueryValue: Codable, Equatable, Sendable {
  /// JSON null.
  case null
  /// JSON Boolean.
  case boolean(Bool)
  /// Interoperable integer in RFC 001 Rev 3's inclusive safe range.
  case integer(Int64)
  /// Finite IEEE 754 binary64 number.
  case number(Double)
  /// JSON string.
  case string(String)
  /// Ordered JSON array.
  case array([FMVarQueryNode])
  /// JSON object with unique member names.
  case object([FMVarQueryObjectMember])

  /// Broad shape used by element-specific cardinality and rendering rules.
  public var shape: FMVarValueShape {
    switch self {
    case .null: .null
    case .boolean, .integer, .number, .string: .scalar
    case .array: .sequence
    case .object: .mapping
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
    case nodes
    case members
  }

  private enum Kind: String, Codable {
    case null
    case boolean
    case integer
    case number
    case string
    case array
    case object
  }

  /// Decodes the explicit, language-neutral tagged wire representation.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .null:
      self = .null
    case .boolean:
      self = .boolean(try container.decode(Bool.self, forKey: .value))
    case .integer:
      self = .integer(try container.decode(Int64.self, forKey: .value))
    case .number:
      self = .number(try container.decode(Double.self, forKey: .value))
    case .string:
      self = .string(try container.decode(String.self, forKey: .value))
    case .array:
      self = .array(try container.decode([FMVarQueryNode].self, forKey: .nodes))
    case .object:
      self = .object(try container.decode([FMVarQueryObjectMember].self, forKey: .members))
    }
  }

  /// Encodes an explicit discriminator rather than Swift's synthesized associated-value shape.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .null:
      try container.encode(Kind.null, forKey: .kind)
    case .boolean(let value):
      try container.encode(Kind.boolean, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .integer(let value):
      try container.encode(Kind.integer, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .number(let value):
      try container.encode(Kind.number, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .string(let value):
      try container.encode(Kind.string, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .array(let nodes):
      try container.encode(Kind.array, forKey: .kind)
      try container.encode(nodes, forKey: .nodes)
    case .object(let members):
      try container.encode(Kind.object, forKey: .kind)
      try container.encode(members, forKey: .members)
    }
  }
}

/// One identified node in the portable query argument or an evaluation nodelist.
public struct FMVarQueryNode: Codable, Equatable, Sendable {
  /// Identity retained through query evaluation.
  public let id: FMVarQueryNodeID
  /// I-JSON-compatible node value.
  public let value: FMVarQueryValue
  /// Original YAML scalar content when this node was projected from a scalar.
  public let sourceScalar: FMVarSourceScalar?

  /// Creates one portable query node.
  public init(
    id: FMVarQueryNodeID,
    value: FMVarQueryValue,
    sourceScalar: FMVarSourceScalar? = nil
  ) {
    self.id = id
    self.value = value
    self.sourceScalar = sourceScalar
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case value
    case sourceScalar = "source-scalar"
  }
}

/// Validated YAML projection ready to serve as an RFC 9535 query argument.
public struct FMVarQueryArgument: Codable, Equatable, Sendable {
  /// Arbitrary I-JSON-compatible document root.
  public let root: FMVarQueryNode

  /// Creates a validated portable query argument.
  public init(root: FMVarQueryNode) { self.root = root }
}

/// Broad selected-value shape relevant to `<fm-var>` and `<fm-list>`.
public enum FMVarValueShape: String, Codable, Equatable, Sendable, CaseIterable {
  /// JSON/YAML null.
  case null
  /// String, Boolean, integer, or finite number.
  case scalar
  /// One-dimensional or nested sequence.
  case sequence
  /// Mapping/object.
  case mapping
}

/// Cardinality class for an RFC 9535 nodelist.
public enum FMVarNodelistCardinality: String, Codable, Equatable, Sendable, CaseIterable {
  /// No selected nodes.
  case zero
  /// Exactly one selected node.
  case one
  /// More than one selected node.
  case multiple

  /// Classifies a selected-node count.
  public init(count: UInt) {
    if count == 0 {
      self = .zero
    } else if count == 1 {
      self = .one
    } else {
      self = .multiple
    }
  }
}

/// Ordered RFC 9535 query result nodes, including duplicates.
public struct FMVarNodelist: Codable, Equatable, Sendable {
  /// Nodes in evaluator result order. Duplicate identities are preserved.
  public let nodes: [FMVarQueryNode]

  /// Creates a nodelist without sorting or deduplicating its nodes.
  public init(nodes: [FMVarQueryNode]) { self.nodes = nodes }

  /// Selected nodelist cardinality.
  public var cardinality: FMVarNodelistCardinality { .init(count: UInt(nodes.count)) }
}

/// Whether YAML projection produced a valid JSONPath query argument.
public enum FMVarQueryArgumentStatus: String, Codable, Equatable, Sendable, CaseIterable {
  /// Projection produced a valid I-JSON-compatible argument.
  case valid
  /// Projection rejected nonportable or invalid YAML data.
  case invalid
}

/// Portable outcome category for RFC 9535 query evaluation.
public enum FMVarQueryEvaluationStatus: String, Codable, Equatable, Sendable, CaseIterable {
  /// Evaluation was not attempted, such as after query-argument validation failed.
  case notEvaluated = "not-evaluated"
  /// A valid supported query produced a nodelist, including an empty nodelist.
  case selected
  /// The query was malformed or invalid under RFC 9535.
  case invalidQuery = "invalid-query"
  /// The query requires an unavailable extension function or other valid capability.
  case unsupportedCapability = "unsupported-capability"
  /// Evaluation exceeded a configured resource limit.
  case resourceLimited = "resource-limited"
}

/// Structured result metadata shared by validation, synchronization, and fixtures.
public struct FMVarReferenceResultMetadata: Codable, Equatable, Sendable {
  /// Element-level outcome.
  public let status: FMVarReferenceStatus
  /// Whether the YAML-derived query argument was valid.
  public let queryArgumentStatus: FMVarQueryArgumentStatus
  /// Query evaluation outcome.
  public let queryEvaluationStatus: FMVarQueryEvaluationStatus
  /// Selected node count when evaluation produced a nodelist.
  public let selectedNodeCount: UInt?
  /// Shape of the node to which element-specific rules were applied, when one was selected.
  public let selectedValueShape: FMVarValueShape?

  /// Creates structured reference-result metadata.
  public init(
    status: FMVarReferenceStatus,
    queryArgumentStatus: FMVarQueryArgumentStatus,
    queryEvaluationStatus: FMVarQueryEvaluationStatus,
    selectedNodeCount: UInt? = nil,
    selectedValueShape: FMVarValueShape? = nil
  ) {
    self.status = status
    self.queryArgumentStatus = queryArgumentStatus
    self.queryEvaluationStatus = queryEvaluationStatus
    self.selectedNodeCount = selectedNodeCount
    self.selectedValueShape = selectedValueShape
  }

  /// Cardinality derived from ``selectedNodeCount``, or `nil` when no nodelist was produced.
  public var selectedCardinality: FMVarNodelistCardinality? {
    selectedNodeCount.map(FMVarNodelistCardinality.init(count:))
  }

  private enum CodingKeys: String, CodingKey {
    case status
    case queryArgumentStatus = "query-argument-status"
    case queryEvaluationStatus = "query-evaluation-status"
    case selectedNodeCount = "selected-node-count"
    case selectedValueShape = "selected-value-shape"
  }
}
