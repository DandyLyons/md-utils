import Foundation
import MarkdownUtilitiesCore

/// The supported version of the md-utils server resource-configuration schema.
public enum MarkdownServerConfigurationSchemaVersion {
  /// The newest server configuration schema understood by this package version.
  public static let current = "1"
}

/// Explicit, opt-in server resource configuration.
public struct MarkdownServerConfiguration: Codable, Equatable, Sendable {
  /// Schema version used to decode and validate the resource declarations.
  public let serverConfigVersion: String

  /// Resources explicitly exposed by the server; loaded rules and types are not exposed implicitly.
  public let resources: [MarkdownResourceConfiguration]

  /// Creates a transport-neutral server configuration.
  ///
  /// - Parameters:
  ///   - serverConfigVersion: Schema version for the configuration model.
  ///   - resources: Explicit resource declarations to compile into an ``EndpointPlan``.
  public init(
    serverConfigVersion: String = MarkdownServerConfigurationSchemaVersion.current,
    resources: [MarkdownResourceConfiguration] = []
  ) {
    self.serverConfigVersion = serverConfigVersion
    self.resources = resources
  }
}

/// A read operation that an explicitly configured resource exposes.
public enum MarkdownResourceOperation: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  /// Enumerates selected records through a collection route.
  case list

  /// Fetches one selected record through its primary identity.
  case get
}

/// How a configured resource selects canonical Markdown records.
public enum MarkdownResourceSelection: Codable, Equatable, Sendable {
  /// Selects records for which the named `MarkdownRuleDefinition` is applicable.
  case rule(name: String)

  /// Selects records conforming to a named mdtype beneath a collection-relative directory.
  case type(name: MarkdownTypeName, searchRoot: String)

  /// Selects by rule while separately assessing and reporting conformance to an expected mdtype.
  case ruleWithExpectedType(rule: String, expectedType: MarkdownTypeName)

  // Keep the serialized form explicitly tagged so configuration files do not depend on
  // Swift's synthesized associated-value representation.
  private enum CodingKeys: String, CodingKey {
    case mode
    case rule
    case type
    case searchRoot
  }

  private enum Mode: String, Codable {
    case rule
    case type
    case ruleWithExpectedType
  }

  /// Decodes an explicitly tagged resource selection.
  ///
  /// - Parameter decoder: Decoder containing `mode` and the fields required by that mode.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Mode.self, forKey: .mode) {
    case .rule:
      self = .rule(name: try container.decode(String.self, forKey: .rule))
    case .type:
      self = .type(
        name: MarkdownTypeName(rawValue: try container.decode(String.self, forKey: .type)),
        searchRoot: try container.decode(String.self, forKey: .searchRoot)
      )
    case .ruleWithExpectedType:
      self = .ruleWithExpectedType(
        rule: try container.decode(String.self, forKey: .rule),
        expectedType: MarkdownTypeName(
          rawValue: try container.decode(String.self, forKey: .type)
        )
      )
    }
  }

  /// Encodes the selection using its stable, explicitly tagged representation.
  ///
  /// - Parameter encoder: Destination for the selection mode and its associated references.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .rule(let name):
      try container.encode(Mode.rule, forKey: .mode)
      try container.encode(name, forKey: .rule)
    case .type(let name, let searchRoot):
      try container.encode(Mode.type, forKey: .mode)
      try container.encode(name.rawValue, forKey: .type)
      try container.encode(searchRoot, forKey: .searchRoot)
    case .ruleWithExpectedType(let rule, let expectedType):
      try container.encode(Mode.ruleWithExpectedType, forKey: .mode)
      try container.encode(rule, forKey: .rule)
      try container.encode(expectedType.rawValue, forKey: .type)
    }
  }
}

/// The public representation used for records selected by a resource.
public enum MarkdownResourceProjectionPolicy: String, Codable, Equatable, Sendable {
  /// The generic read envelope defined by the server read-snapshot layer.
  case genericRecord
}

/// Overrides the stable operation identifier for one configured operation.
public struct MarkdownOperationIDOverride: Codable, Equatable, Sendable {
  /// Configured operation whose derived identifier is replaced.
  public let operation: MarkdownResourceOperation

  /// Explicit identifier consumed by route adapters and contract generators.
  public let operationID: String

  /// Creates an explicit operation-ID override.
  ///
  /// - Parameters:
  ///   - operation: Enabled operation to override.
  ///   - operationID: Nonempty identifier that must be unique across the compiled plan.
  public init(operation: MarkdownResourceOperation, operationID: String) {
    self.operation = operation
    self.operationID = operationID
  }
}

/// One explicitly exposed Markdown-backed server resource.
public struct MarkdownResourceConfiguration: Codable, Equatable, Sendable {
  /// Stable, case-sensitive name used to identify this resource in a plan.
  public let name: String

  /// Absolute literal route at which the resource is exposed, such as `/books`.
  public let route: String

  /// Read operations explicitly enabled for the resource.
  public let operations: [MarkdownResourceOperation]

  /// Rule- or type-based policy that determines resource membership.
  public let selection: MarkdownResourceSelection

  /// Policy for deriving primary identities and enabling logical-path fallback.
  public let identityPolicy: MarkdownRecordIdentityPolicy

  /// Read representation applied after a record has been selected and assessed.
  public let projectionPolicy: MarkdownResourceProjectionPolicy

  /// Optional replacements for deterministically derived operation identifiers.
  public let operationIDOverrides: [MarkdownOperationIDOverride]

  /// Creates one explicit server resource declaration.
  ///
  /// - Parameters:
  ///   - name: Stable, case-sensitive resource name.
  ///   - route: Absolute literal collection route.
  ///   - operations: Read operations to expose.
  ///   - selection: Membership policy for the resource.
  ///   - identityPolicy: Primary-identity and logical-path fallback behavior.
  ///   - projectionPolicy: Public read representation, defaulting to the generic record envelope.
  ///   - operationIDOverrides: Optional explicit operation identifiers.
  public init(
    name: String,
    route: String,
    operations: [MarkdownResourceOperation],
    selection: MarkdownResourceSelection,
    identityPolicy: MarkdownRecordIdentityPolicy,
    projectionPolicy: MarkdownResourceProjectionPolicy = .genericRecord,
    operationIDOverrides: [MarkdownOperationIDOverride] = []
  ) {
    self.name = name
    self.route = route
    self.operations = operations
    self.selection = selection
    self.identityPolicy = identityPolicy
    self.projectionPolicy = projectionPolicy
    self.operationIDOverrides = operationIDOverrides
  }
}
