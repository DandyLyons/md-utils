import MarkdownUtilitiesCore
import MarkdownUtilitiesTemplates

/// Connects explicit endpoint configuration to shared planning and validation.
/// This service neither reads a store nor persists a proposal.
public struct ResourceMutationPlanner: Sendable {
  public let validator: ResourceMutationValidator

  public init(types: MarkdownTypeRegistry, rules: MarkdownRuleRegistry) {
    validator = ResourceMutationValidator(types: types, rules: rules)
  }

  public func plan(
    _ edit: ResourceEdit,
    source: ResourceMutationSource,
    resource: PlannedMarkdownResource,
    policy: ResourceMutationValidationPolicy = .preserveExistingConformance
  ) async throws -> ResourceMutationValidation {
    let codec = try codec(for: resource)
    let proposal = try codec.plan(edit, source: source)
    return try await validator.validate(proposal, destination: requirements(for: resource), policy: policy)
  }

  /// Host-selected identity, context, and protected metadata are separate from client inputs.
  public func planCreation(
    input: MarkdownTemplateInput,
    identity: MarkdownRecordIdentity,
    context: MarkdownRecordContext = .init(),
    protectedFrontmatter: [String: JSONValue] = [:],
    resource: PlannedMarkdownResource
  ) async throws -> ResourceMutationValidation {
    let codec = try codec(for: resource)
    guard let template = resource.writable?.creation else {
      throw ResourceCodecError("creation-disabled", "The resource has no creation template.")
    }
    let proposal = try await TemplateResourceCreationCodec(codec: codec, template: template).plan(
      input: input, identity: identity, context: context, protectedFrontmatter: protectedFrontmatter)
    return try await validator.validate(proposal, destination: requirements(for: resource))
  }

  private func codec(for resource: PlannedMarkdownResource) throws -> MarkdownResourceCodec {
    guard let writable = resource.writable else {
      throw ResourceCodecError("read-only", "The resource does not declare a writable codec.")
    }
    var protected = writable.codec.protectedFields
    if case .frontmatter(let path, _) = resource.identityPolicy.source, let field = path.first {
      protected.append(field)
    }
    return try MarkdownResourceCodec(configuration: ResourceCodecConfiguration(
      frontmatterFields: writable.codec.frontmatterFields,
      bodyWritable: writable.codec.bodyWritable, protectedFields: protected))
  }

  private func requirements(for resource: PlannedMarkdownResource) -> ResourceMutationRequirements {
    switch resource.selection {
    case .rule(let name): return .init(rule: name)
    case .type(let name, let root): return .init(type: name, searchRoot: root.rawValue)
    case .ruleWithExpectedType(let rule, let type): return .init(rule: rule, type: type)
    }
  }
}
