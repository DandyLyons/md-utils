import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndexNative
import MarkdownUtilitiesServer

/// Shared source planning, projection, and constraints for REST and offline drafts.
struct NativeEditPlanning: Sendable {
  let plan: EndpointPlan
  let evaluator: IndexProjectEvaluator

  func project(_ record: MarkdownRecord) async throws -> GenericMarkdownRecord? {
    let snapshot = try await MarkdownServerReadSnapshotBuilder(store: SingleRecordStore(record: record),
      plan: plan, ruleRegistry: evaluator.rules ?? MarkdownRuleCompiler().compile([]),
      typeRegistry: evaluator.types).build()
    return snapshot.resources.lazy.compactMap { $0.records.first }.first
  }

  func edit(_ request: MarkdownMutationRequest, source: ResourceMutationSource,
    resource: PlannedMarkdownResource,
  ) async throws -> ResourceMutationValidation {
    guard resource.mutations?.operations.contains(request.operation) == true else {
      throw MarkdownMutationError(405, "operation.disabled", "This resource does not enable the requested mutation.")
    }
    guard try await project(source.record)?.memberships.contains(where: { $0.resourceName == resource.name }) == true else {
      throw MarkdownMutationError(404, "record.not-found", "The resource does not select this document.")
    }
    var context = source.record.context
    context.modificationDate = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    let planner = ResourceMutationPlanner(types: evaluator.types,
      rules: try evaluator.rules ?? MarkdownRuleCompiler().compile([]))
    let validation = try await planner.plan(request.edit(), source: source, resource: resource,
      policy: request.validationPolicy, proposedContext: context)
    guard validation.proposal.record.content.utf8.count <= 8 * 1024 * 1024 else {
      throw MarkdownMutationError(413, "record.too-large", "Proposed source exceeds 8 MiB.")
    }
    let before = await MarkdownRecordAnalyzer.analyze(source.record)
    let after = await MarkdownRecordAnalyzer.analyze(validation.proposal.record)
    let beforeProjection = try await project(source.record)
    let afterProjection = try await project(validation.proposal.record)
    let memberships = Set((beforeProjection?.memberships ?? []).map(\.resourceName)
      + (afterProjection?.memberships ?? []).map(\.resourceName))
    try FileEditPolicy(revision: source.record.revision, memberships: memberships, plan: plan,
      contracts: validation.changes).validate(before: before.userFrontmatter ?? [:], after: after.userFrontmatter ?? [:])
    return validation
  }

  struct Constraint: Sendable {
    let resource: String
    let policy: MarkdownRecordIdentityPolicy
    let value: String
    let server: Bool
  }

  func constraints(_ proposed: MarkdownRecord, projection: GenericMarkdownRecord?) async throws -> [Constraint] {
    let analyzed = await MarkdownRecordAnalyzer.analyze(proposed)
    let selected = Set(projection?.memberships.map(\.resourceName) ?? [])
    var checks: [Constraint] = []
    for resource in plan.resources {
      if selected.contains(resource.name) {
        let primary = MarkdownRecordIdentityIndex.assess(analyzed, policy: resource.identityPolicy)
        guard let value = primary.primaryIdentity?.rawValue else {
          throw MarkdownMutationError(422, "identity.invalid", "The proposed primary identity is missing or invalid.")
        }
        checks.append(.init(resource: resource.name, policy: resource.identityPolicy, value: value, server: false))
      }
      for lookup in resource.assessmentLookups(persistentIdentity: plan.persistentIdentity) {
        let constraint = resource.constraint(for: lookup)
        guard selected.contains(resource.name) || constraint.uniqueWithin == .server,
          let policy = lookup.policy(persistentIdentity: plan.persistentIdentity) else { continue }
        let value = MarkdownRecordIdentityIndex.assess(analyzed, policy: policy)
        if (value.status == .invalid && (selected.contains(resource.name) || lookup.source == .persistentIdentity))
          || (value.primaryIdentity == nil && constraint.requireValue && selected.contains(resource.name)) {
          throw MarkdownMutationError(422, "identity.invalid", "The proposed lookup \(lookup.name) violates its format or required-value constraint.")
        }
        if let scope = constraint.uniqueWithin, let key = value.primaryIdentity?.rawValue {
          checks.append(.init(resource: resource.name, policy: policy, value: key, server: scope == .server))
        }
      }
    }
    return checks
  }

  func validateOther(_ other: MarkdownRecord, checks: [Constraint]) async throws {
    guard !checks.isEmpty else { return }
    let analyzed = await MarkdownRecordAnalyzer.analyze(other)
    if analyzed.parseDiagnostics.contains(where: { $0.severity == .error }) {
      throw MarkdownMutationError(503, "identity.incomplete", "A collection document cannot be assessed; repair its parse diagnostics before enforcing uniqueness.")
    }
    let memberships = try await project(other)?.memberships ?? []
    for check in checks where check.server || memberships.contains(where: { $0.resourceName == check.resource }) {
      if MarkdownRecordIdentityIndex.assess(analyzed, policy: check.policy).primaryIdentity?.rawValue == check.value {
        let location: String
        if case .frontmatter(let path, _) = check.policy.source { location = "frontmatter." + path.joined(separator: ".") }
        else { location = "identity" }
        throw MarkdownMutationError(409, "identity.collision", "The proposal violates a configured identity uniqueness scope.",
          diagnostics: [.init(code: "identity.collision", severity: .error, domain: .record,
            location: location, message: "A value already exists in the configured uniqueness scope.")])
      }
    }
  }
}
