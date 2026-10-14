import Foundation

/// A read-only proposal set. Diagnostics retain cases where no safe edit can be
/// constructed; unavailable evidence never becomes an inferred assertion.
public struct MarkdownRelationshipFixSuggestions: Sendable {
  public let assessment: MarkdownRuleCollectionAssessment
  public let proposals: [MarkdownFixItProposal]
  public let diagnostics: [MarkdownDiagnostic]
}

/// Combined in-memory effects, including required constraints that would regress.
public struct MarkdownFixItOverlay: Sendable {
  public let records: [String: MarkdownRecord]
  public let before: MarkdownRuleCollectionAssessment
  public let after: MarkdownRuleCollectionAssessment
  public let blockers: [String]

  package func addingBlockers(_ additional: [String]) -> Self {
    .init(records: records, before: before, after: after, blockers: Array(Set(blockers + additional)).sorted())
  }
}

/// Portable proposals over explicitly declared relationship policies. All edits
/// reuse MarkdownFixIt/MarkdownRecordEdit; no filesystem or domain inference.
public struct MarkdownRelationshipFixPlanner: Sendable {
  public let registry: MarkdownRuleRegistry
  public init(registry: MarkdownRuleRegistry) { self.registry = registry }

  public func suggest(collection: MarkdownRelationshipCollection, ruleNames: [String]? = nil,
    includeRecommendations: Bool = false,
  ) async throws -> MarkdownRelationshipFixSuggestions {
    let assessment = try await MarkdownRuleCollectionEvaluator(registry: registry)
      .evaluate(collection: collection, ruleNames: ruleNames)
    var proposals: [MarkdownFixItProposal] = []
    var diagnostics: [MarkdownDiagnostic] = []
    guard let types = registry.typeRegistry else { return .init(assessment: assessment, proposals: [], diagnostics: []) }
    for result in assessment.rules {
      guard let rule = registry.rule(named: result.rule) else { continue }
      for policyResult in result.policies where includeRecommendations || policyResult.severity == .error {
        guard let policy = rule.definition.relationshipPolicies.first(where: { $0.id == policyResult.origin.policy }) else { continue }
        for problem in policyResult.diagnostics {
          try Task.checkCancellation()
          guard ["relationship.policy.reciprocity", "relationship.policy.inverse", "relationship.policy.cycle", "relationship.policy.self-link"]
            .contains(problem.diagnostic.code) else { continue }
          guard proposals.count < 1_000 else { throw MarkdownFixItReviewError.limitExceeded }
          let group = "\(result.rule)/\(policy.id)/\(problem.occurrences.map(String.init).joined(separator: ","))"
          for index in problem.occurrences {
            guard proposals.count < 1_000 else { throw MarkdownFixItReviewError.limitExceeded }
            guard assessment.extraction.occurrences.indices.contains(index) else { continue }
            let occurrence = assessment.extraction.occurrences[index]
            guard let source = collection.records[occurrence.source], source.revision != nil,
              let target = occurrence.resolution?.destination, collection.records[target] != nil else { continue }
            let removal = MarkdownFixIt(id: group + "/remove/\(index)",
              title: "Remove the frontmatter link from \(occurrence.source) to \(target)", safety: .requiresInput,
              edits: [.removeFrontmatterOccurrence(path: occurrence.propertyPath)],
            )
            proposals.append(.init(path: try MarkdownRecordPath(occurrence.source), fixIt: removal,
              diagnostic: problem.diagnostic, rule: result.rule, alternativeGroup: group,
              changes: [.init(path: occurrence.propertyPath, before: occurrence.value, after: nil)],
            ))
            let returnReference: MarkdownPolicyRelation
            switch policy.kind {
            case .reciprocity(let relation): returnReference = relation
            case .inverse(_, let to): returnReference = to
            default: continue
            }
            guard let type = rule.definition.typeBindings[returnReference.type],
              let definition = types.definition(named: type),
              let relation = definition.relationships[returnReference.name],
              let record = collection.records[target] else { continue }
            let analyzed = await MarkdownRecordAnalyzer.analyze(record)
            guard analyzed.parseDiagnostics.isEmpty else { continue }
            let metadata = analyzed.userFrontmatter ?? [:]
            let slots = Self.slots(relation.select[...], value: .object(metadata), path: [])
            guard slots.count <= 1_000 else { throw MarkdownFixItReviewError.limitExceeded }
            var added = false
            for slot in slots {
              for spelling in Self.spellings(destination: occurrence.source, from: target) {
                guard let link = try? Wikilink.parse(spelling),
                  collection.resolver.resolve(target: link.target, from: target).destination == occurrence.source else { continue }
                let value: JSONValue
                if slot.array {
                  if let old = slot.value {
                    guard case .array(var items) = old else { continue }
                    items.append(.string(spelling)); value = .array(items)
                  } else { value = .array([.string(spelling)]) }
                } else { value = .string(spelling) }
                let fix = MarkdownFixIt(id: group + "/return/\(index)/\(proposals.count)",
                  title: "\(slot.value == nil ? "Add" : "Set") \(returnReference.name): \(spelling) in \(target)",
                  safety: .requiresInput, edits: [.setFrontmatterOccurrence(path: slot.path, value: value)],
                )
                let changed = try MarkdownTypeFixer.apply([fix], to: record)
                let overlay = Self.replacing([target: changed], in: collection)
                // The destination's declaring type owns shape, cardinality, scalar
                // style, target conformance and branches. Do not duplicate them.
                let checked = try await MarkdownRelationshipEvaluator(registry: types)
                  .evaluate(roots: [(changed, type)], collection: overlay)
                guard checked.assessments.first(where: { $0.source == target && $0.type == type.rawValue })?.outcome == .pass else { continue }
                proposals.append(.init(path: try MarkdownRecordPath(target), fixIt: fix,
                  diagnostic: problem.diagnostic, rule: result.rule, alternativeGroup: group,
                  changes: [.init(path: slot.path, before: slot.value, after: value)],
                ))
                added = true
                break
              }
              // Multiple concrete slots are alternatives; never invent array rows.
              guard proposals.count < 1_000 else { throw MarkdownFixItReviewError.limitExceeded }
            }
            if !added {
              diagnostics.append(.init(code: "relationship.fix.return-unavailable", severity: problem.diagnostic.severity,
                domain: .frontmatter, constraintID: policy.id, location: target,
                message: "No declaration-conforming return edit could be constructed for \(target).\(returnReference.name); review the selector, cardinality, target type and wikilink constraints.",
              ))
            }
          }
        }
      }
      // #70 consumes the same type diagnostics/fix-its for ordinary rule checks.
      for record in result.records where record.membership == .matched {
        let values = record.assessment.diagnostics + record.assessment.typeAssessments.keys.sorted().flatMap {
          record.assessment.typeAssessments[$0]?.diagnostics ?? []
        }
        var seen = Set<String>()
        for diagnostic in values where includeRecommendations || diagnostic.severity == .error {
          for fix in diagnostic.fixIts where seen.insert(fix.id).inserted {
            // #70's first scope is metadata repair, not body restructuring.
            if fix.edits.contains(where: { if case .appendHeading = $0 { return true }; return false }) { continue }
            var fix = fix
            fix.edits = fix.edits.map {
              if case .setFrontmatterValue(let path, let value) = $0 {
                return .setFrontmatterOccurrence(path: path.map(WikilinkPropertyComponent.key), value: value)
              }
              return $0
            }
            guard proposals.count < 1_000 else { throw MarkdownFixItReviewError.limitExceeded }
            proposals.append(.init(path: try MarkdownRecordPath(record.path), fixIt: fix, diagnostic: diagnostic, rule: result.rule))
          }
        }
      }
    }
    proposals.sort {
      let left = ($0.rule ?? "") + "/" + ($0.alternativeGroup ?? $0.fixIt.id)
      let right = ($1.rule ?? "") + "/" + ($1.alternativeGroup ?? $1.fixIt.id)
      if left != right { return left < right }
      let a = $0.fixIt.edits.contains { if case .removeFrontmatterOccurrence = $0 { return true }; return false }
      let b = $1.fixIt.edits.contains { if case .removeFrontmatterOccurrence = $0 { return true }; return false }
      if a != b { return !a }
      return $0.fixIt.id < $1.fixIt.id
    }
    return .init(assessment: assessment, proposals: proposals, diagnostics: diagnostics)
  }

  /// Reassess the combined selection against every loaded rule and type. No
  /// successful existing required obligation may become failed or unavailable.
  public func preview(collection: MarkdownRelationshipCollection, proposals: [MarkdownFixItProposal]) async throws -> MarkdownFixItOverlay {
    var records = collection.records
    for (path, edits) in Dictionary(grouping: proposals, by: { $0.path.rawValue }) {
      guard let original = records[path] else { throw MarkdownFixItReviewError.missingRevision(path) }
      records[path] = try MarkdownTypeFixer.apply(edits.map(\.fixIt), to: original)
    }
    return try await assessTransition(from: collection, to: Self.replacing(records, in: collection))
  }

  public func assessTransition(from before: MarkdownRelationshipCollection, to after: MarkdownRelationshipCollection) async throws -> MarkdownFixItOverlay {
    let evaluator = MarkdownRuleCollectionEvaluator(registry: registry)
    let old = try await evaluator.evaluate(collection: before)
    let new = try await evaluator.evaluate(collection: after)
    var blockers: [String] = []
    if !before.sourcesComplete || !after.sourcesComplete || !before.resolver.namespaceComplete || !after.resolver.namespaceComplete
      || old.diagnosticsTruncated || new.diagnosticsTruncated || !old.limitations.isEmpty || !new.limitations.isEmpty {
      blockers.append("Complete collection evidence is required before applying fixes.")
    }
    if [old, new].contains(where: { $0.rules.contains { rule in
      rule.records.contains { $0.outcome == .unavailable }
        || rule.policies.contains { $0.severity == .error && !$0.graphComplete }
    } }) { blockers.append("Required rule or policy evidence is unavailable; resolve it before applying fixes.") }
    let previous = Self.requiredFailures(old)
    for failure in Self.requiredFailures(new).subtracting(previous).sorted() { blockers.append("New required failure: " + failure) }
    for rule in old.rules {
      guard let updated = new.rules.first(where: { $0.rule == rule.rule }) else { continue }
      for record in rule.records where record.membership == .matched {
        if updated.records.first(where: { $0.path == record.path })?.membership != .matched {
          blockers.append("Fix would remove \(record.path) from rule \(rule.rule).")
        }
      }
    }
    if let types = registry.typeRegistry {
      guard max(before.records.count, after.records.count) * types.definitions.count <= 100_000 else {
        throw MarkdownFixItReviewError.limitExceeded
      }
      let typeEvaluator = MarkdownRelationshipEvaluator(registry: types)
      let rootsBefore = before.records.keys.sorted().flatMap { path in
        types.definitions.compactMap { type in before.records[path].map { ($0, type.name) } }
      }
      let rootsAfter = after.records.keys.sorted().flatMap { path in
        types.definitions.compactMap { type in after.records[path].map { ($0, type.name) } }
      }
      let oldTypes = try await typeEvaluator.evaluate(roots: rootsBefore, collection: before)
      let newTypes = try await typeEvaluator.evaluate(roots: rootsAfter, collection: after)
      if !oldTypes.limitations.isEmpty || !newTypes.limitations.isEmpty || oldTypes.diagnosticsTruncated || newTypes.diagnosticsTruncated {
        blockers.append("Type assessment evidence is incomplete.")
      }
      let formerlyPassing = Set(oldTypes.assessments.filter { $0.outcome == .pass }.map { $0.source + "\u{0}" + $0.type })
      func failures(_ evaluation: MarkdownRelationshipEvaluation) -> Set<String> {
        Set(evaluation.assessments.flatMap { node in
          node.diagnostics.filter { $0.severity == .error }.map {
            "\(node.source):\(node.type):\($0.code):\($0.location):\($0.schemaLocation ?? ""):\($0.message)"
          }
        })
      }
      blockers += failures(newTypes).subtracting(failures(oldTypes)).sorted().map { "New required type failure: " + $0 }
      for value in newTypes.assessments where value.outcome != .pass && formerlyPassing.contains(value.source + "\u{0}" + value.type) {
        blockers.append("Fix would lose type \(value.type) conformance for \(value.source).")
      }
    }
    // Removing witnessed edges may expose a different pre-existing cycle. That
    // is remaining work, not a new violation. Additions into a still-cyclic graph
    // are blocked conservatively instead of claiming a cycle was harmless.
    let oldEdges = Set(old.extraction.occurrences.compactMap { edge in
      edge.resolution?.destination.map { "\(edge.source):\(edge.type):\(edge.relationship):\($0)" }
    })
    let hasAddedEdges = new.extraction.occurrences.contains { edge in
      guard let target = edge.resolution?.destination else { return false }
      return !oldEdges.contains("\(edge.source):\(edge.type):\(edge.relationship):\(target)")
    }
    if hasAddedEdges && new.rules.contains(where: { $0.policies.contains { policy in
      policy.severity == .error && policy.diagnostics.contains { $0.diagnostic.code == "relationship.policy.cycle" }
    } }) { blockers.append("Adding links while a required cycle policy still fails needs a different selection.") }
    return .init(records: after.records, before: old, after: new, blockers: Array(Set(blockers)).sorted())
  }

  public static func replacing(_ records: [String: MarkdownRecord], in collection: MarkdownRelationshipCollection) -> MarkdownRelationshipCollection {
    .init(identity: collection.identity, generation: collection.generation,
      records: collection.records.merging(records) { _, new in new }, paths: collection.resolver.paths,
      sourcesComplete: collection.sourcesComplete, candidatesComplete: collection.resolver.namespaceComplete,
      completeExactPaths: collection.resolver.completeExactPaths, limitations: collection.limitations,
    )
  }

  private static func requiredFailures(_ value: MarkdownRuleCollectionAssessment) -> Set<String> {
    var failures = Set<String>()
    for rule in value.rules {
      if !rule.sourcesComplete { failures.insert(rule.rule + ": unavailable membership") }
      for record in rule.records where record.membership != .notMatched {
        let diagnostics = record.assessment.diagnostics + record.assessment.applicabilityDiagnostics
        for diagnostic in diagnostics where diagnostic.severity == .error {
          failures.insert("\(rule.rule):\(record.path):\(diagnostic.code):\(diagnostic.location):\(diagnostic.schemaLocation ?? "")")
        }
        if record.outcome == .unavailable { failures.insert("\(rule.rule):\(record.path): unavailable") }
      }
      for policy in rule.policies where policy.severity == .error {
        for problem in policy.diagnostics where problem.diagnostic.severity == .error {
          // Witnesses include endpoint identity, not extraction-array offsets.
          let edges = problem.diagnostic.code == "relationship.policy.cycle" ? "" : problem.occurrences.compactMap { index -> String? in
            guard value.extraction.occurrences.indices.contains(index) else { return nil }
            let edge = value.extraction.occurrences[index]
            return "\(edge.source):\(edge.relationship):\(edge.resolution?.destination ?? "?")"
          }.sorted().joined(separator: ",")
          failures.insert("\(rule.rule):\(policy.origin.policy):\(problem.diagnostic.code):\(edges)")
        }
      }
    }
    return failures
  }

  private struct Slot {
    var path: [WikilinkPropertyComponent]
    var value: JSONValue?
    var array: Bool
  }

  private static func slots(_ selector: ArraySlice<MarkdownRelationshipSelector>, value: JSONValue?,
    path: [WikilinkPropertyComponent],
  ) -> [Slot] {
    guard let first = selector.first else { return [.init(path: path, value: value, array: false)] }
    switch first {
    case .key(let key):
      guard case .object(let object) = value else { return [] }
      return slots(selector.dropFirst(), value: object[key], path: path + [.key(key)])
    case .each:
      if selector.count == 1 { return [.init(path: path, value: value, array: true)] }
      guard case .array(let array) = value else { return [] }
      return array.enumerated().flatMap { slots(selector.dropFirst(), value: $0.element, path: path + [.index($0.offset)]) }
    }
  }

  private static func spellings(destination: String, from source: String) -> [String] {
    let destinationParts = destination.split(separator: "/").map(String.init)
    var sourceParts = source.split(separator: "/").dropLast().map(String.init)
    var targetParts = destinationParts
    while sourceParts.first == targetParts.first && !sourceParts.isEmpty && !targetParts.isEmpty {
      sourceParts.removeFirst(); targetParts.removeFirst()
    }
    let relative = (sourceParts.isEmpty ? "./" : String(repeating: "../", count: sourceParts.count)) + targetParts.joined(separator: "/")
    let name = destinationParts.last ?? destination
    var result: [String] = []
    for full in [name, destination, relative] {
      let omitted: String
      if full.lowercased().hasSuffix(".markdown") { omitted = String(full.dropLast(9)) }
      else if full.lowercased().hasSuffix(".md") { omitted = String(full.dropLast(3)) }
      else { omitted = full }
      for target in [omitted, full] {
        let text = "[[\(target)]]"
        if !result.contains(text) { result.append(text) }
      }
    }
    return result
  }
}
