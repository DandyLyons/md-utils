import Foundation
import MarkdownUtilitiesCore

/// Stable categories produced while compiling endpoint configuration.
public enum EndpointPlanDiagnosticCode: String, Codable, Equatable, Sendable {
  /// Configuration declares a schema version unsupported by this package release.
  case unsupportedConfigurationVersion = "endpoint.configuration.unsupported-version"
  /// Resource name is empty or contains ambiguous surrounding whitespace.
  case invalidResourceName = "endpoint.resource.invalid-name"
  /// More than one resource uses the same case-sensitive name.
  case duplicateResourceName = "endpoint.resource.duplicate-name"
  /// A configured resource does not expose any operation.
  case missingOperations = "endpoint.operation.missing"
  /// The same operation appears more than once on one resource.
  case duplicateOperation = "endpoint.operation.duplicate"
  /// One operation has multiple explicit operation-ID overrides.
  case duplicateOperationIDOverride = "endpoint.operation-id.duplicate-override"
  /// An override refers to an operation the resource does not expose.
  case operationIDForDisabledOperation = "endpoint.operation-id.disabled-operation"
  /// An explicit operation ID is empty or contains only whitespace.
  case invalidOperationID = "endpoint.operation-id.invalid"
  /// Multiple planned routes resolve to the same operation ID.
  case duplicateOperationID = "endpoint.operation-id.duplicate"
  /// A selection refers to a rule that was not supplied to the compiler.
  case missingRule = "endpoint.reference.rule-missing"
  /// A selected rule name resolves to more than one supplied definition.
  case ambiguousRule = "endpoint.reference.rule-ambiguous"
  /// A selection refers to an mdtype absent from the validated registry.
  case missingType = "endpoint.reference.type-missing"
  /// Type selection declares an unsafe or non-directory search root.
  case invalidSearchRoot = "endpoint.selection.invalid-search-root"
  /// A resource route is not a safe absolute literal path.
  case unsafeRoute = "endpoint.route.unsafe"
  /// A resource attempts to use the server-owned `/_md-utils` namespace.
  case reservedRoute = "endpoint.route.reserved"
  /// Two routes with the same method can match at least one common request path.
  case routeCollision = "endpoint.route.collision"
}

/// One structured endpoint-configuration problem.
public struct EndpointPlanDiagnostic: Codable, Equatable, Sendable {
  /// Stable machine-readable category for the problem.
  public let code: EndpointPlanDiagnosticCode
  /// Configuration location that produced the problem.
  public let location: String
  /// Human-readable explanation suitable for startup logs.
  public let message: String
  /// Other configuration locations participating in a duplicate or collision.
  public let conflictingLocations: [String]

  /// Creates one structured endpoint-plan diagnostic.
  ///
  /// - Parameters:
  ///   - code: Stable diagnostic category.
  ///   - location: Primary configuration location.
  ///   - message: Human-readable explanation.
  ///   - conflictingLocations: Related locations involved in the same problem.
  public init(
    code: EndpointPlanDiagnosticCode,
    location: String,
    message: String,
    conflictingLocations: [String] = []
  ) {
    self.code = code
    self.location = location
    self.message = message
    self.conflictingLocations = conflictingLocations
  }
}

/// All diagnostics produced by one failed endpoint-plan compilation.
public struct EndpointPlanCompilationError: Error, Codable, Equatable, Sendable, LocalizedError {
  /// Every configuration problem found during the compilation pass, deterministically ordered.
  public let diagnostics: [EndpointPlanDiagnostic]

  /// Creates a compilation failure from structured diagnostics.
  ///
  /// - Parameter diagnostics: Deterministically ordered startup problems.
  public init(diagnostics: [EndpointPlanDiagnostic]) {
    self.diagnostics = diagnostics
  }

  /// Concise startup-oriented rendering of all diagnostics.
  public var errorDescription: String? {
    diagnostics.map { "\($0.location): \($0.message)" }.joined(separator: "; ")
  }
}

/// Compiles explicit resources against reusable rules and validated Markdown types.
public struct EndpointPlanCompiler: Sendable {
  /// Reserved catch-all route used for enabled logical-path fallback lookups.
  public static let logicalPathRoute = "/_md-utils/path/{path...}"
  /// Stable operation identifier associated with ``logicalPathRoute``.
  public static let logicalPathOperationID = "md-utils.path.get"

  /// Loaded definitions remain private so compilation exposes only explicit references.
  private let rules: [MarkdownRuleDefinition]
  private let typeRegistry: MarkdownTypeRegistry

  /// Creates a compiler backed by reusable rules and a validated mdtype registry.
  ///
  /// - Parameters:
  ///   - rules: Reusable rule definitions available for explicit selection.
  ///   - typeRegistry: Validated mdtypes available for explicit selection and expected-type checks.
  public init(
    rules: [MarkdownRuleDefinition] = [],
    typeRegistry: MarkdownTypeRegistry
  ) {
    self.rules = rules
    self.typeRegistry = typeRegistry
  }

  /// Validates explicit resources and produces the immutable route source of truth.
  ///
  /// Compilation accumulates independent problems before failing. Successful output is
  /// canonically ordered, so equivalent configuration produces an identical plan.
  ///
  /// - Parameter configuration: Versioned transport-neutral resource configuration.
  /// - Returns: Deterministic resources and route descriptions for adapters and generators.
  /// - Throws: ``EndpointPlanCompilationError`` when any reference, path, operation, or route is invalid.
  public func compile(_ configuration: MarkdownServerConfiguration) throws -> EndpointPlan {
    // Validate the top-level version independently so resource diagnostics are still useful.
    var diagnostics: [EndpointPlanDiagnostic] = []
    if configuration.serverConfigVersion != MarkdownServerConfigurationSchemaVersion.current {
      diagnostics.append(EndpointPlanDiagnostic(
        code: .unsupportedConfigurationVersion,
        location: "serverConfigVersion",
        message: "Unsupported server configuration version \"\(configuration.serverConfigVersion)\"; expected \"\(MarkdownServerConfigurationSchemaVersion.current)\""
      ))
    }

    let duplicateNames = duplicates(configuration.resources.map(\.name))
    var plannedResources: [PlannedMarkdownResource] = []
    var routeCandidates: [RouteCandidate] = []
    var operationIDCandidates: [OperationIDCandidate] = []
    var needsLogicalPathRoute = false

    // Compile each resource independently, retaining diagnostics from invalid siblings.
    for (index, resource) in configuration.resources.enumerated() {
      let location = "resources[\(index)]"
      var resourceIsValid = true

      if resource.name.isEmpty || resource.name.trimmingCharacters(in: .whitespacesAndNewlines) != resource.name {
        diagnostics.append(EndpointPlanDiagnostic(
          code: .invalidResourceName,
          location: "\(location).name",
          message: "Resource names must be nonempty and cannot have leading or trailing whitespace"
        ))
        resourceIsValid = false
      }
      if duplicateNames.contains(resource.name) {
        diagnostics.append(EndpointPlanDiagnostic(
          code: .duplicateResourceName,
          location: "\(location).name",
          message: "Resource name \"\(resource.name)\" is configured more than once",
          conflictingLocations: resourceLocations(
            named: resource.name,
            in: configuration.resources,
            excluding: index,
            suffix: ".name"
          )
        ))
        resourceIsValid = false
      }

      let operationDuplicates = duplicates(resource.operations)
      if resource.operations.isEmpty {
        diagnostics.append(EndpointPlanDiagnostic(
          code: .missingOperations,
          location: "\(location).operations",
          message: "Resource \"\(resource.name)\" must configure at least one operation"
        ))
        resourceIsValid = false
      }
      for operation in operationDuplicates.sorted(by: { $0.rawValue < $1.rawValue }) {
        diagnostics.append(EndpointPlanDiagnostic(
          code: .duplicateOperation,
          location: "\(location).operations",
          message: "Operation \"\(operation.rawValue)\" is configured more than once"
        ))
        resourceIsValid = false
      }

      let route = validatedResourceRoute(resource.route, location: location, diagnostics: &diagnostics)
      let selection = validatedSelection(resource.selection, location: location, diagnostics: &diagnostics)
      let overrides = validatedOverrides(
        resource.operationIDOverrides,
        configuredOperations: Set(resource.operations),
        location: location,
        diagnostics: &diagnostics
      )
      if overrides.valid == false {
        resourceIsValid = false
      }
      guard resourceIsValid, let route, let selection else { continue }

      // Canonical operation order prevents authoring order from changing the plan.
      let operations = resource.operations.sorted { $0.rawValue < $1.rawValue }
      let planned = PlannedMarkdownResource(
        name: resource.name,
        route: route,
        operations: operations,
        selection: selection,
        identityPolicy: resource.identityPolicy,
        projectionPolicy: resource.projectionPolicy
      )
      plannedResources.append(planned)

      for operation in operations {
        let operationID = overrides.values[operation] ?? "\(resource.name).\(operation.rawValue)"
        let operationLocation = "\(location).operations.\(operation.rawValue)"
        operationIDCandidates.append(OperationIDCandidate(
          id: operationID,
          location: operationLocation
        ))
        switch operation {
        case .list:
          routeCandidates.append(RouteCandidate(
            description: EndpointRouteDescription(
              method: .get,
              path: route,
              kind: .collection,
              resourceName: resource.name,
              operationID: operationID
            ),
            location: operationLocation
          ))
        case .get:
          routeCandidates.append(RouteCandidate(
            description: EndpointRouteDescription(
              method: .get,
              path: EndpointRoutePath(validated: resource.route + "/{id}"),
              kind: .item,
              resourceName: resource.name,
              operationID: operationID
            ),
            location: operationLocation
          ))
          if resource.identityPolicy.logicalPathFallbackEnabled {
            needsLogicalPathRoute = true
          }
        }
      }
    }

    // Logical-path fallback is server-wide, so any eligible item route emits exactly one catch-all.
    if needsLogicalPathRoute {
      let path = EndpointRoutePath(validated: Self.logicalPathRoute)
      routeCandidates.append(RouteCandidate(
        description: EndpointRouteDescription(
          method: .get,
          path: path,
          kind: .logicalPath,
          resourceName: nil,
          operationID: Self.logicalPathOperationID
        ),
        location: "routes.logicalPath"
      ))
      operationIDCandidates.append(OperationIDCandidate(
        id: Self.logicalPathOperationID,
        location: "routes.logicalPath"
      ))
    }

    appendRouteCollisionDiagnostics(routeCandidates, to: &diagnostics)
    appendOperationIDDiagnostics(operationIDCandidates, to: &diagnostics)

    // No partial plan escapes when startup configuration is invalid.
    if diagnostics.isEmpty == false {
      throw EndpointPlanCompilationError(diagnostics: sortedDiagnostics(diagnostics))
    }

    return EndpointPlan(
      serverConfigVersion: configuration.serverConfigVersion,
      resources: plannedResources.sorted(by: resourceOrder),
      routes: routeCandidates.map(\.description).sorted(by: routeOrder)
    )
  }

  /// Validates public route values decoded independently from an ``EndpointPlan``.
  static func isSafeRouteTemplate(_ route: String) -> Bool {
    if route == logicalPathRoute { return true }
    let base = route.hasSuffix("/{id}") ? String(route.dropLast(5)) : route
    return isSafeResourceRoute(base) && (route == base || route == base + "/{id}")
  }

  /// Enforces the literal resource-route subset shared by future transport adapters.
  private static func isSafeResourceRoute(_ route: String) -> Bool {
    guard route.hasPrefix("/"),
          route != "/",
          route.hasSuffix("/") == false,
          route.contains("//") == false,
          route.contains("\\") == false,
          route.contains("?") == false,
          route.contains("#") == false,
          route.contains("*") == false,
          route.contains("{") == false,
          route.contains("}") == false,
          route.contains(":") == false,
          route.contains("%") == false,
          route.unicodeScalars.allSatisfy({ scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar) == false
              && CharacterSet.controlCharacters.contains(scalar) == false
          })
    else { return false }

    return route.dropFirst().split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
      $0.isEmpty == false && $0 != "." && $0 != ".."
    }
  }

  /// Converts an authored route into a validated plan value and reserves internal paths.
  private func validatedResourceRoute(
    _ rawValue: String,
    location: String,
    diagnostics: inout [EndpointPlanDiagnostic]
  ) -> EndpointRoutePath? {
    guard Self.isSafeResourceRoute(rawValue) else {
      diagnostics.append(EndpointPlanDiagnostic(
        code: .unsafeRoute,
        location: "\(location).route",
        message: "Route \"\(rawValue)\" must be an absolute literal path without unsafe or ambiguous components"
      ))
      return nil
    }
    guard rawValue != "/_md-utils", rawValue.hasPrefix("/_md-utils/") == false else {
      diagnostics.append(EndpointPlanDiagnostic(
        code: .reservedRoute,
        location: "\(location).route",
        message: "The /_md-utils route namespace is reserved"
      ))
      return nil
    }
    return EndpointRoutePath(validated: rawValue)
  }

  /// Resolves one selection without collapsing the three membership semantics.
  private func validatedSelection(
    _ selection: MarkdownResourceSelection,
    location: String,
    diagnostics: inout [EndpointPlanDiagnostic]
  ) -> PlannedResourceSelection? {
    switch selection {
    case .rule(let name):
      guard validateRule(name, location: "\(location).selection.rule", diagnostics: &diagnostics) else {
        return nil
      }
      return .rule(name: name)
    case .type(let name, let rawSearchRoot):
      let typeIsValid = validateType(
        name,
        location: "\(location).selection.type",
        diagnostics: &diagnostics
      )
      let searchRoot = MarkdownSearchRoot(rawValue: rawSearchRoot)
      if searchRoot == nil {
        diagnostics.append(EndpointPlanDiagnostic(
          code: .invalidSearchRoot,
          location: "\(location).selection.searchRoot",
          message: "Search root \"\(rawSearchRoot)\" must be . or a collection-relative directory ending in /"
        ))
      }
      guard typeIsValid, let searchRoot else { return nil }
      return .type(name: name, searchRoot: searchRoot)
    case .ruleWithExpectedType(let rule, let expectedType):
      let ruleIsValid = validateRule(
        rule,
        location: "\(location).selection.rule",
        diagnostics: &diagnostics
      )
      let typeIsValid = validateType(
        expectedType,
        location: "\(location).selection.type",
        diagnostics: &diagnostics
      )
      guard ruleIsValid, typeIsValid else { return nil }
      return .ruleWithExpectedType(rule: rule, expectedType: expectedType)
    }
  }

  /// Confirms that a rule reference resolves to exactly one supplied definition.
  private func validateRule(
    _ name: String,
    location: String,
    diagnostics: inout [EndpointPlanDiagnostic]
  ) -> Bool {
    let matches = rules.enumerated().filter { $0.element.name == name }
    if matches.isEmpty {
      diagnostics.append(EndpointPlanDiagnostic(
        code: .missingRule,
        location: location,
        message: "Referenced rule \"\(name)\" was not loaded"
      ))
      return false
    }
    if matches.count > 1 {
      diagnostics.append(EndpointPlanDiagnostic(
        code: .ambiguousRule,
        location: location,
        message: "Referenced rule \"\(name)\" is defined more than once",
        conflictingLocations: matches.map { "rules[\($0.offset)]" }
      ))
      return false
    }
    return true
  }

  /// Confirms that an mdtype reference exists in the already validated registry.
  private func validateType(
    _ name: MarkdownTypeName,
    location: String,
    diagnostics: inout [EndpointPlanDiagnostic]
  ) -> Bool {
    guard typeRegistry.definition(named: name) != nil else {
      diagnostics.append(EndpointPlanDiagnostic(
        code: .missingType,
        location: location,
        message: "Referenced Markdown type \"\(name.rawValue)\" was not loaded"
      ))
      return false
    }
    return true
  }

  /// Validates explicit IDs and creates the per-resource override lookup.
  private func validatedOverrides(
    _ overrides: [MarkdownOperationIDOverride],
    configuredOperations: Set<MarkdownResourceOperation>,
    location: String,
    diagnostics: inout [EndpointPlanDiagnostic]
  ) -> (values: [MarkdownResourceOperation: String], valid: Bool) {
    var values: [MarkdownResourceOperation: String] = [:]
    var valid = true
    let duplicateOperations = duplicates(overrides.map(\.operation))
    for (index, override) in overrides.enumerated() {
      let overrideLocation = "\(location).operationIDOverrides[\(index)]"
      if duplicateOperations.contains(override.operation) {
        diagnostics.append(EndpointPlanDiagnostic(
          code: .duplicateOperationIDOverride,
          location: overrideLocation,
          message: "Operation \"\(override.operation.rawValue)\" has more than one operation ID override"
        ))
        valid = false
      }
      if configuredOperations.contains(override.operation) == false {
        diagnostics.append(EndpointPlanDiagnostic(
          code: .operationIDForDisabledOperation,
          location: overrideLocation,
          message: "Operation ID override targets disabled operation \"\(override.operation.rawValue)\""
        ))
        valid = false
      }
      if override.operationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        diagnostics.append(EndpointPlanDiagnostic(
          code: .invalidOperationID,
          location: "\(overrideLocation).operationID",
          message: "Operation IDs must be nonempty"
        ))
        valid = false
      }
      values[override.operation] = override.operationID
    }
    return (values, valid)
  }

  /// Finds method-compatible paths whose literal and parameter components can overlap.
  private func appendRouteCollisionDiagnostics(
    _ candidates: [RouteCandidate],
    to diagnostics: inout [EndpointPlanDiagnostic]
  ) {
    guard candidates.count > 1 else { return }
    for leftIndex in candidates.indices {
      for rightIndex in candidates.indices where rightIndex > leftIndex {
        let left = candidates[leftIndex]
        let right = candidates[rightIndex]
        guard left.description.method == right.description.method,
              routesOverlap(left.description.path.rawValue, right.description.path.rawValue)
        else { continue }
        diagnostics.append(EndpointPlanDiagnostic(
          code: .routeCollision,
          location: left.location,
          message: "Route \(left.description.method.rawValue) \(left.description.path.rawValue) overlaps another configured route",
          conflictingLocations: [right.location]
        ))
      }
    }
  }

  /// Reports every participant in a global operation-ID collision.
  private func appendOperationIDDiagnostics(
    _ candidates: [OperationIDCandidate],
    to diagnostics: inout [EndpointPlanDiagnostic]
  ) {
    let duplicateIDs = duplicates(candidates.map(\.id))
    for candidate in candidates where duplicateIDs.contains(candidate.id) {
      diagnostics.append(EndpointPlanDiagnostic(
        code: .duplicateOperationID,
        location: candidate.location,
        message: "Operation ID \"\(candidate.id)\" is used more than once",
        conflictingLocations: candidates
          .filter { $0.id == candidate.id && $0.location != candidate.location }
          .map(\.location)
          .sorted()
      ))
    }
  }

  /// Determines whether two supported path templates can match a common request path.
  private func routesOverlap(_ left: String, _ right: String) -> Bool {
    let leftComponents = left.split(separator: "/").map(String.init)
    let rightComponents = right.split(separator: "/").map(String.init)
    if leftComponents.last == "{path...}" {
      let prefix = leftComponents.dropLast()
      guard rightComponents.count >= prefix.count else { return false }
      return zip(prefix, rightComponents.prefix(prefix.count)).allSatisfy {
        componentsOverlap($0.0, $0.1)
      }
    }
    if rightComponents.last == "{path...}" {
      let prefix = rightComponents.dropLast()
      guard leftComponents.count >= prefix.count else { return false }
      return zip(leftComponents.prefix(prefix.count), prefix).allSatisfy {
        componentsOverlap($0.0, $0.1)
      }
    }
    guard leftComponents.count == rightComponents.count else { return false }
    return zip(leftComponents, rightComponents).allSatisfy { componentsOverlap($0.0, $0.1) }
  }

  /// Treats a generated parameter component as overlapping any literal component.
  private func componentsOverlap(_ left: String, _ right: String) -> Bool {
    left == right || left.hasPrefix("{") || right.hasPrefix("{")
  }

  /// Returns values that occur more than once without depending on their input order.
  private func duplicates<Value: Hashable>(_ values: [Value]) -> Set<Value> {
    var seen: Set<Value> = []
    var duplicateValues: Set<Value> = []
    for value in values where seen.insert(value).inserted == false {
      duplicateValues.insert(value)
    }
    return duplicateValues
  }

  /// Locates every other resource that uses a duplicate case-sensitive name.
  private func resourceLocations(
    named name: String,
    in resources: [MarkdownResourceConfiguration],
    excluding excludedIndex: Int,
    suffix: String
  ) -> [String] {
    resources.enumerated().compactMap { index, resource in
      index != excludedIndex && resource.name == name ? "resources[\(index)]\(suffix)" : nil
    }
  }

  /// Gives diagnostics a stable code, location, and message order.
  private func sortedDiagnostics(_ diagnostics: [EndpointPlanDiagnostic]) -> [EndpointPlanDiagnostic] {
    diagnostics.sorted { left, right in
      if left.code.rawValue != right.code.rawValue { return left.code.rawValue < right.code.rawValue }
      if left.location != right.location { return left.location < right.location }
      return left.message < right.message
    }
  }

  /// Orders planned resources by route and then stable name.
  private func resourceOrder(_ left: PlannedMarkdownResource, _ right: PlannedMarkdownResource) -> Bool {
    if left.route.rawValue != right.route.rawValue { return left.route.rawValue < right.route.rawValue }
    return left.name < right.name
  }

  /// Orders routes by path, method, and operation ID for deterministic consumers.
  private func routeOrder(_ left: EndpointRouteDescription, _ right: EndpointRouteDescription) -> Bool {
    if left.path.rawValue != right.path.rawValue { return left.path.rawValue < right.path.rawValue }
    if left.method.rawValue != right.method.rawValue { return left.method.rawValue < right.method.rawValue }
    return left.operationID < right.operationID
  }
}

/// Internal route plus its source location, retained until collision validation completes.
private struct RouteCandidate {
  /// Transport-neutral route proposed by one configured operation.
  let description: EndpointRouteDescription
  /// Configuration location used when reporting an overlap.
  let location: String
}

/// Internal operation identifier plus its source location.
private struct OperationIDCandidate {
  /// Derived or overridden operation identifier.
  let id: String
  /// Configuration location used when reporting a duplicate.
  let location: String
}
