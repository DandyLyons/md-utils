import Foundation
import MarkdownUtilitiesCore

/// The subsystem that produced a generic record diagnostic.
public enum MarkdownServerRecordDiagnosticSource: String, Codable, Equatable, Sendable {
  /// Frontmatter or Markdown parsing produced the diagnostic.
  case parsing
  /// Configured identity assessment produced the diagnostic.
  case identity
  /// Rule applicability or checking produced the diagnostic.
  case rule
  /// Markdown type assessment produced the diagnostic.
  case type
}

/// One JSON-ready diagnostic associated with a generic Markdown record.
public struct MarkdownServerRecordDiagnostic: Codable, Equatable, Sendable {
  /// Stable machine-readable diagnostic code.
  public let code: String
  /// Whether the diagnostic invalidates its associated assessment.
  public let severity: MarkdownDiagnosticSeverity
  /// Subsystem that produced the diagnostic.
  public let source: MarkdownServerRecordDiagnosticSource
  /// Record location or field associated with the problem.
  public let location: String
  /// Human-readable explanation suitable for clients and logs.
  public let message: String
  /// Constraint that produced the diagnostic, when applicable.
  public let constraintID: String?
  /// Rule associated with the diagnostic, when applicable.
  public let ruleName: String?
  /// Markdown type associated with the diagnostic, when applicable.
  public let typeName: MarkdownTypeName?
  /// Colliding or invalid identity associated with the diagnostic, when available.
  public let identity: MarkdownRecordIdentity?
  /// Logical paths participating in an identity diagnostic.
  public let paths: [MarkdownRecordPath]

  /// Creates a normalized server diagnostic.
  public init(
    code: String,
    severity: MarkdownDiagnosticSeverity,
    source: MarkdownServerRecordDiagnosticSource,
    location: String,
    message: String,
    constraintID: String? = nil,
    ruleName: String? = nil,
    typeName: MarkdownTypeName? = nil,
    identity: MarkdownRecordIdentity? = nil,
    paths: [MarkdownRecordPath] = []
  ) {
    self.code = code
    self.severity = severity
    self.source = source
    self.location = location
    self.message = message
    self.constraintID = constraintID
    self.ruleName = ruleName
    self.typeName = typeName
    self.identity = identity
    self.paths = paths
  }
}

/// Compact conformance information for one loaded Markdown type.
public struct GenericMarkdownTypeAssessment: Codable, Equatable, Sendable {
  /// Stable type name.
  public let name: MarkdownTypeName
  /// Contract version used for assessment.
  public let version: String
  /// Whether every required constraint passed.
  public let conforms: Bool

  /// Creates a JSON-ready type assessment summary.
  public init(name: MarkdownTypeName, version: String, conforms: Bool) {
    self.name = name
    self.version = version
    self.conforms = conforms
  }
}

/// Compact checking information for the rule that selected a resource member.
public struct GenericMarkdownRuleAssessment: Codable, Equatable, Sendable {
  /// Stable configured rule name.
  public let name: String
  /// Whether the rule selected the record.
  public let applicable: Bool
  /// Whether all required checks passed after selection.
  public let passes: Bool

  /// Creates a JSON-ready rule assessment summary.
  public init(name: String, applicable: Bool, passes: Bool) {
    self.name = name
    self.applicable = applicable
    self.passes = passes
  }
}

/// Selection mode recorded for one resource membership.
public enum GenericMarkdownResourceSelectionMode: String, Codable, Equatable, Sendable {
  /// Rule applicability selected the record.
  case rule
  /// Markdown type conformance selected the record.
  case type
  /// Rule applicability selected the record and a type supplied additional validity.
  case ruleWithExpectedType
}

/// One configured resource through which a canonical record is visible.
public struct GenericMarkdownResourceMembership: Codable, Equatable, Sendable {
  /// Stable resource name from the endpoint plan.
  public let resourceName: String
  /// Selection behavior that admitted the record.
  public let selectionMode: GenericMarkdownResourceSelectionMode
  /// Primary identity derived under this resource's identity policy.
  public let identity: MarkdownRecordIdentity?
  /// Collection-wide status of the resource-derived identity.
  public let identityStatus: MarkdownRecordIdentityStatus
  /// Selecting rule and its check result, when rule selection was configured.
  public let ruleAssessment: GenericMarkdownRuleAssessment?
  /// Expected or selected type, when the mode declares one.
  public let selectedType: MarkdownTypeName?
  /// All loaded type memberships, preserving non-exclusive conformance.
  public let assessedTypes: [GenericMarkdownTypeAssessment]
  /// Whether this record satisfies the resource's rule and type requirements.
  public let valid: Bool

  /// Creates resource-local membership metadata for a generic record.
  public init(
    resourceName: String,
    selectionMode: GenericMarkdownResourceSelectionMode,
    identity: MarkdownRecordIdentity?,
    identityStatus: MarkdownRecordIdentityStatus,
    ruleAssessment: GenericMarkdownRuleAssessment?,
    selectedType: MarkdownTypeName?,
    assessedTypes: [GenericMarkdownTypeAssessment],
    valid: Bool
  ) {
    self.resourceName = resourceName
    self.selectionMode = selectionMode
    self.identity = identity
    self.identityStatus = identityStatus
    self.ruleAssessment = ruleAssessment
    self.selectedType = selectedType
    self.assessedTypes = assessedTypes
    self.valid = valid
  }
}

/// Generic JSON representation of one canonical Markdown record in a read snapshot.
///
/// Membership is many-to-many: one value can list several resources without copying
/// canonical content or changing its revision. See <doc:ReadSnapshots> for the full model.
public struct GenericMarkdownRecord: Codable, Equatable, Sendable {
  /// Store-supplied canonical identity, when the record has one.
  public let canonicalIdentity: MarkdownRecordIdentity?
  /// Collection-wide status of the canonical store identity.
  public let identityStatus: MarkdownRecordIdentityStatus
  /// Collection-relative logical path, when supplied by the store.
  public let logicalPath: MarkdownRecordPath?
  /// Opaque store-owned revision, when available.
  public let revision: MarkdownRecordRevision?
  /// Every configured resource that selected this canonical record.
  public let memberships: [GenericMarkdownResourceMembership]
  /// Whether all resource memberships represented by this envelope are valid.
  public let valid: Bool
  /// Schema-visible YAML frontmatter, excluding reserved system metadata.
  public let frontmatter: [String: JSONValue]?
  /// Markdown body with a safely separated frontmatter block removed.
  public let body: String
  /// Deterministically ordered parse, identity, rule, and type diagnostics.
  public let diagnostics: [MarkdownServerRecordDiagnostic]

  /// Creates a generic immutable record representation.
  public init(
    canonicalIdentity: MarkdownRecordIdentity?,
    identityStatus: MarkdownRecordIdentityStatus,
    logicalPath: MarkdownRecordPath?,
    revision: MarkdownRecordRevision?,
    memberships: [GenericMarkdownResourceMembership],
    valid: Bool,
    frontmatter: [String: JSONValue]?,
    body: String,
    diagnostics: [MarkdownServerRecordDiagnostic]
  ) {
    self.canonicalIdentity = canonicalIdentity
    self.identityStatus = identityStatus
    self.logicalPath = logicalPath
    self.revision = revision
    self.memberships = memberships
    self.valid = valid
    self.frontmatter = frontmatter
    self.body = body
    self.diagnostics = diagnostics
  }
}

/// Every candidate associated with an ambiguous read-snapshot lookup.
public struct MarkdownServerReadConflict: Codable, Equatable, Sendable {
  /// Records sharing the requested primary identity or logical path.
  public let candidates: [GenericMarkdownRecord]

  /// Creates a conflict that retains every ambiguous record.
  public init(candidates: [GenericMarkdownRecord]) {
    self.candidates = candidates
  }
}

/// Exhaustive result of collision-safe primary identity or logical-path lookup.
public enum MarkdownServerReadLookupResult: Codable, Equatable, Sendable {
  /// No selected record has the requested lookup key.
  case notFound
  /// Exactly one canonical record has the requested lookup key.
  case record(GenericMarkdownRecord)
  /// Several canonical records have the requested lookup key.
  case conflict(MarkdownServerReadConflict)
}

/// Immutable collection and primary-identity index for one planned resource.
public struct MarkdownResourceReadSnapshot: Equatable, Sendable {
  /// Stable resource name from the endpoint plan.
  public let name: String
  /// Selected records in deterministic store order.
  public let records: [GenericMarkdownRecord]

  private let primaryLookup: [MarkdownRecordIdentity: [Int]]

  /// Looks up one resource member without selecting an arbitrary collision candidate.
  public func lookup(primary identity: MarkdownRecordIdentity) -> MarkdownServerReadLookupResult {
    lookupResult(indexes: primaryLookup[identity] ?? [], records: records)
  }

  /// Creates a resource view after the builder has completed identity assessment.
  package init(
    name: String,
    records: [GenericMarkdownRecord],
    primaryLookup: [MarkdownRecordIdentity: [Int]]
  ) {
    self.name = name
    self.records = records
    self.primaryLookup = primaryLookup
  }
}

/// Immutable read-side state shared safely by concurrent server requests.
///
/// The snapshot contains no store handle and performs no parsing during lookup.
/// See <doc:ReadSnapshots> for construction and selection semantics.
public struct MarkdownServerReadSnapshot: Equatable, Sendable {
  /// Resource views in deterministic endpoint-plan order.
  public let resources: [MarkdownResourceReadSnapshot]

  private let logicalPathLookup: [MarkdownRecordPath: [Int]]
  private let canonicalRecords: [GenericMarkdownRecord]

  /// Returns the immutable view for a configured resource.
  public func resource(named name: String) -> MarkdownResourceReadSnapshot? {
    resources.first { $0.name == name }
  }

  /// Looks up a canonical record through the server-wide logical-path namespace.
  public func lookup(logicalPath path: MarkdownRecordPath) -> MarkdownServerReadLookupResult {
    lookupResult(indexes: logicalPathLookup[path] ?? [], records: canonicalRecords)
  }

  /// Creates the final snapshot after all resource indexes have been assembled.
  package init(
    resources: [MarkdownResourceReadSnapshot],
    canonicalRecords: [GenericMarkdownRecord],
    logicalPathLookup: [MarkdownRecordPath: [Int]]
  ) {
    self.resources = resources
    self.canonicalRecords = canonicalRecords
    self.logicalPathLookup = logicalPathLookup
  }
}

/// Startup failures detected while composing a read snapshot from validated inputs.
public enum MarkdownServerReadSnapshotBuildError: Error, Equatable, Sendable, LocalizedError {
  /// The plan references a rule absent from the supplied definitions.
  case missingRule(String)
  /// The plan references a type absent from the supplied registry.
  case missingType(MarkdownTypeName)
  /// A store repeated a continuation token and could not make forward progress.
  case repeatedContinuationToken(RecordStoreContinuationToken)

  /// Human-readable startup failure description.
  public var errorDescription: String? {
    switch self {
    case .missingRule(let name):
      return "Endpoint plan references missing rule \"\(name)\""
    case .missingType(let name):
      return "Endpoint plan references missing Markdown type \"\(name.rawValue)\""
    case .repeatedContinuationToken(let token):
      return "Record store repeated continuation token \"\(token.rawValue)\""
    }
  }
}

/// Builds one immutable read snapshot from canonical storage and compiled server inputs.
public struct MarkdownServerReadSnapshotBuilder: Sendable {
  /// Default bounded page size used during the startup scan.
  public static let defaultPageSize = 256

  private let store: any RecordStore
  private let plan: EndpointPlan
  private let ruleRegistry: MarkdownRuleRegistry
  private let typeRegistry: MarkdownTypeRegistry
  private let pageSize: Int
  private let analyzer: @Sendable (MarkdownRecord) async -> AnalyzedMarkdownRecord

  /// Creates a snapshot builder.
  ///
  /// - Parameters:
  ///   - store: Source of canonical Markdown records.
  ///   - plan: Validated resource and route plan.
  ///   - ruleRegistry: The same compiled rule registry used to create the plan.
  ///   - typeRegistry: The same validated type registry used to create the plan.
  ///   - pageSize: Positive bound for each store enumeration request.
  /// - Throws: ``RecordStoreError/invalidQuery(_:)`` when `pageSize` is not positive.
  public init(
    store: any RecordStore,
    plan: EndpointPlan,
    ruleRegistry: MarkdownRuleRegistry,
    typeRegistry: MarkdownTypeRegistry,
    pageSize: Int = MarkdownServerReadSnapshotBuilder.defaultPageSize
  ) throws {
    _ = try RecordStoreQuery(limit: pageSize)
    self.store = store
    self.plan = plan
    self.ruleRegistry = ruleRegistry
    self.typeRegistry = typeRegistry
    self.pageSize = pageSize
    self.analyzer = { record in
      await MarkdownRecordAnalyzer.analyze(record)
    }
  }

  /// Creates a builder with an observable analyzer for package-level correctness tests.
  package init(
    store: any RecordStore,
    plan: EndpointPlan,
    ruleRegistry: MarkdownRuleRegistry,
    typeRegistry: MarkdownTypeRegistry,
    pageSize: Int,
    analyzer: @escaping @Sendable (MarkdownRecord) async -> AnalyzedMarkdownRecord
  ) throws {
    _ = try RecordStoreQuery(limit: pageSize)
    self.store = store
    self.plan = plan
    self.ruleRegistry = ruleRegistry
    self.typeRegistry = typeRegistry
    self.pageSize = pageSize
    self.analyzer = analyzer
  }

  /// Scans, assesses, and indexes records once for concurrent read access.
  ///
  /// - Returns: An immutable snapshot containing every selected resource member.
  /// - Throws: Store failures, cancellation, or ``MarkdownServerReadSnapshotBuildError``
  ///   when supplied definitions drift from the endpoint plan or paging cannot advance.
  public func build() async throws -> MarkdownServerReadSnapshot {
    let dependencies = try resolveDependencies()
    let records = try await enumerateRecords()

    // Path-only selection is deliberately separated from analysis so large stores do not
    // parse records that cannot participate in any planned resource.
    let candidates = records.filter { record in
      plan.resources.contains { resource in
        isPathCandidate(record, for: resource, dependencies: dependencies)
      }
    }

    var analyzedRecords: [AnalyzedMarkdownRecord] = []
    analyzedRecords.reserveCapacity(candidates.count)
    for record in candidates {
      try Task.checkCancellation()
      analyzedRecords.append(await analyzer(record))
    }
    try Task.checkCancellation()

    let checker = MarkdownTypeChecker(registry: typeRegistry)
    let typeAssessments = analyzedRecords.map { checker.assessAll($0) }
    let canonicalIndex = await MarkdownRecordIdentityIndex.build(
      analyzedRecords: analyzedRecords,
      policy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
    )

    var pendingMemberships = Array(repeating: [PendingMembership](), count: analyzedRecords.count)
    var resourceMembers: [[Int]] = []
    var resourcePrimaryLookups: [[MarkdownRecordIdentity: [Int]]] = []

    // Selection and identity are resource-local. Keeping their indexes separate preserves
    // overlapping membership without turning one canonical record into a collision.
    for resource in plan.resources {
      try Task.checkCancellation()
      let selection = try select(
        resource: resource,
        dependencies: dependencies,
        analyzedRecords: analyzedRecords,
        typeAssessments: typeAssessments
      )
      let selectedAnalyzed = selection.map { analyzedRecords[$0.recordIndex] }
      let identityIndex = await MarkdownRecordIdentityIndex.build(
        analyzedRecords: selectedAnalyzed,
        policy: resource.identityPolicy
      )

      var primaryLookup: [MarkdownRecordIdentity: [Int]] = [:]
      for (localIndex, selected) in selection.enumerated() {
        let identity = identityIndex.assessments[localIndex]
        pendingMemberships[selected.recordIndex].append(PendingMembership(
          resource: resource,
          ruleAssessment: selected.ruleAssessment,
          selectedTypeAssessment: selected.selectedTypeAssessment,
          allTypeAssessments: typeAssessments[selected.recordIndex],
          identityAssessment: identity,
          valid: selected.valid
        ))
        if let primary = identity.primaryIdentity {
          primaryLookup[primary, default: []].append(localIndex)
        }
      }
      resourceMembers.append(selection.map(\.recordIndex))
      resourcePrimaryLookups.append(primaryLookup)
    }

    var canonicalRecords: [GenericMarkdownRecord] = []
    var canonicalIndexes: [Int: Int] = [:]
    canonicalRecords.reserveCapacity(pendingMemberships.filter { $0.isEmpty == false }.count)
    for index in analyzedRecords.indices where pendingMemberships[index].isEmpty == false {
      canonicalIndexes[index] = canonicalRecords.count
      canonicalRecords.append(makeGenericRecord(
        analyzed: analyzedRecords[index],
        canonicalIdentity: canonicalIndex.assessments[index],
        memberships: pendingMemberships[index]
      ))
    }

    var resourceSnapshots: [MarkdownResourceReadSnapshot] = []
    for resourceIndex in plan.resources.indices {
      let canonicalMemberIndexes = resourceMembers[resourceIndex].compactMap { canonicalIndexes[$0] }
      let records = canonicalMemberIndexes.map { canonicalRecords[$0] }
      resourceSnapshots.append(MarkdownResourceReadSnapshot(
        name: plan.resources[resourceIndex].name,
        records: records,
        primaryLookup: resourcePrimaryLookups[resourceIndex]
      ))
    }

    var logicalPathLookup: [MarkdownRecordPath: [Int]] = [:]
    for (index, record) in canonicalRecords.enumerated() {
      if let path = record.logicalPath {
        logicalPathLookup[path, default: []].append(index)
      }
    }
    return MarkdownServerReadSnapshot(
      resources: resourceSnapshots,
      canonicalRecords: canonicalRecords,
      logicalPathLookup: logicalPathLookup
    )
  }

  /// Resolves plan references once and rejects composition drift before scanning storage.
  private func resolveDependencies() throws -> ResolvedDependencies {
    for resource in plan.resources {
      switch resource.selection {
      case .rule(let name):
        guard ruleRegistry.rule(named: name) != nil else {
          throw MarkdownServerReadSnapshotBuildError.missingRule(name)
        }
      case .type(let name, _):
        guard typeRegistry.definition(named: name) != nil else {
          throw MarkdownServerReadSnapshotBuildError.missingType(name)
        }
      case .ruleWithExpectedType(let rule, let expectedType):
        guard ruleRegistry.rule(named: rule) != nil else {
          throw MarkdownServerReadSnapshotBuildError.missingRule(rule)
        }
        guard typeRegistry.definition(named: expectedType) != nil else {
          throw MarkdownServerReadSnapshotBuildError.missingType(expectedType)
        }
      }
    }
    return ResolvedDependencies()
  }

  /// Enumerates the collection root in bounded pages and rejects token cycles.
  private func enumerateRecords() async throws -> [MarkdownRecord] {
    var result: [MarkdownRecord] = []
    var seenRecords: [RecordDeduplicationKey: [MarkdownRecord]] = [:]
    var continuationToken: RecordStoreContinuationToken?
    var seenTokens: Set<RecordStoreContinuationToken> = []
    repeat {
      try Task.checkCancellation()
      let page = try await store.records(matching: RecordStoreQuery(
        limit: pageSize,
        continuationToken: continuationToken
      ))
      // Exact repeated values are backend duplication, not identity collisions. Remove only
      // these repeats; distinct records sharing an identity remain available for diagnostics.
      for record in page.records {
        let key = RecordDeduplicationKey(record: record)
        guard seenRecords[key, default: []].contains(record) == false else { continue }
        seenRecords[key, default: []].append(record)
        result.append(record)
      }
      continuationToken = page.continuationToken
      if let continuationToken, seenTokens.insert(continuationToken).inserted == false {
        throw MarkdownServerReadSnapshotBuildError.repeatedContinuationToken(continuationToken)
      }
    } while continuationToken != nil
    return result
  }

  /// Applies search roots and portable path constraints without parsing content.
  private func isPathCandidate(
    _ record: MarkdownRecord,
    for resource: PlannedMarkdownResource,
    dependencies: ResolvedDependencies
  ) -> Bool {
    switch resource.selection {
    case .rule(let name):
      guard let rule = ruleRegistry.rule(named: name) else { return false }
      return rulePathCandidate(record.context.path, rule: rule)
    case .type(let name, let searchRoot):
      guard isUnderSearchRoot(record.context.path, searchRoot: searchRoot),
            let definition = typeRegistry.definition(named: name)
      else { return false }
      return requiredPathPredicates(in: definition).allSatisfy { predicate in
        record.context.path?.matches(glob: predicate.glob) == true
      }
    case .ruleWithExpectedType(let name, _):
      guard let rule = ruleRegistry.rule(named: name) else { return false }
      return rulePathCandidate(record.context.path, rule: rule)
    }
  }

  /// Combines explicit rule globs with legacy path predicates for cheap narrowing.
  private func rulePathCandidate(
    _ path: MarkdownRecordPath?,
    rule: CompiledMarkdownRule
  ) -> Bool {
    let checker = MarkdownRuleChecker(registry: ruleRegistry)
    guard checker.isPathCandidate(path, for: rule) else { return false }
    return rule.definition.applicability.requirements.allSatisfy { requirement in
      guard case .markdown(.path(let predicate)) = requirement.predicate else { return true }
      return path?.matches(glob: predicate.glob) == true
    }
  }

  /// Returns required type path predicates, excluding advisory recommendations.
  private func requiredPathPredicates(
    in definition: MarkdownTypeDefinition
  ) -> [MarkdownPathPredicate] {
    (definition.body.requirements + definition.context.requirements).compactMap { constraint in
      guard case .path(let predicate) = constraint.predicate else { return nil }
      return predicate
    }
  }

  /// Tests collection-relative search-root membership using complete path components.
  private func isUnderSearchRoot(
    _ path: MarkdownRecordPath?,
    searchRoot: MarkdownSearchRoot
  ) -> Bool {
    guard searchRoot != .collectionRoot else { return true }
    guard let path else { return false }
    return path.rawValue.hasPrefix(searchRoot.rawValue)
  }

  /// Applies one planned selection mode to shared analyses.
  private func select(
    resource: PlannedMarkdownResource,
    dependencies: ResolvedDependencies,
    analyzedRecords: [AnalyzedMarkdownRecord],
    typeAssessments: [[MarkdownTypeAssessment]]
  ) throws -> [SelectedRecord] {
    let ruleChecker = MarkdownRuleChecker(registry: ruleRegistry)
    return try analyzedRecords.indices.compactMap { index in
      let analyzed = analyzedRecords[index]
      guard isPathCandidate(
        analyzed.record,
        for: resource,
        dependencies: dependencies
      ) else { return nil }
      switch resource.selection {
      case .rule(let name):
        guard let rule = ruleRegistry.rule(named: name) else { return nil }
        let assessment = try ruleChecker.assess(analyzed, against: rule)
        guard assessment.applicable else { return nil }
        return SelectedRecord(
          recordIndex: index,
          ruleAssessment: assessment,
          selectedTypeAssessment: nil,
          valid: assessment.passes
        )
      case .type(let name, _):
        guard let assessment = typeAssessments[index].first(where: { $0.type == name }),
              assessment.conforms
        else { return nil }
        return SelectedRecord(
          recordIndex: index,
          ruleAssessment: nil,
          selectedTypeAssessment: assessment,
          valid: true
        )
      case .ruleWithExpectedType(let ruleName, let expectedType):
        guard let rule = ruleRegistry.rule(named: ruleName),
              let typeAssessment = typeAssessments[index].first(where: { $0.type == expectedType })
        else { return nil }
        let ruleAssessment = try ruleChecker.assess(analyzed, against: rule)
        guard ruleAssessment.applicable else { return nil }
        return SelectedRecord(
          recordIndex: index,
          ruleAssessment: ruleAssessment,
          selectedTypeAssessment: typeAssessment,
          valid: ruleAssessment.passes && typeAssessment.conforms
        )
      }
    }
  }

  /// Projects shared analysis and resource assessments into the generic JSON envelope.
  private func makeGenericRecord(
    analyzed: AnalyzedMarkdownRecord,
    canonicalIdentity: MarkdownRecordIdentityAssessment,
    memberships pending: [PendingMembership]
  ) -> GenericMarkdownRecord {
    let memberships = pending.map(\.publicValue)
    var diagnostics = analyzed.parseDiagnostics.map {
      normalize($0, source: .parsing)
    }
    diagnostics.append(contentsOf: canonicalIdentity.diagnostics.map(normalize))
    for membership in pending {
      diagnostics.append(contentsOf: membership.identityAssessment.diagnostics.map(normalize))
      if let rule = membership.ruleAssessment {
        diagnostics.append(contentsOf: rule.applicabilityDiagnostics.filter {
          analyzed.parseDiagnostics.contains($0) == false
        }.map {
          normalize($0, source: .rule, ruleName: rule.ruleName)
        })
        diagnostics.append(contentsOf: rule.diagnostics.filter {
          analyzed.parseDiagnostics.contains($0) == false
        }.map {
          normalize($0, source: .rule, ruleName: rule.ruleName)
        })
      }
      if let type = membership.selectedTypeAssessment {
        diagnostics.append(contentsOf: type.diagnostics.filter {
          analyzed.parseDiagnostics.contains($0) == false
        }.map {
          normalize($0, source: .type, typeName: type.type)
        })
      }
    }
    diagnostics = uniqueDiagnostics(diagnostics)
    return GenericMarkdownRecord(
      canonicalIdentity: analyzed.record.identity,
      identityStatus: canonicalIdentity.status,
      logicalPath: analyzed.record.context.path,
      revision: analyzed.record.revision,
      memberships: memberships,
      valid: memberships.allSatisfy(\.valid),
      frontmatter: analyzed.userFrontmatter,
      body: analyzed.body,
      diagnostics: diagnostics
    )
  }

  /// Converts a portable Markdown diagnostic to the stable server envelope.
  private func normalize(
    _ diagnostic: MarkdownDiagnostic,
    source: MarkdownServerRecordDiagnosticSource,
    ruleName: String? = nil,
    typeName: MarkdownTypeName? = nil
  ) -> MarkdownServerRecordDiagnostic {
    MarkdownServerRecordDiagnostic(
      code: diagnostic.code,
      severity: diagnostic.severity,
      source: source,
      location: diagnostic.location,
      message: diagnostic.message,
      constraintID: diagnostic.constraintID,
      ruleName: ruleName,
      typeName: typeName
    )
  }

  /// Converts identity diagnostics, which are always error-severity conditions.
  private func normalize(
    _ diagnostic: MarkdownRecordIdentityDiagnostic
  ) -> MarkdownServerRecordDiagnostic {
    MarkdownServerRecordDiagnostic(
      code: diagnostic.code.rawValue,
      severity: .error,
      source: .identity,
      location: diagnostic.location,
      message: diagnostic.message,
      identity: diagnostic.identity,
      paths: diagnostic.paths
    )
  }

  /// Removes repeated parse diagnostics while preserving first-observed stable order.
  private func uniqueDiagnostics(
    _ diagnostics: [MarkdownServerRecordDiagnostic]
  ) -> [MarkdownServerRecordDiagnostic] {
    var result: [MarkdownServerRecordDiagnostic] = []
    for diagnostic in diagnostics where result.contains(diagnostic) == false {
      result.append(diagnostic)
    }
    return result
  }
}

/// Resolved definitions retained for one build pass.
private struct ResolvedDependencies {}

/// Selection facts retained until resource-local identity assessment completes.
private struct SelectedRecord {
  let recordIndex: Int
  let ruleAssessment: MarkdownRuleAssessment?
  let selectedTypeAssessment: MarkdownTypeAssessment?
  let valid: Bool
}

/// Complete internal membership state used to project public summaries and diagnostics.
private struct PendingMembership {
  let resource: PlannedMarkdownResource
  let ruleAssessment: MarkdownRuleAssessment?
  let selectedTypeAssessment: MarkdownTypeAssessment?
  let allTypeAssessments: [MarkdownTypeAssessment]
  let identityAssessment: MarkdownRecordIdentityAssessment
  let valid: Bool

  /// JSON-ready membership value, excluding diagnostics normalized by the parent record.
  var publicValue: GenericMarkdownResourceMembership {
    let mode: GenericMarkdownResourceSelectionMode
    switch resource.selection {
    case .rule:
      mode = .rule
    case .type:
      mode = .type
    case .ruleWithExpectedType:
      mode = .ruleWithExpectedType
    }
    return GenericMarkdownResourceMembership(
      resourceName: resource.name,
      selectionMode: mode,
      identity: identityAssessment.primaryIdentity,
      identityStatus: identityAssessment.status,
      ruleAssessment: ruleAssessment.map {
        GenericMarkdownRuleAssessment(
          name: $0.ruleName,
          applicable: $0.applicable,
          passes: $0.passes
        )
      },
      selectedType: selectedTypeAssessment?.type,
      assessedTypes: allTypeAssessments.map {
        GenericMarkdownTypeAssessment(name: $0.type, version: $0.version, conforms: $0.conforms)
      },
      valid: valid
    )
  }
}

/// Cheap bucket key used before exact duplicate-record equality checks.
private struct RecordDeduplicationKey: Hashable {
  let identity: MarkdownRecordIdentity?
  let revision: MarkdownRecordRevision?
  let path: MarkdownRecordPath?
  let content: String

  /// Retains stable canonical fields while leaving full context comparison to `Equatable`.
  init(record: MarkdownRecord) {
    self.identity = record.identity
    self.revision = record.revision
    self.path = record.context.path
    self.content = record.content
  }
}

/// Forms an exhaustive lookup result from deterministic record indexes.
private func lookupResult(
  indexes: [Int],
  records: [GenericMarkdownRecord]
) -> MarkdownServerReadLookupResult {
  let candidates = indexes.map { records[$0] }
  if candidates.isEmpty { return .notFound }
  if let candidate = candidates.first, candidates.count == 1 { return .record(candidate) }
  return .conflict(MarkdownServerReadConflict(candidates: candidates))
}
