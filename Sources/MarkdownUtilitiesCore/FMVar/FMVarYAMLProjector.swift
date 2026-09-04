import Foundation
import Yams

/// Root shape required while projecting an fm-var YAML source.
public enum FMVarYAMLRootRequirement: String, Codable, Equatable, Sendable, CaseIterable {
  /// Any portable YAML root is accepted.
  case any
  /// The root must be a mapping, as required for Markdown frontmatter.
  case mapping
}

/// One source position reported by Yams.
public struct FMVarYAMLSourcePosition: Codable, Equatable, Sendable {
  /// One-based source line.
  public let line: Int
  /// One-based Unicode-scalar column.
  public let column: Int

  /// Creates a YAML source position.
  public init(line: Int, column: Int) {
    self.line = line
    self.column = column
  }
}

/// Stable reason that YAML could not become an fm-var query argument.
public enum FMVarQueryArgumentFailureReason: String, Codable, Equatable, Sendable, CaseIterable {
  /// Yams rejected the YAML stream or document syntax.
  case malformedYAML = "malformed-yaml"
  /// A standalone YAML stream contained no document root.
  case emptyDocument = "empty-document"
  /// A mapping repeated a key.
  case duplicateMappingKey = "duplicate-mapping-key"
  /// A mapping key did not resolve to a string.
  case nonStringMappingKey = "non-string-mapping-key"
  /// An alias was cyclic, forward, self-referential, or undefined.
  case invalidAlias = "invalid-alias"
  /// A node used a tag outside the YAML 1.2.2 Core Schema types supported by RFC 001.
  case unsupportedTag = "unsupported-tag"
  /// A scalar's content was not valid for its resolved or explicit Core Schema tag.
  case invalidScalar = "invalid-scalar"
  /// A YAML float was infinite or NaN.
  case nonFiniteFloat = "non-finite-float"
  /// A YAML integer exceeded the RFC 001 interoperable integer range.
  case integerOutOfRange = "integer-out-of-range"
  /// A YAML float overflowed finite IEEE 754 binary64.
  case floatingPointOverflow = "floating-point-overflow"
  /// Markdown frontmatter did not have the required mapping root.
  case markdownRootNotMapping = "markdown-root-not-mapping"
}

/// Structured details for one YAML-to-query-argument failure.
public struct FMVarQueryArgumentFailure: Codable, Equatable, Sendable {
  /// Stable projection failure category.
  public let reason: FMVarQueryArgumentFailureReason
  /// Deterministic JSONPath-style location when the failing node had one.
  public let nodeID: FMVarQueryNodeID?
  /// Yams-provided source position when available.
  public let position: FMVarYAMLSourcePosition?
  /// Human-readable explanation whose wording is not stable API.
  public let message: String

  /// Creates a query-argument failure.
  public init(
    reason: FMVarQueryArgumentFailureReason,
    nodeID: FMVarQueryNodeID? = nil,
    position: FMVarYAMLSourcePosition? = nil,
    message: String
  ) {
    self.reason = reason
    self.nodeID = nodeID
    self.position = position
    self.message = message
  }

  /// Stable diagnostic code corresponding to ``reason``.
  public var diagnosticCode: FMVarDiagnosticCode {
    switch reason {
    case .malformedYAML: .malformedYAML
    case .emptyDocument: .emptyYAMLDocument
    case .duplicateMappingKey: .duplicateYAMLKey
    case .nonStringMappingKey: .nonStringYAMLKey
    case .invalidAlias: .invalidYAMLAlias
    case .unsupportedTag: .unsupportedYAMLTag
    case .invalidScalar: .invalidYAMLScalar
    case .nonFiniteFloat: .nonFiniteYAMLFloat
    case .integerOutOfRange: .yamlIntegerOutOfRange
    case .floatingPointOverflow: .yamlFloatOverflow
    case .markdownRootNotMapping: .invalidYAMLFrontmatterRoot
    }
  }

  private enum CodingKeys: String, CodingKey {
    case reason
    case nodeID = "node-id"
    case position
    case message
  }
}

/// Result of projecting one YAML 1.2.2 Core Schema document.
public struct FMVarYAMLProjection: Codable, Equatable, Sendable {
  /// Whether projection produced a query argument.
  public let status: FMVarQueryArgumentStatus
  /// Valid query argument when ``status`` is ``FMVarQueryArgumentStatus/valid``.
  public let argument: FMVarQueryArgument?
  /// Structured failure when ``status`` is ``FMVarQueryArgumentStatus/invalid``.
  public let failure: FMVarQueryArgumentFailure?

  /// Creates a YAML projection result.
  public init(
    status: FMVarQueryArgumentStatus,
    argument: FMVarQueryArgument? = nil,
    failure: FMVarQueryArgumentFailure? = nil
  ) {
    self.status = status
    self.argument = argument
    self.failure = failure
  }
}

/// Projects Yams nodes resolved with the YAML 1.2.2 Core Schema into portable fm-var values.
///
/// Yams remains responsible for YAML syntax, scalar decoding, mappings, sequences, anchors, and
/// aliases. This adapter supplies Core Schema resolver rules and validates the narrower RFC 001
/// I-JSON contract. See <doc:ResolvingFMVarSources> for the complete projection rules.
public struct FMVarYAMLProjector: Sendable {
  private static let maximumInteroperableInteger: Int64 = 9_007_199_254_740_991
  private static let booleanPattern = "^(?:true|True|TRUE|false|False|FALSE)$"
  private static let integerPattern = "^[-+]?[0-9]+$"
  private static let octalPattern = "^0o[0-7]+$"
  private static let hexadecimalPattern = "^0x[0-9a-fA-F]+$"
  private static let floatPattern = "^(?:[-+]?(?:\\.[0-9]+|[0-9]+(?:\\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?|[-+]?\\.(?:inf|Inf|INF)|\\.(?:nan|NaN|NAN))$"
  private static let nullPattern = "^(?:~|null|Null|NULL|)$"

  /// Creates a YAML query-argument projector.
  public init() {}

  /// Parses and projects one YAML document without throwing host-facing errors.
  ///
  /// - Parameters:
  ///   - yaml: YAML source decoded as UTF-8.
  ///   - rootRequirement: Whether the root may have any portable shape or must be a mapping.
  /// - Returns: A valid query argument or a structured projection failure.
  public func project(
    yaml: String,
    rootRequirement: FMVarYAMLRootRequirement = .any
  ) -> FMVarYAMLProjection {
    let resolver: Resolver
    do {
      resolver = try Self.makeCoreSchemaResolver()
    } catch {
      return invalid(
        reason: .malformedYAML,
        message: "The YAML 1.2.2 Core Schema resolver could not be configured: \(error)"
      )
    }

    let root: Node
    do {
      guard let parsed = try Yams.compose(yaml: yaml, resolver) else {
        return invalid(reason: .emptyDocument, message: "The YAML stream has no document root.")
      }
      root = parsed
    } catch let error as YamlError {
      return invalid(yamlError: error)
    } catch {
      return invalid(reason: .malformedYAML, message: "Yams rejected the YAML document: \(error)")
    }

    if rootRequirement == .mapping, root.mapping == nil {
      return invalid(
        reason: .markdownRootNotMapping,
        nodeID: FMVarQueryNodeID(rawValue: "$"),
        position: position(of: root),
        message: "Markdown YAML frontmatter must have a mapping root."
      )
    }

    do {
      let node = try project(node: root, id: FMVarQueryNodeID(rawValue: "$"))
      return FMVarYAMLProjection(status: .valid, argument: FMVarQueryArgument(root: node))
    } catch let failure as ProjectionError {
      return FMVarYAMLProjection(status: .invalid, failure: failure.failure)
    } catch {
      return invalid(reason: .malformedYAML, message: "YAML projection failed: \(error)")
    }
  }

  private static func makeCoreSchemaResolver() throws -> Resolver {
    try Resolver.basic
      .appending(.bool, booleanPattern)
      .appending(.int, integerPattern)
      .appending(.int, octalPattern)
      .appending(.int, hexadecimalPattern)
      .appending(.float, floatPattern)
      .appending(.null, nullPattern)
  }

  private func project(node: Node, id: FMVarQueryNodeID) throws -> FMVarQueryNode {
    switch node {
    case .mapping(let mapping):
      try requireTag(node, expected: Tag.Name.map.rawValue, id: id)
      var names = Set<String>()
      var members: [FMVarQueryObjectMember] = []
      members.reserveCapacity(mapping.count)
      for (keyNode, valueNode) in mapping {
        let keyID = FMVarQueryNodeID(rawValue: id.rawValue + "[<key>]")
        guard case .scalar(let scalar) = keyNode,
          keyNode.tag.rawValue == Tag.Name.str.rawValue
        else {
          throw failure(
            reason: .nonStringMappingKey,
            node: keyNode,
            id: keyID,
            message: "Every YAML mapping key must resolve to a string."
          )
        }
        let name = scalar.string
        guard names.insert(name).inserted else {
          throw failure(
            reason: .duplicateMappingKey,
            node: keyNode,
            id: keyID,
            message: "YAML mapping key '\(name)' is duplicated."
          )
        }
        let childID = FMVarQueryNodeID(rawValue: objectChildID(parent: id.rawValue, name: name))
        members.append(FMVarQueryObjectMember(
          name: name,
          node: try project(node: valueNode, id: childID)
        ))
      }
      return FMVarQueryNode(id: id, value: .object(members))

    case .sequence(let sequence):
      try requireTag(node, expected: Tag.Name.seq.rawValue, id: id)
      let children = try sequence.enumerated().map { index, child in
        try project(
          node: child,
          id: FMVarQueryNodeID(rawValue: "\(id.rawValue)[\(index)]")
        )
      }
      return FMVarQueryNode(id: id, value: .array(children))

    case .scalar(let scalar):
      return try project(scalar: scalar, node: node, id: id)

    case .alias:
      throw failure(
        reason: .invalidAlias,
        node: node,
        id: id,
        message: "Yams returned an unresolved YAML alias."
      )
    }
  }

  private func project(
    scalar: Node.Scalar,
    node: Node,
    id: FMVarQueryNodeID
  ) throws -> FMVarQueryNode {
    let sourceScalar = FMVarSourceScalar(content: scalar.string)
    switch node.tag.rawValue {
    case Tag.Name.str.rawValue:
      return FMVarQueryNode(id: id, value: .string(scalar.string), sourceScalar: sourceScalar)

    case Tag.Name.null.rawValue:
      guard matches(scalar.string, pattern: Self.nullPattern) else {
        throw failure(
          reason: .invalidScalar,
          node: node,
          id: id,
          message: "The scalar is not valid for the YAML null tag."
        )
      }
      return FMVarQueryNode(id: id, value: .null, sourceScalar: sourceScalar)

    case Tag.Name.bool.rawValue:
      guard matches(scalar.string, pattern: Self.booleanPattern) else {
        throw failure(
          reason: .invalidScalar,
          node: node,
          id: id,
          message: "The scalar is not valid for the YAML Boolean tag."
        )
      }
      let value: Bool
      switch scalar.string.lowercased() {
      case "true": value = true
      case "false": value = false
      default:
        throw failure(
          reason: .invalidScalar,
          node: node,
          id: id,
          message: "The scalar is not valid for the YAML Boolean tag."
        )
      }
      return FMVarQueryNode(id: id, value: .boolean(value), sourceScalar: sourceScalar)

    case Tag.Name.int.rawValue:
      guard matches(scalar.string, patterns: [
        Self.integerPattern, Self.octalPattern, Self.hexadecimalPattern,
      ]) else {
        throw failure(
          reason: .invalidScalar,
          node: node,
          id: id,
          message: "The scalar is not valid for the YAML integer tag."
        )
      }
      guard let value = parseInteger(scalar.string) else {
        throw failure(
          reason: .integerOutOfRange,
          node: node,
          id: id,
          message: "The YAML integer is outside the supported signed 64-bit parsing range."
        )
      }
      guard value >= -Self.maximumInteroperableInteger,
        value <= Self.maximumInteroperableInteger
      else {
        throw failure(
          reason: .integerOutOfRange,
          node: node,
          id: id,
          message: "The YAML integer is outside RFC 001's interoperable range."
        )
      }
      return FMVarQueryNode(id: id, value: .integer(value), sourceScalar: sourceScalar)

    case Tag.Name.float.rawValue:
      guard matches(scalar.string, pattern: Self.floatPattern) else {
        throw failure(
          reason: .invalidScalar,
          node: node,
          id: id,
          message: "The scalar is not valid for the YAML float tag."
        )
      }
      let normalized = scalar.string.lowercased()
      if normalized.contains(".inf") || normalized.contains(".nan") {
        throw failure(
          reason: .nonFiniteFloat,
          node: node,
          id: id,
          message: "Non-finite YAML floats cannot be represented in I-JSON."
        )
      }
      guard let value = parseFloat(scalar.string) else {
        throw failure(
          reason: .invalidScalar,
          node: node,
          id: id,
          message: "The scalar is not valid for the YAML float tag."
        )
      }
      guard value.isFinite else {
        throw failure(
          reason: .floatingPointOverflow,
          node: node,
          id: id,
          message: "The YAML float overflows finite IEEE 754 binary64."
        )
      }
      return FMVarQueryNode(id: id, value: .number(value), sourceScalar: sourceScalar)

    default:
      throw failure(
        reason: .unsupportedTag,
        node: node,
        id: id,
        message: "YAML tag '\(node.tag.rawValue)' is not portable under RFC 001."
      )
    }
  }

  private func requireTag(_ node: Node, expected: String, id: FMVarQueryNodeID) throws {
    guard node.tag.rawValue == expected else {
      throw failure(
        reason: .unsupportedTag,
        node: node,
        id: id,
        message: "YAML tag '\(node.tag.rawValue)' is not portable under RFC 001."
      )
    }
  }

  private func parseInteger(_ source: String) -> Int64? {
    let value = source
    let negative = value.hasPrefix("-")
    let hasSign = negative || value.hasPrefix("+")
    let sign = negative ? "-" : ""
    let unsigned = value.dropFirst(hasSign ? 1 : 0)
    if unsigned.hasPrefix("0o") {
      return Int64(sign + unsigned.dropFirst(2), radix: 8)
    }
    if unsigned.hasPrefix("0x") {
      return Int64(sign + unsigned.dropFirst(2), radix: 16)
    }
    return Int64(value, radix: 10)
  }

  private func parseFloat(_ source: String) -> Double? {
    var value = source
    if value.hasPrefix(".") {
      value = "0" + value
    } else if value.hasPrefix("+.") {
      value = "+0" + value.dropFirst()
    } else if value.hasPrefix("-.") {
      value = "-0" + value.dropFirst()
    }
    return Double(value)
  }

  private func matches(_ source: String, pattern: String) -> Bool {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return expression.firstMatch(in: source, range: range)?.range == range
  }

  private func matches(_ source: String, patterns: [String]) -> Bool {
    patterns.contains { matches(source, pattern: $0) }
  }

  private func objectChildID(parent: String, name: String) -> String {
    let escaped = name
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
    return "\(parent)['\(escaped)']"
  }

  private func failure(
    reason: FMVarQueryArgumentFailureReason,
    node: Node,
    id: FMVarQueryNodeID,
    message: String
  ) -> ProjectionError {
    ProjectionError(failure: FMVarQueryArgumentFailure(
      reason: reason,
      nodeID: id,
      position: position(of: node),
      message: message
    ))
  }

  private func invalid(yamlError: YamlError) -> FMVarYAMLProjection {
    switch yamlError {
    case .duplicatedKeysInMapping(_, let context):
      return invalid(
        reason: .duplicateMappingKey,
        position: FMVarYAMLSourcePosition(
          line: context.mark.line,
          column: context.mark.column
        ),
        message: yamlError.description
      )
    case .composer(_, let problem, let mark, _) where problem.contains("alias"):
      return invalid(
        reason: .invalidAlias,
        position: FMVarYAMLSourcePosition(line: mark.line, column: mark.column),
        message: yamlError.description
      )
    case .scanner(_, _, let mark, _),
      .parser(_, _, let mark, _),
      .composer(_, _, let mark, _):
      return invalid(
        reason: .malformedYAML,
        position: FMVarYAMLSourcePosition(line: mark.line, column: mark.column),
        message: yamlError.description
      )
    default:
      return invalid(reason: .malformedYAML, message: yamlError.description)
    }
  }

  private func invalid(
    reason: FMVarQueryArgumentFailureReason,
    nodeID: FMVarQueryNodeID? = nil,
    position: FMVarYAMLSourcePosition? = nil,
    message: String
  ) -> FMVarYAMLProjection {
    FMVarYAMLProjection(
      status: .invalid,
      failure: FMVarQueryArgumentFailure(
        reason: reason,
        nodeID: nodeID,
        position: position,
        message: message
      )
    )
  }

  private func position(of node: Node) -> FMVarYAMLSourcePosition? {
    node.mark.map { FMVarYAMLSourcePosition(line: $0.line, column: $0.column) }
  }
}

private struct ProjectionError: Error {
  let failure: FMVarQueryArgumentFailure
}
