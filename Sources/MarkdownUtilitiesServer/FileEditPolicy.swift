import MarkdownUtilitiesCore

/// Revision-bound, derived restrictions. Users do not author per-file policies.
public struct FileEditPolicy: Sendable {
  public let revision: MarkdownRecordRevision?
  public let protectedFields: [String: [String]]
  public let contracts: [ResourceConformanceChange]

  public init(revision: MarkdownRecordRevision?, memberships: Set<String>, plan: EndpointPlan,
    contracts: [ResourceConformanceChange],
  ) {
    self.revision = revision; self.contracts = contracts
    var origins: [String: [String]] = [:]
    for resource in plan.resources where memberships.contains(resource.name) {
      for field in resource.protectedIdentityFields(persistentIdentity: plan.persistentIdentity) {
        origins[field, default: []].append("resource.\(resource.name).identity")
      }
      for field in resource.writable?.codec.protectedFields ?? [] {
        origins[field, default: []].append("resource.\(resource.name).codec")
      }
    }
    if let field = plan.persistentIdentity?.path.first {
      origins[field, default: []].append("server.persistentIdentity")
    }
    protectedFields = origins
  }

  public func validate(before: [String: JSONValue], after: [String: JSONValue],
    explicitlyEditing: Set<String> = [],
  ) throws {
    for field in protectedFields.keys.sorted() where !explicitlyEditing.contains(field) && before[field] != after[field] {
      throw MarkdownMutationError(422, "identity.protected", "\(field) is protected by \((protectedFields[field] ?? []).joined(separator: ", ")).")
    }
  }
}
