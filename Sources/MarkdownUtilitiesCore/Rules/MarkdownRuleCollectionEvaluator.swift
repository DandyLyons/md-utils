import Foundation

/// Collection policies are independent of structural type conformance. Hosts supply all I/O.
public struct MarkdownRuleCollectionEvaluator: Sendable {
  /// Bump when policy evaluation semantics change, invalidating native certificates.
  public static let profile = "relationship-policies-1"
  public var registry: MarkdownRuleRegistry
  public var limits: MarkdownRelationshipLimits
  public var cycleWitnessMode: MarkdownCycleWitnessMode

  public init(registry: MarkdownRuleRegistry, limits: MarkdownRelationshipLimits = .init(),
    cycleWitnessMode: MarkdownCycleWitnessMode = .perComponent,
  ) {
    self.registry = registry
    self.limits = limits
    self.cycleWitnessMode = cycleWitnessMode
  }

  public func evaluate(collection: MarkdownRelationshipCollection, ruleNames: [String]? = nil) async throws -> MarkdownRuleCollectionAssessment {
    try Task.checkCancellation()
    guard limits.policySteps > 0, limits.policies > 0 else {
      throw MarkdownRelationshipDefinition.invalid("Policy limits must be positive")
    }
    let rules = try (ruleNames ?? registry.definitions.map(\.name)).sorted().map { name in
      guard let rule = registry.rule(named: name) else { throw MarkdownRuleCheckerError.unknownRule(name) }
      return rule
    }
    guard let types = registry.typeRegistry else { throw MarkdownRelationshipDefinition.invalid("Collection evaluation requires a type registry") }
    let paths = collection.records.keys.sorted()
    var limitations = collection.limitations
    var bounded = paths.count <= limits.records
    var identities: [String: MarkdownRecord] = [:]
    for path in paths.prefix(max(0, limits.records)) {
      guard let record = collection.records[path] else { continue }
      let identity = record.identity?.rawValue ?? path
      let source = record.context.path?.rawValue ?? record.identity?.rawValue ?? "<source>"
      if source != path || identities[identity].map({ $0 != record }) == true {
        bounded = false
        limitations.append("relationship.context.unavailable: inconsistent path or identity revision at \(path)")
      }
      identities[identity] = record
    }
    let selectedPaths = Array(paths.prefix(max(0, limits.records)))
    var relationNames: [MarkdownTypeName: Set<String>] = [:]
    var extractionPolicies = 0
    for rule in rules {
      for policy in rule.definition.relationshipPolicies where !policy.isNoOp {
        extractionPolicies += 1
        if extractionPolicies > limits.policies { break }
        for ref in policy.relations {
          if let type = rule.definition.typeBindings[ref.type] { relationNames[type, default: []].insert(ref.name) }
        }
      }
    }
    let referencedTypes = Set(rules.flatMap { $0.definition.referencedTypes })
    func roots(for names: Set<MarkdownTypeName>) -> [(MarkdownRecord, MarkdownTypeName)] {
      var result: [(MarkdownRecord, MarkdownTypeName)] = []
      for path in selectedPaths {
        guard let record = collection.records[path] else { continue }
        for name in names.sorted(by: { $0.rawValue < $1.rawValue }) {
          guard result.count < limits.nodes else { bounded = false; return result }
          result.append((record, name))
        }
      }
      return result
    }
    let evaluator = MarkdownRelationshipEvaluator(registry: types, limits: limits)
    let typeEvidence = try await evaluator.evaluate(roots: roots(for: referencedTypes), collection: collection)
    let extraction = try await evaluator.extract(roots: roots(for: Set(relationNames.keys)), collection: collection, relations: relationNames)
    var resolved: [String: [MarkdownTypeName: MarkdownTypeAssessment]] = [:]
    for node in typeEvidence.assessments {
      let name = MarkdownTypeName(rawValue: node.type)
      resolved[node.source, default: [:]][name] = .init(type: name,
        version: types.definition(named: name)?.version ?? "", diagnostics: node.diagnostics, outcome: node.outcome)
    }
    var results: [MarkdownCollectionRuleAssessment] = []
    var budget = MarkdownPolicyGraph.Budget(remaining: limits.policySteps)
    var policyCount = 0
    var diagnosticCapacity = limits.diagnostics
    var bytes = 0
    var recordsByRule: [String: [MarkdownCollectionRecordAssessment]] = [:]
    var checker = MarkdownRuleChecker(registry: registry)
    for path in selectedPaths {
      try Task.checkCancellation()
      guard let record = collection.records[path], record.content.utf8.count <= limits.bytes - bytes else {
        bounded = false
        continue
      }
      bytes += record.content.utf8.count
      let analyzed = await MarkdownRecordAnalyzer.analyze(record, contentKind: .rulesKind(forFileName: path))
      checker.relationshipAssessments = resolved[path] ?? [:]
      // Missing bounded type nodes must not fall back to context-free success.
      for name in referencedTypes where checker.relationshipAssessments[name] == nil {
        checker.relationshipAssessments[name] = .init(type: name, version: types.definition(named: name)?.version ?? "",
          diagnostics: [], outcome: .unavailable)
      }
      for rule in rules {
        let membership = try checker.assessApplicability(analyzed, rule: rule.definition)
        let assessment = try checker.assess(analyzed, against: rule, collectionPoliciesHandled: true)
        let member: MarkdownRuleEvidenceStatus = membership.unavailable ? .unavailable : (membership.matches ? .matched : .notMatched)
        let outcome: MarkdownAssessmentOutcome
        if member == .unavailable { outcome = .unavailable }
        else if member == .notMatched { outcome = .pass }
        else {
          var obligations = assessment.typeAssessments.values.map(\.outcome)
          if let expression = assessment.typeExpressionAssessment {
            obligations.append(expression.status == .matched ? .pass : (expression.status == .unavailable ? .unavailable : .fail))
          }
          // Legacy check diagnostics still use the shared type diagnostic classification.
          let checkDiagnostics = assessment.diagnostics.filter { !$0.code.hasPrefix("rule.types.") }
          obligations.append(MarkdownTypeAssessment(type: .init(rawValue: ""), version: "", diagnostics: checkDiagnostics).outcome)
          outcome = .all(obligations)
        }
        recordsByRule[rule.definition.name, default: []].append(.init(path: path, membership: member, outcome: outcome, assessment: assessment))
      }
    }
    if !bounded { limitations.append("relationship.limit.exceeded: collection record, byte or root budget") }
    var graphs: [PolicyGraphContext] = []
    for rule in rules {
      let records = recordsByRule[rule.definition.name] ?? []
      var policies: [MarkdownPolicyAssessment] = []
      var omittedRequiredPolicies = false
      for (index, policy) in rule.definition.relationshipPolicies.enumerated() {
        try Task.checkCancellation()
        policyCount += 1
        let origin = MarkdownPolicyOrigin(rule: rule.definition.name, policy: policy.id,
          definitionSource: rule.definition.source, location: "#/relationshipPolicies/\(index)", declaration: policy.jsonValue)
        let context = PolicyGraphContext(policy: policy, origin: origin, bindings: rule.definition.typeBindings,
          records: records, collection: collection, extraction: extraction)
        var policyLimits = limits
        policyLimits.diagnostics = diagnosticCapacity
        let assessment = try context.assess(mode: cycleWitnessMode, limits: policyLimits, budget: &budget,
          enumerationComplete: bounded && collection.sourcesComplete, overPolicyLimit: policyCount > limits.policies)
        policies.append(assessment)
        diagnosticCapacity -= assessment.diagnostics.count
        if policyCount <= limits.policies { graphs.append(context.withScope(assessment.checkedRecords)) }
        else {
          omittedRequiredPolicies = rule.definition.relationshipPolicies.dropFirst(index).contains { !$0.isNoOp && $0.severity == .error }
          limitations.append("relationship.limit.exceeded: remaining policies omitted for \(rule.definition.name)")
          break
        }
      }
      let sourceComplete = bounded && collection.sourcesComplete && !records.contains { $0.membership == .unavailable }
      let required = policies.filter { $0.severity == .error }.map(\.outcome)
      results.append(.init(rule: rule.definition.name,
        outcome: .all(records.map(\.outcome) + required + [sourceComplete && !omittedRequiredPolicies ? .pass : .unavailable]),
        sourcesComplete: sourceComplete, records: records, policies: policies))
    }
    var conflictLimits = limits
    conflictLimits.diagnostics = diagnosticCapacity
    let conflicts = try PolicyGraphContext.conflicts(graphs, limits: conflictLimits, budget: &budget)
    try Task.checkCancellation()
    return .init(collection: collection.identity, generation: collection.generation, rules: results,
      extraction: extraction, typeEvidence: typeEvidence, conflicts: conflicts.values,
      diagnosticsTruncated: conflicts.truncated || extraction.diagnosticsTruncated || typeEvidence.diagnosticsTruncated
        || results.contains { $0.policies.contains { $0.diagnosticsTruncated } }, limitations: limitations,
      outcome: .all(results.map(\.outcome)))
  }
}

/// Evaluation-local indices retain all selected values, including gaps that cannot prove absence.
private struct PolicyGraphContext {
  var policy: MarkdownRelationshipPolicy
  var origin: MarkdownPolicyOrigin
  var bindings: [String: MarkdownTypeName]
  var records: [MarkdownCollectionRecordAssessment]
  var collection: MarkdownRelationshipCollection
  var extraction: MarkdownRelationshipEvaluation
  var scope: Set<String> = []

  func identity(_ path: String) -> String { collection.records[path]?.identity?.rawValue ?? path }
  func qualified(_ ref: MarkdownPolicyRelation) -> MarkdownPolicyRelation {
    .init(type: bindings[ref.type]?.rawValue ?? ref.type, name: ref.name)
  }
  func withScope(_ identities: [String]) -> Self {
    var copy = self
    copy.scope = Set(identities)
    return copy
  }

  func diagnostic(_ code: String, _ message: String, occurrences: [Int] = [],
    severity: MarkdownDiagnosticSeverity? = nil, origins: [MarkdownPolicyOrigin]? = nil,
  ) -> MarkdownPolicyDiagnostic {
    var value = MarkdownDiagnostic(code: "relationship." + code, severity: severity ?? policy.severity,
      domain: .record, constraintID: policy.id, location: origin.location, message: message)
    value.definitionSource = origin.definitionSource
    value.schemaLocation = origin.location
    return .init(diagnostic: value, origins: origins ?? [origin], occurrences: occurrences)
  }

  func assess(mode: MarkdownCycleWitnessMode, limits: MarkdownRelationshipLimits, budget: inout MarkdownPolicyGraph.Budget,
    enumerationComplete: Bool, overPolicyLimit: Bool,
  ) throws -> MarkdownPolicyAssessment {
    var result = MarkdownPolicyAssessment(origin: origin, outcome: .pass, severity: policy.severity, scope: policy.scope,
      checkedRecords: [], graphComplete: true, boundaryEdges: [], cycleWitnessMode: mode,
      cycleSearchStoppedEarly: false, diagnostics: [], diagnosticsTruncated: false)
    if policy.isNoOp { return result }
    var complete = enumerationComplete && !records.contains { $0.membership == .unavailable }
    var failed = false
    func report(_ value: MarkdownPolicyDiagnostic) {
      if result.diagnostics.count < limits.diagnostics { result.diagnostics.append(value) }
      else { result.diagnosticsTruncated = true }
    }
    let refs = Set(policy.relations.map(qualified))
    var selected = Set(records.filter { $0.membership == .matched }.map { identity($0.path) })
    let membership = Dictionary(records.map { (identity($0.path), $0.membership) }, uniquingKeysWith: { a, b in a == b ? a : .unavailable })
    var edges: [MarkdownPolicyGraph.Edge] = []
    var allEdges: [String: [MarkdownPolicyGraph.Edge]] = [:]
    var values: [String: [MarkdownPolicyRelation: [Int]]] = [:]
    var selection: [String: [MarkdownPolicyRelation: Bool]] = [:]
    var witnesses: [[Int]] = []
    do {
      if overPolicyLimit { throw MarkdownPolicyGraph.Exhausted() }
      for node in extraction.assessments {
        try budget.spend()
        for (name, isComplete) in node.selectionComplete {
          let ref = MarkdownPolicyRelation(type: node.type, name: name)
          if refs.contains(ref) { selection[identity(node.source), default: [:]][ref] = isComplete }
        }
      }
      for (index, occurrence) in extraction.occurrences.enumerated() {
        try budget.spend()
        let ref = MarkdownPolicyRelation(type: occurrence.type, name: occurrence.relationship)
        guard refs.contains(ref) else { continue }
        let source = identity(occurrence.source)
        values[source, default: [:]][ref, default: []].append(index)
        if let target = occurrence.resolution?.destination {
          allEdges[source, default: []].append(.init(source: source, target: identity(target), relation: ref, occurrence: index))
        }
      }
      if policy.scope == .reachable {
        var queue = selected.sorted()
        var cursor = 0
        while cursor < queue.count {
          try budget.spend()
          let source = queue[cursor]
          cursor += 1
          for edge in allEdges[source] ?? [] {
            try budget.spend()
            guard selected.count < limits.nodes || selected.contains(edge.target) else { throw MarkdownPolicyGraph.Exhausted() }
            if selected.insert(edge.target).inserted { queue.append(edge.target) }
          }
        }
      }
      for source in selected.sorted() {
        try budget.spend()
        for ref in refs {
          if selection[source]?[ref] != true { complete = false }
          for index in values[source]?[ref] ?? [] {
            let occurrence = extraction.occurrences[index]
            if occurrence.link == nil || occurrence.resolution == nil { complete = false }
            if let resolution = occurrence.resolution,
              resolution.status == .ambiguous || resolution.status == .unavailable { complete = false }
          }
        }
        for edge in allEdges[source] ?? [] {
          try budget.spend()
          if selected.contains(edge.target) {
            guard edges.count < limits.edges else { throw MarkdownPolicyGraph.Exhausted() }
            edges.append(edge)
          } else if membership[edge.target] == .notMatched { result.boundaryEdges.append(edge.occurrence) }
          else { complete = false }
        }
      }
      switch policy.kind {
      case .cycles:
        try MarkdownPolicyGraph(edges: edges).cycles(mode: mode, budget: &budget, witnesses: &witnesses)
        result.cycleSearchStoppedEarly = mode == .first && !witnesses.isEmpty
      case .selfLinks:
        for edge in edges where edge.source == edge.target {
          try budget.spend()
          failed = true
          report(diagnostic("policy.self-link", "Forbidden self-link at \(edge.source)", occurrences: [edge.occurrence]))
        }
      case .reciprocity(let relation):
        try returns(from: qualified(relation), to: qualified(relation))
      case .inverse(let from, let to):
        try returns(from: qualified(from), to: qualified(to))
      }
    } catch is MarkdownPolicyGraph.Exhausted {
      complete = false
      report(diagnostic("limit.exceeded", "Policy traversal, node, edge or policy budget exceeded"))
    }
    for witness in witnesses {
      failed = true
      report(diagnostic("policy.cycle", "Directed cycle witnessed by \(witness.count) assertion(s)", occurrences: witness))
    }
    if !complete { report(diagnostic("context.unavailable", "Policy graph coverage is incomplete; unwitnessed consistency cannot be certified")) }
    result.checkedRecords = selected.sorted()
    result.graphComplete = complete
    result.outcome = failed ? .fail : (complete ? .pass : .unavailable)
    return result

    func returns(from: MarkdownPolicyRelation, to: MarkdownPolicyRelation) throws {
      struct Key: Hashable { var source: String; var target: String; var relation: MarkdownPolicyRelation }
      let keys = Set(edges.map { Key(source: $0.source, target: $0.target, relation: $0.relation) })
      var uncertainReturns: [Key: Bool] = [:]
      for edge in edges where edge.relation == from {
        try budget.spend()
        let key = Key(source: edge.target, target: edge.source, relation: to)
        if keys.contains(key) { continue }
        let uncertain: Bool
        if let prior = uncertainReturns[key] { uncertain = prior }
        else {
          var possible = selection[edge.target]?[to] != true
          for index in values[edge.target]?[to] ?? [] {
            try budget.spend()
            let occurrence = extraction.occurrences[index]
            guard let resolution = occurrence.resolution else { possible = true; continue }
            if resolution.status == .unavailable { possible = true }
            if resolution.status == .ambiguous && (!resolution.namespaceComplete || resolution.candidates.contains(where: { identity($0) == edge.source })) {
              possible = true
            }
          }
          uncertain = possible
          uncertainReturns[key] = possible
        }
        if uncertain {
          complete = false
          report(diagnostic("context.unavailable", "Return assertion from \(edge.target) to \(edge.source) is uncertain", occurrences: [edge.occurrence]))
        } else {
          failed = true
          let code: String
          if case .reciprocity = policy.kind { code = "policy.reciprocity" } else { code = "policy.inverse" }
          report(diagnostic(code, "Missing return assertion from \(edge.target) to \(edge.source) in \(to.type).\(to.name)", occurrences: [edge.occurrence]))
        }
      }
    }
  }

  static func conflicts(_ contexts: [Self], limits: MarkdownRelationshipLimits, budget: inout MarkdownPolicyGraph.Budget) throws
    -> (values: [MarkdownPolicyDiagnostic], truncated: Bool) {
    var result: [MarkdownPolicyDiagnostic] = []
    do {
      for cycles in contexts {
        guard case .cycles(let relations, .forbidden) = cycles.policy.kind else { continue }
        let union = Set(relations.map(cycles.qualified))
        for other in contexts {
          try budget.spend()
          let forward: MarkdownPolicyRelation
          let backward: MarkdownPolicyRelation
          switch other.policy.kind {
          case .reciprocity(let relation): forward = other.qualified(relation); backward = forward
          case .inverse(let from, let to): forward = other.qualified(from); backward = other.qualified(to)
          default: continue
          }
          guard union.contains(forward), union.contains(backward) else { continue }
          let sameSelection = cycles.origin.rule == other.origin.rule && cycles.policy.scope == other.policy.scope
          var witness: [Int] = []
          let overlap = cycles.scope.intersection(other.scope)
          for (index, occurrence) in other.extraction.occurrences.enumerated() {
            try budget.spend()
            guard occurrence.type == forward.type, occurrence.relationship == forward.name,
              let target = occurrence.resolution?.destination,
              overlap.contains(other.identity(occurrence.source)), overlap.contains(other.identity(target)) else { continue }
            witness = [index]
            break
          }
          guard sameSelection || !witness.isEmpty else { continue }
          guard result.count < limits.diagnostics else { return (result, true) }
          result.append(cycles.diagnostic("policy.conflict",
            witness.isEmpty ? "Potential conflict: required returns can violate forbidden cycles; empty graphs may satisfy both"
              : "On this overlapping edge, the required return necessarily completes a forbidden cycle",
            occurrences: witness, severity: .advisory, origins: [cycles.origin, other.origin]))
        }
      }
      return (result, false)
    } catch is MarkdownPolicyGraph.Exhausted { return (result, true) }
  }
}
