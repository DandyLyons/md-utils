import Foundation
import Testing
@testable import MarkdownUtilitiesCore

struct MarkdownRelationshipPolicyTests {
  private let friends = MarkdownPolicyRelation(type: "person.mdtype.json", name: "friends")
  private let children = MarkdownPolicyRelation(type: "person.mdtype.json", name: "children")

  private func types() throws -> MarkdownTypeRegistry {
    var relation = MarkdownRelationshipDefinition(select: [.key("friends"), .each], target: "person.mdtype.json")
    relation.forbidAnchors = true
    relation.forbidEmbeds = true
    var inverse = relation
    inverse.select = [.key("children"), .each]
    inverse.severity = .advisory
    let person = MarkdownTypeDefinition(typeSchemaVersion: "2", name: .init(rawValue: "Person"), version: "1",
      frontmatter: .init(schemas: [.inline(.object(["required": .array([.string("name")])]))]),
      requires: ["document-relationships"], relationships: ["friends": relation, "children": inverse])
    let basic = MarkdownTypeDefinition(name: .init(rawValue: "Basic"), version: "1")
    return try .init(definitions: [person, basic], typeResourceBindings: ["person.mdtype.json": person.name, "basic.mdtype.json": basic.name])
  }

  private func rule(_ policies: [MarkdownRelationshipPolicy], name: String = "test", paths: [String] = [],
    type: String = "basic.mdtype.json",
  ) -> MarkdownRuleDefinition {
    .init(name: name, applicability: .init(paths: paths), typeExpression: .reference(type),
      typeBindings: ["person.mdtype.json": .init(rawValue: "Person"), "basic.mdtype.json": .init(rawValue: "Basic")],
      ruleSchemaVersion: "1", relationshipPolicies: policies)
  }

  private func collection(_ values: [(String, String)], complete: Bool = true, candidatesComplete: Bool = true,
    extraPaths: Set<String> = [],
  ) throws -> MarkdownRelationshipCollection {
    let records = try Dictionary(uniqueKeysWithValues: values.map { path, value in
      (path, MarkdownRecord(identity: .init(rawValue: path), content: "---\n\(value)\n---\n",
        context: .init(path: try MarkdownRecordPath(path)), revision: .init(rawValue: value)))
    })
    return .init(identity: "test", generation: "1", records: records, paths: Set(records.keys).union(extraPaths),
      sourcesComplete: complete, candidatesComplete: candidatesComplete, completeExactPaths: Set(records.keys))
  }

  private func evaluate(_ policies: [MarkdownRelationshipPolicy], _ values: [(String, String)],
    paths: [String] = [], complete: Bool = true, mode: MarkdownCycleWitnessMode = .perComponent,
    limits: MarkdownRelationshipLimits = .init(),
  ) async throws -> MarkdownRuleCollectionAssessment {
    let registry = try MarkdownRuleCompiler(typeRegistry: types()).compile([rule(policies, paths: paths)])
    return try await MarkdownRuleCollectionEvaluator(registry: registry, limits: limits, cycleWitnessMode: mode)
      .evaluate(collection: collection(values, complete: complete))
  }

  @Test(arguments: [MarkdownRelationshipPolicy.CycleMode.allowed, .discouraged, .forbidden])
  func cycleModes(_ mode: MarkdownRelationshipPolicy.CycleMode) async throws {
    let result = try await evaluate([.init(id: "cycles", scope: .selected, kind: .cycles([friends], mode))],
      [("A.md", "friends: ['[[B]]']"), ("B.md", "friends: ['[[A]]']")])
    let policy = try #require(result.rules.first?.policies.first)
    #expect(policy.outcome == (mode == .allowed ? .pass : .fail))
    #expect(result.outcome == (mode == .forbidden ? .fail : .pass))
    #expect(policy.diagnostics.filter { $0.diagnostic.code == "relationship.policy.cycle" }.count == (mode == .allowed ? 0 : 1))
    // Policy-only references do not impose Person's missing required name on these records.
    #expect(result.rules.first?.records.allSatisfy { $0.outcome == .pass } == true)
  }

  @Test func witnessesAreBoundedPerComponentOrFirst() async throws {
    let values = [("A.md", "friends: ['[[B]]', '[[A]]']"), ("B.md", "friends: ['[[A]]']"),
      ("C.md", "friends: ['[[D]]']"), ("D.md", "friends: ['[[C]]']")]
    let policies: [MarkdownRelationshipPolicy] = [.init(id: "cycles", scope: .selected, kind: .cycles([friends], .forbidden))]
    let all = try await evaluate(policies, values)
    let first = try await evaluate(policies, values, mode: .first)
    #expect(all.rules[0].policies[0].diagnostics.filter { $0.diagnostic.code == "relationship.policy.cycle" }.count == 2)
    #expect(first.rules[0].policies[0].diagnostics.count == 1)
    #expect(first.rules[0].policies[0].cycleSearchStoppedEarly)
    #expect(all.rules[0].policies[0].cycleSearchStoppedEarly == false)
    let reversed = try await evaluate(policies, values.reversed())
    #expect(all.rules[0].policies[0].diagnostics.map(\.occurrences) == reversed.rules[0].policies[0].diagnostics.map(\.occurrences))
  }

  @Test func selectedBoundaryAndReachableReturnObligation() async throws {
    let values = [("A.md", "friends: ['[[B]]']"), ("B.md", "name: B")]
    let selected = try await evaluate([.init(id: "return", scope: .selected, kind: .reciprocity(friends))], values, paths: ["A.md"])
    #expect(selected.outcome == .pass)
    #expect(selected.rules[0].policies[0].boundaryEdges.count == 1)
    let reachable = try await evaluate([.init(id: "return", scope: .reachable, kind: .reciprocity(friends))], values, paths: ["A.md"])
    #expect(reachable.outcome == .fail)
    #expect(reachable.rules[0].policies[0].checkedRecords == ["A.md", "B.md"])
  }

  @Test func returnsIgnoreMultiplicityAndTypeOrDecorationFailure() async throws {
    let result = try await evaluate([.init(id: "return", scope: .selected, kind: .reciprocity(friends))],
      [("A.md", "friends: ['[[B|one]]', '[[B|two]]']"), ("B.md", "friends: ['![[A#Heading]]']")])
    #expect(result.outcome == .pass)
    #expect(result.extraction.occurrences.contains { $0.outcome == .fail })
  }

  @Test func inverseIsDirectionalAndExtractsAdvisoryRelation() async throws {
    let forward = MarkdownRelationshipPolicy(id: "inverse", scope: .reachable, kind: .inverse(from: friends, to: children))
    let reverse = MarkdownRelationshipPolicy(id: "reverse", scope: .reachable, kind: .inverse(from: children, to: friends))
    let values = [("A.md", "friends: ['[[B]]']"), ("B.md", "children: ['[[A]]', '[[C]]']"), ("C.md", "name: C")]
    #expect(try await evaluate([forward], values).outcome == .pass)
    let failed = try await evaluate([forward, reverse], values)
    #expect(failed.outcome == .fail)
    #expect(failed.rules[0].policies[1].diagnostics.contains { $0.diagnostic.code == "relationship.policy.inverse" })
  }

  @Test func selfLinksAreIndependent() async throws {
    let result = try await evaluate([
      .init(id: "return", scope: .selected, kind: .reciprocity(friends)),
      .init(id: "self", scope: .selected, kind: .selfLinks([friends], forbid: true)),
      .init(id: "inverse", scope: .selected, kind: .inverse(from: friends, to: children)),
    ], [("A.md", "friends: ['[[#Here]]']")])
    #expect(result.rules[0].policies.map(\.outcome) == [.pass, .fail, .fail])
  }

  @Test func mixedRelationsOnlyCycleWhenExplicitlyCombined() async throws {
    let result = try await evaluate([
      .init(id: "friends", scope: .selected, kind: .cycles([friends], .forbidden)),
      .init(id: "children", scope: .selected, kind: .cycles([children], .forbidden)),
      .init(id: "both", scope: .selected, kind: .cycles([friends, children], .forbidden)),
    ], [("A.md", "friends: ['[[B]]']"), ("B.md", "children: ['[[A]]']")])
    #expect(result.rules[0].policies.map(\.outcome) == [.pass, .pass, .fail])
  }

  @Test(arguments: ["friends: ['bad']", "friends: [", "friends: 3"])
  func uncertainReturnsDoNotBecomeMissingReturns(_ value: String) async throws {
    let result = try await evaluate([.init(id: "return", scope: .selected, kind: .reciprocity(friends))],
      [("A.md", "friends: ['[[B]]']"), ("B.md", value)])
    #expect(result.rules[0].policies[0].outcome == .unavailable)
    #expect(result.rules[0].policies[0].diagnostics.contains { $0.diagnostic.code == "relationship.policy.reciprocity" } == false)
  }

  @Test func unresolvedReturnProvesMissingButAmbiguousPossibleReturnDoesNot() async throws {
    let policy = MarkdownRelationshipPolicy(id: "return", scope: .selected, kind: .reciprocity(friends))
    let missing = try await evaluate([policy], [("A.md", "friends: ['[[B]]']"), ("B.md", "friends: ['[[Missing]]']")])
    #expect(missing.outcome == .fail)
    let ambiguous = try await evaluate([policy], [("A.md", "friends: ['[[B]]']"), ("B.md", "friends: ['[[A]]']"), ("other/A.md", "name: Other")])
    #expect(ambiguous.outcome == .unavailable)
  }

  @Test func incompleteCoverageRetainsWitnessesAndRejectsGlobalSuccess() async throws {
    let policy = MarkdownRelationshipPolicy(id: "cycles", scope: .selected, kind: .cycles([friends], .forbidden))
    let witnessed = try await evaluate([policy], [("A.md", "friends: ['[[B]]']"), ("B.md", "friends: ['[[A]]']")], complete: false)
    #expect(witnessed.outcome == .fail)
    #expect(witnessed.rules[0].policies[0].graphComplete == false)
    let empty = try await evaluate([policy], [], complete: false)
    #expect(empty.outcome == .unavailable)
    #expect(try await evaluate([policy], []).outcome == .pass)
  }

  @Test func conflictsRetainOriginsAndObservedPropertyWitnesses() async throws {
    let policies: [MarkdownRelationshipPolicy] = [
      .init(id: "cycles", scope: .selected, kind: .cycles([friends], .forbidden)),
      .init(id: "return", scope: .selected, kind: .reciprocity(friends)),
    ]
    let empty = try await evaluate(policies, [])
    #expect(empty.outcome == .pass)
    #expect(empty.conflicts.count == 1)
    let observed = try await evaluate(policies, [("A.md", "friends: ['[[B]]']"), ("B.md", "name: B")])
    let conflict = try #require(observed.conflicts.first)
    #expect(conflict.origins.map(\.policy) == ["cycles", "return"])
    #expect(conflict.occurrences.count == 1)
    #expect(observed.extraction.occurrences[try #require(conflict.occurrences.first)].propertyPath == [.key("friends"), .index(0)])
  }

  @Test func exhaustedTraversalNeverPassesAndCancellationAborts() async throws {
    let policies: [MarkdownRelationshipPolicy] = [.init(id: "cycles", scope: .selected, kind: .cycles([friends], .forbidden))]
    var limits = MarkdownRelationshipLimits()
    limits.policySteps = 1
    let result = try await evaluate(policies, [("A.md", "friends: ['[[A]]']")], limits: limits)
    #expect(result.outcome == .unavailable)
    #expect(result.rules[0].policies[0].diagnostics.contains { $0.diagnostic.code == "relationship.limit.exceeded" })
    await #expect(throws: CancellationError.self) {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          while !Task.isCancelled { await Task.yield() }
          _ = try await evaluate(policies, [])
        }
        group.cancelAll()
        try await group.waitForAll()
      }
    }
  }

  @Test func versionedDeclarationsRoundTripAndLegacyRejectsPolicyFields() throws {
    let content = """
    {"md-utils-rule-schema":"1","name":"people","types":"basic.mdtype.json",
    "relationshipPolicies":[{"id":"return","kind":"reciprocity","scope":"selected","relation":{"type":"person.mdtype.json","name":"friends"}}]}
    """
    let decoded = try MarkdownRuleFile.decode(content, source: "test")
    #expect(try MarkdownRuleFile.decode(decoded.encoded(), source: "test") == decoded)
    #expect(throws: MarkdownRuleFileError.self) { try MarkdownRuleFile.decode(content.replacingOccurrences(of: "\"md-utils-rule-schema\":\"1\",", with: ""), source: "test") }
    #expect(throws: MarkdownRuleFileError.self) { try MarkdownRuleFile.decode(content.replacingOccurrences(of: "\"1\"", with: "\"2\""), source: "test") }
    var invalid = rule(decoded.relationshipPolicies)
    invalid.ruleSchemaVersion = nil
    #expect(throws: MarkdownRuleCompilationError.self) { try MarkdownRuleCompiler(typeRegistry: types()).compile([invalid]) }
    invalid.ruleSchemaVersion = "1"
    invalid.relationshipPolicies = [.init(id: "bad", scope: .selected, kind: .reciprocity(.init(type: "person.mdtype.json", name: "unknown")))]
    #expect(throws: MarkdownRuleCompilationError.self) { try MarkdownRuleCompiler(typeRegistry: types()).compile([invalid]) }
    var inconsistent = MarkdownRelationshipPolicy(id: "cycle", scope: .selected, kind: .cycles([friends], .forbidden))
    inconsistent.severity = .advisory
    invalid.relationshipPolicies = [inconsistent]
    #expect(throws: MarkdownRuleCompilationError.self) { try MarkdownRuleCompiler(typeRegistry: types()).compile([invalid]) }
  }

  @Test func policyBudgetsAndDiagnosticTruncationPreserveOutcomes() async throws {
    let policy = MarkdownRelationshipPolicy(id: "cycle", scope: .selected, kind: .cycles([friends], .forbidden))
    let values = [("A.md", "friends: ['[[A]]']"), ("B.md", "friends: ['[[B]]']")]
    var limits = MarkdownRelationshipLimits()
    limits.diagnostics = 1
    let result = try await evaluate([policy], values, limits: limits)
    #expect(result.outcome == .fail)
    #expect(result.diagnosticsTruncated)
    #expect(result.rules[0].policies[0].diagnostics.count == 1)
    limits = .init()
    limits.policies = 1
    let policies: [MarkdownRelationshipPolicy] = [
      .init(id: "allowed", scope: .selected, kind: .cycles([friends], .allowed)),
      .init(id: "advisory", scope: .selected, kind: .cycles([friends], .discouraged)),
      policy,
    ]
    let limited = try await evaluate(policies, [], limits: limits)
    #expect(limited.outcome == .unavailable)
    #expect(limited.rules[0].policies.count == 2)
  }

  @Test func thousandRecordCycleFitsDefaultBudgetsAndIsDeterministic() async throws {
    let values = (0..<1_000).map { ("N\($0).md", "friends: ['[[N\(($0 + 1) % 1_000)]]']") }
    let policy = MarkdownRelationshipPolicy(id: "cycles", scope: .reachable, kind: .cycles([friends], .forbidden))
    let result = try await evaluate([policy], values, paths: ["N0.md"])
    #expect(result.outcome == .fail)
    #expect(result.rules[0].policies[0].checkedRecords.count == 1_000)
    #expect(result.rules[0].policies[0].graphComplete)
    #expect(result.rules[0].policies[0].diagnostics.first?.occurrences.count == 1_000)
    #expect(result.diagnosticsTruncated == false)
  }

  @Test func standaloneRecordAssessmentCannotSilentlyIgnoreRequiredPolicies() async throws {
    let registry = try MarkdownRuleCompiler(typeRegistry: types()).compile([
      rule([.init(id: "cycles", scope: .selected, kind: .cycles([friends], .forbidden))]),
    ])
    let snapshot = try collection([("A.md", "friends: ['[[A]]']")])
    let record = try #require(snapshot.records["A.md"])
    let assessment = try await MarkdownRuleChecker(registry: registry).assess(record, ruleNamed: "test", collection: snapshot)
    #expect(assessment.status == .failed)
    #expect(assessment.diagnostics.contains { $0.code == "relationship.context.unavailable" })
  }

  @Test func crossRuleConflictsRequireObservedOverlapAndRespectRequestedRules() async throws {
    let registry = try MarkdownRuleCompiler(typeRegistry: types()).compile([
      rule([.init(id: "cycles", scope: .selected, kind: .cycles([friends], .forbidden))], name: "acyclic"),
      rule([.init(id: "return", scope: .reachable, kind: .reciprocity(friends))], name: "returns", paths: ["A.md"]),
    ])
    let evaluator = MarkdownRuleCollectionEvaluator(registry: registry)
    let snapshot = try collection([("A.md", "friends: ['[[B]]']"), ("B.md", "name: B")])
    let together = try await evaluator.evaluate(collection: snapshot)
    #expect(together.conflicts.count == 1)
    let alone = try await evaluator.evaluate(collection: snapshot, ruleNames: ["acyclic"])
    #expect(alone.conflicts.isEmpty)
    #expect(alone.outcome == .pass)
  }

  @Test func opaqueDocumentIdentitiesAreNotReinterpretedAsPaths() async throws {
    let registry = try MarkdownRuleCompiler(typeRegistry: types()).compile([
      rule([
        .init(id: "cycles", scope: .selected, kind: .cycles([friends], .forbidden)),
        .init(id: "return", scope: .selected, kind: .reciprocity(friends)),
      ]),
    ])
    let original = try collection([("A.md", "friends: ['[[B]]']"), ("B.md", "name: B")])
    var records: [String: MarkdownRecord] = [:]
    for (path, record) in original.records {
      records[path] = .init(identity: .init(rawValue: path == "A.md" ? "B.md" : "opaque-B"),
        content: record.content, context: record.context, revision: record.revision)
    }
    let snapshot = MarkdownRelationshipCollection(identity: "test", generation: "1", records: records,
      paths: Set(records.keys), sourcesComplete: true, candidatesComplete: true)
    let result = try await MarkdownRuleCollectionEvaluator(registry: registry).evaluate(collection: snapshot)
    #expect(result.outcome == .fail)
    #expect(result.conflicts.first?.occurrences.count == 1)
    #expect(result.rules[0].policies[0].checkedRecords == ["B.md", "opaque-B"])
  }
}
