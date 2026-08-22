import Foundation
import MarkdownUtilitiesCore

/// A validated, collection-relative directory used to narrow type selection.
public struct MarkdownSearchRoot: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  /// The root of the configured record collection.
  public static let collectionRoot = MarkdownSearchRoot(validated: ".")

  /// Canonical collection-relative directory, including its trailing slash, or `.` for the root.
  public let rawValue: String

  /// Validates and creates a collection-relative search root.
  ///
  /// Nested directories must use forward slashes and end in `/`. Absolute paths,
  /// empty components, `.`, and `..` components are rejected.
  ///
  /// - Parameter rawValue: Authored directory path, or `.` for the collection root.
  public init?(rawValue: String) {
    guard Self.isValid(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  private init(validated rawValue: String) {
    self.rawValue = rawValue
  }

  /// Decodes a validated search root from its single-string representation.
  ///
  /// - Parameter decoder: Decoder containing a collection-relative directory string.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    guard let value = Self(rawValue: rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid Markdown search root \"\(rawValue)\""
      )
    }
    self = value
  }

  /// Encodes the canonical search root as a single string.
  ///
  /// - Parameter encoder: Destination for the search-root string.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  /// Checks the portable directory invariants without constructing a value.
  static func isValid(_ value: String) -> Bool {
    if value == "." { return true }
    guard value.isEmpty == false,
          value.hasPrefix("/") == false,
          value.hasSuffix("/"),
          value.contains("\\") == false
    else { return false }

    let content = value.dropLast()
    let components = content.split(separator: "/", omittingEmptySubsequences: false)
    return components.allSatisfy { component in
      component.isEmpty == false && component != "." && component != ".."
    }
  }
}

/// A validated route path or generated path template.
public struct EndpointRoutePath: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  /// Canonical absolute route or generated route template.
  public let rawValue: String

  /// Creates a path after the compiler has established its invariants.
  init(validated rawValue: String) {
    self.rawValue = rawValue
  }

  /// Validates a literal, item, or reserved logical-path route template.
  ///
  /// - Parameter rawValue: Absolute route path or one of the supported generated templates.
  public init?(rawValue: String) {
    guard EndpointPlanCompiler.isSafeRouteTemplate(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  /// Decodes and validates a route path from its single-string representation.
  ///
  /// - Parameter decoder: Decoder containing an endpoint route string.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    guard let value = Self(rawValue: rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid endpoint route path \"\(rawValue)\""
      )
    }
    self = value
  }

  /// Encodes the canonical route path as a single string.
  ///
  /// - Parameter encoder: Destination for the route string.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A planned selection with all external references and search roots validated.
public enum PlannedResourceSelection: Codable, Equatable, Sendable {
  /// Uses applicability of a resolved named rule for membership.
  case rule(name: String)

  /// Uses conformance to a resolved mdtype within a validated search root.
  case type(name: MarkdownTypeName, searchRoot: MarkdownSearchRoot)

  /// Uses rule applicability for membership and a resolved mdtype for validity reporting.
  case ruleWithExpectedType(rule: String, expectedType: MarkdownTypeName)
}

/// One immutable resource in a compiled endpoint plan.
public struct PlannedMarkdownResource: Codable, Equatable, Sendable {
  /// Stable configured resource name.
  public let name: String

  /// Validated collection route shared by this resource's operations.
  public let route: EndpointRoutePath

  /// Canonically ordered read operations enabled for this resource.
  public let operations: [MarkdownResourceOperation]

  /// Resolved selection policy consumed by the read snapshot.
  public let selection: PlannedResourceSelection

  /// Identity policy used to build collision-safe lookup indexes.
  public let identityPolicy: MarkdownRecordIdentityPolicy

  /// Representation policy used to project selected records.
  public let projectionPolicy: MarkdownResourceProjectionPolicy

  /// Creates a fully validated planned resource.
  ///
  /// Callers normally receive these values from ``EndpointPlanCompiler``.
  ///
  /// - Parameters:
  ///   - name: Stable configured resource name.
  ///   - route: Validated collection route.
  ///   - operations: Canonically ordered enabled operations.
  ///   - selection: Resolved selection policy.
  ///   - identityPolicy: Identity and fallback policy.
  ///   - projectionPolicy: Public read representation.
  public init(
    name: String,
    route: EndpointRoutePath,
    operations: [MarkdownResourceOperation],
    selection: PlannedResourceSelection,
    identityPolicy: MarkdownRecordIdentityPolicy,
    projectionPolicy: MarkdownResourceProjectionPolicy
  ) {
    self.name = name
    self.route = route
    self.operations = operations
    self.selection = selection
    self.identityPolicy = identityPolicy
    self.projectionPolicy = projectionPolicy
  }
}

/// HTTP methods used by transport-neutral endpoint descriptions.
public enum EndpointHTTPMethod: String, Codable, Equatable, Sendable {
  /// Retrieves a collection or individual resource without mutation.
  case get = "GET"
}

/// Semantic handler categories consumed by HTTP adapters and contract generators.
public enum EndpointRouteKind: String, Codable, Equatable, Sendable {
  /// Lists selected records for one configured resource.
  case collection

  /// Retrieves one selected record by primary identity.
  case item

  /// Retrieves a canonical record by its collection-relative logical path.
  case logicalPath

  /// Retrieves the active OpenAPI 3.1 description generated from this plan.
  case openAPI
}

/// A transport-neutral route installed from an endpoint plan.
public struct EndpointRouteDescription: Codable, Equatable, Sendable {
  /// HTTP method installed by a transport adapter.
  public let method: EndpointHTTPMethod

  /// Canonical path template shared with contract generation.
  public let path: EndpointRoutePath

  /// Semantic handler behavior associated with the route.
  public let kind: EndpointRouteKind

  /// Owning resource, or `nil` for a server-wide route such as logical-path lookup.
  public let resourceName: String?

  /// Globally unique stable identifier for the operation.
  public let operationID: String

  /// Creates a transport-neutral route description.
  ///
  /// - Parameters:
  ///   - method: HTTP method to register.
  ///   - path: Validated route template.
  ///   - kind: Semantic handler category.
  ///   - resourceName: Owning resource, if the route is resource-specific.
  ///   - operationID: Stable globally unique operation identifier.
  public init(
    method: EndpointHTTPMethod,
    path: EndpointRoutePath,
    kind: EndpointRouteKind,
    resourceName: String?,
    operationID: String
  ) {
    self.method = method
    self.path = path
    self.kind = kind
    self.resourceName = resourceName
    self.operationID = operationID
  }
}

/// The deterministic, immutable source of runtime and OpenAPI route truth.
public struct EndpointPlan: Codable, Equatable, Sendable {
  /// Server configuration schema version from which this plan was compiled.
  public let serverConfigVersion: String

  /// Validated resources in deterministic route-and-name order.
  public let resources: [PlannedMarkdownResource]

  /// Runtime and contract routes in deterministic path, method, and operation-ID order.
  public let routes: [EndpointRouteDescription]

  /// Resolved contracts for the Markdown types explicitly referenced by resources.
  public let typeSchemas: [ResolvedMarkdownTypeFrontmatterSchema]

  /// Creates an immutable endpoint plan from already compiled values.
  ///
  /// Callers normally obtain a plan from ``EndpointPlanCompiler/compile(_:)``.
  ///
  /// - Parameters:
  ///   - serverConfigVersion: Validated configuration schema version.
  ///   - resources: Canonically ordered planned resources.
  ///   - routes: Canonically ordered transport-neutral routes.
  ///   - typeSchemas: Resolved schemas referenced by planned resources.
  public init(
    serverConfigVersion: String,
    resources: [PlannedMarkdownResource],
    routes: [EndpointRouteDescription],
    typeSchemas: [ResolvedMarkdownTypeFrontmatterSchema] = []
  ) {
    self.serverConfigVersion = serverConfigVersion
    self.resources = resources
    self.routes = routes
    self.typeSchemas = typeSchemas
  }
}
