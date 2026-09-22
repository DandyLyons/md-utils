import Foundation

/// The caller explicitly opts out of preserving other currently passing contracts.
public enum ResourceMutationValidationPolicy: String, Codable, Equatable, Sendable {
  case preserveExistingConformance
  case endpointOnly
}

/// Destination requirements supplied by a configured resource, not by request data.
public struct ResourceMutationRequirements: Sendable {
  public let rule: String?
  public let type: MarkdownTypeName?
  public let searchRoot: String

  public init(rule: String? = nil, type: MarkdownTypeName? = nil, searchRoot: String = ".") {
    self.rule = rule
    self.type = type
    self.searchRoot = searchRoot
  }
}

/// One loaded contract's before/after evidence, including unexposed definitions.
public struct ResourceConformanceChange: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case type, rule }
  public let kind: Kind
  public let name: String
  public let previouslyPassed: Bool
  public let passes: Bool
  public let previouslySelected: Bool
  public let selected: Bool
  public let diagnostics: [MarkdownDiagnostic]
}

/// A validation decision. The complete proposal remains available for previews.
public struct ResourceMutationValidation: Sendable {
  public let proposal: ResourceMutationProposal
  public let policy: ResourceMutationValidationPolicy
  /// Blocking errors and destination advisories. Fix-its are proposals only.
  public let diagnostics: [MarkdownDiagnostic]
  public let changes: [ResourceConformanceChange]
  public var isValid: Bool { !diagnostics.contains { $0.severity == .error } }
  public var lostConformance: [ResourceConformanceChange] {
    changes.filter { $0.previouslyPassed && !$0.passes }
  }
  public var lostMembership: [ResourceConformanceChange] {
    changes.filter { $0.previouslySelected && !$0.selected }
  }
}

/// Assesses before/after source against one immutable collection registry snapshot.
/// No cache, persistence, HTTP, or automatic repair is involved.
public struct ResourceMutationValidator: Sendable {
  public let types: MarkdownTypeRegistry
  public let rules: MarkdownRuleRegistry

  public init(types: MarkdownTypeRegistry, rules: MarkdownRuleRegistry) {
    self.types = types
    self.rules = rules
  }

  public func validate(
    _ proposal: ResourceMutationProposal,
    destination: ResourceMutationRequirements,
    policy: ResourceMutationValidationPolicy = .preserveExistingConformance
  ) async throws -> ResourceMutationValidation {
    if let ruleTypes = rules.typeRegistry {
      guard ruleTypes.definitions == types.definitions,
            types.definitions.allSatisfy({
              ruleTypes.resolvedFrontmatterSchema(for: $0.name) == types.resolvedFrontmatterSchema(for: $0.name)
            }) else {
        throw ResourceCodecError("registry", "Rule and type assessment must use the same collection type definitions and schemas.")
      }
    }
    guard destination.rule != nil || destination.type != nil else {
      throw ResourceCodecError("destination", "A destination rule or type is required.")
    }
    if let type = destination.type, types.definition(named: type) == nil {
      throw ResourceCodecError("destination", "Unknown destination type: \(type.rawValue)")
    }
    if let rule = destination.rule, rules.rule(named: rule) == nil {
      throw ResourceCodecError("destination", "Unknown destination rule: \(rule)")
    }
    try Task.checkCancellation()
    let after = await MarkdownRecordAnalyzer.analyze(proposal.record)
    let before: AnalyzedMarkdownRecord?
    if let original = proposal.original {
      before = await MarkdownRecordAnalyzer.analyze(original)
    } else { before = nil }
    var diagnostics = after.parseDiagnostics
    // Failure to establish the baseline must not silently weaken preservation.
    diagnostics.append(contentsOf: before?.parseDiagnostics ?? [])
    var changes: [ResourceConformanceChange] = []
    let typeChecker = MarkdownTypeChecker(registry: types)
    for definition in types.definitions {
      try Task.checkCancellation()
      let old = try before.map { try typeChecker.assess($0, as: definition.name) }
      let new = try typeChecker.assess(after, as: definition.name)
      let change = ResourceConformanceChange(kind: .type, name: definition.name.rawValue,
        previouslyPassed: old?.conforms ?? false, passes: new.conforms,
        previouslySelected: old?.conforms ?? false, selected: new.conforms, diagnostics: new.diagnostics)
      changes.append(change)
      diagnostics.append(contentsOf: evaluationErrors(old?.diagnostics ?? []))
      diagnostics.append(contentsOf: evaluationErrors(new.diagnostics))
      if definition.name == destination.type || (policy == .preserveExistingConformance && change.previouslyPassed) {
        diagnostics.append(contentsOf: new.diagnostics)
        if !new.conforms { diagnostics.append(failure("type", definition.name.rawValue)) }
      }
    }
    let ruleChecker = MarkdownRuleChecker(registry: rules)
    for definition in rules.definitions {
      try Task.checkCancellation()
      guard let rule = rules.rule(named: definition.name) else { continue }
      let old = try before.map { try ruleChecker.assess($0, against: rule) }
      let new = try ruleChecker.assess(after, against: rule)
      let change = ResourceConformanceChange(kind: .rule, name: definition.name,
        previouslyPassed: old.map { $0.applicable && $0.passes } ?? false,
        passes: new.applicable && new.passes,
        previouslySelected: old?.applicable ?? false, selected: new.applicable,
        diagnostics: new.applicabilityDiagnostics + new.diagnostics)
      changes.append(change)
      diagnostics.append(contentsOf: old?.applicabilityDiagnostics ?? [])
      diagnostics.append(contentsOf: new.applicabilityDiagnostics)
      diagnostics.append(contentsOf: evaluationErrors(old?.diagnostics ?? []))
      diagnostics.append(contentsOf: evaluationErrors(new.diagnostics))
      if old?.typeExpressionAssessment?.status == .unavailable || new.typeExpressionAssessment?.status == .unavailable {
        diagnostics.append(failure("evaluation", definition.name))
      }
      if definition.name == destination.rule || (policy == .preserveExistingConformance && change.previouslyPassed) {
        diagnostics.append(contentsOf: change.diagnostics)
        if !change.passes { diagnostics.append(failure("rule", definition.name)) }
      }
    }
    if destination.searchRoot != "." {
      guard destination.searchRoot.hasSuffix("/"),
            let path = proposal.record.context.path,
            path.rawValue.hasPrefix(destination.searchRoot) else {
        diagnostics.append(failure("selection", "destination search root"))
        return ResourceMutationValidation(proposal: proposal, policy: policy,
          diagnostics: unique(diagnostics), changes: changes)
      }
    }
    return ResourceMutationValidation(proposal: proposal, policy: policy,
      diagnostics: unique(diagnostics), changes: changes)
  }

  private func failure(_ kind: String, _ name: String) -> MarkdownDiagnostic {
    MarkdownDiagnostic(code: "resource.validation.\(kind)", severity: .error, domain: .record,
      location: "\(kind).\(name)", message: "Proposed record must remain selected and pass \(kind) \"\(name)\".")
  }

  private func evaluationErrors(_ diagnostics: [MarkdownDiagnostic]) -> [MarkdownDiagnostic] {
    diagnostics.filter {
      $0.code.hasSuffix("engine-error") || $0.code.hasSuffix("schema-engine")
        || $0.code.hasSuffix("unavailable") || $0.code.hasSuffix("unsupported")
    }
  }

  private func unique(_ diagnostics: [MarkdownDiagnostic]) -> [MarkdownDiagnostic] {
    diagnostics.reduce(into: []) { result, diagnostic in
      if !result.contains(diagnostic) { result.append(diagnostic) }
    }
  }
}
