import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import PathKit
import Testing

/// Isolated project-local collections exercise persistence through the production service.
struct RelationshipCacheTests {
  private struct Fixture {
    let root: Path
    let database: SQLiteIndexDatabase
    init() throws {
      root = Path(#filePath).parent().parent().parent().parent() + "tmp/cache-180-\(UUID().uuidString)/"
      try (root + ".md-utils/types/").mkpath()
      try (root + ".md-utils/rules/").mkpath()
      try (root + ".md-utils/md-utils.json").write("{\"configVersion\":\"0.3.0\"}")
      try (root + ".md-utils/types/person.mdtype.json").write("""
        {"md-utils-type-schema":"2","name":"Person","version":"1","requires":["document-relationships"],
         "frontmatter":{"schemas":[{"inline":{"type":"object","required":["name"]}}]},
         "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
         "relationships":{"friends":{"select":["friends",{"each":true}],"target":{"type":"person.mdtype.json"}}}}
        """)
      try (root + ".md-utils/rules/people.mdrule.json").write("""
        {"md-utils-rule-schema":"1","name":"people","types":"person.mdtype.json",
         "relationshipPolicies":[{"id":"return","kind":"reciprocity","scope":"selected",
           "relation":{"type":"person.mdtype.json","name":"friends"}}]}
        """)
      try (root + "A.md").write("---\nname: A\nfriends: ['[[B]]']\n---\n")
      try (root + "B.md").write("---\nname: B\nfriends: ['[[A]]']\n---\n")
      database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
      try database.prepareCollection(root: URL(fileURLWithPath: root.string).resolvingSymlinksInPath().path)
    }
    func session(noIndex: Bool = false, indexedOnly: Bool = false,
      limits: MarkdownRelationshipLimits = .init(),
    ) async throws -> MarkdownRelationshipAssessmentSession {
      try await .load(root: root, noIndex: noIndex, indexedOnly: indexedOnly, verifyHashes: true, limits: limits)
    }
    func query(noIndex: Bool = false, indexedOnly: Bool = false) async throws
      -> (value: MarkdownRelationshipEvaluation, cacheHit: Bool) {
      try await session(noIndex: noIndex, indexedOnly: indexedOnly).relationships(roots: [("A.md", .init(rawValue: "Person"))])
    }
    func policy(noIndex: Bool = false, indexedOnly: Bool = false) async throws
      -> (value: MarkdownRuleCollectionAssessment, cacheHit: Bool) {
      try await session(noIndex: noIndex, indexedOnly: indexedOnly).policies(ruleNames: ["people"])
    }
  }

  @Test func unchangedRefreshReusesEvidenceAndRebindsGeneration() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    let cold = try await f.query()
    let warm = try await f.query()
    #expect(cold.cacheHit == false)
    #expect(warm.cacheHit)
    #expect(cold.value.generation != warm.value.generation)
    #expect(cold.value.occurrences == warm.value.occurrences)
    #expect(try await f.query(noIndex: true).cacheHit == false)
    let policy = try await f.policy()
    #expect(policy.cacheHit == false)
    let cachedPolicy = try await f.policy()
    #expect(cachedPolicy.cacheHit)
    #expect(cachedPolicy.value.outcome == .pass)
    #expect(cachedPolicy.value.generation == cachedPolicy.value.extraction.generation)
    #expect(cachedPolicy.value.generation == cachedPolicy.value.typeEvidence.generation)
    var normalized = cachedPolicy.value
    normalized.generation = policy.value.generation
    normalized.extraction.generation = policy.value.extraction.generation
    normalized.typeEvidence.generation = policy.value.typeEvidence.generation
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(try encoder.encode(normalized) == encoder.encode(policy.value))
  }

  @Test func negativeAndAmbiguousLookupsInvalidateOnNamespaceChanges() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    try (f.root + "B.md").delete()
    #expect(try await f.query().value.occurrences.first?.resolution?.status == .unresolved)
    #expect(try await f.query().cacheHit)
    try (f.root + "B.md").write("---\nname: B\n---\n")
    let repaired = try await f.query()
    #expect(repaired.cacheHit == false)
    #expect(repaired.value.occurrences.first?.resolution?.status == .resolved)
    try (f.root + "other/").mkpath()
    try (f.root + "other/B.md").write("---\nname: Duplicate\n---\n")
    let ambiguous = try await f.query()
    #expect(ambiguous.cacheHit == false)
    #expect(ambiguous.value.occurrences.first?.resolution?.status == .ambiguous)
    #expect(try await f.query().cacheHit)
    try (f.root + "other/B.md").delete()
    let unique = try await f.query()
    #expect(unique.cacheHit == false)
    #expect(unique.value.occurrences == (try await f.query(noIndex: true)).value.occurrences)
  }

  @Test func recursiveTargetAndReturnEditsMatchDirectResults() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    _ = try await f.query()
    _ = try await f.policy()
    // Break required target conformance and a return independently of source A's revision.
    try (f.root + "B.md").write("---\nfriends: []\n---\n")
    let query = try await f.query()
    #expect(query.cacheHit == false)
    #expect(query.value.occurrences.first?.targetOutcome == .fail)
    #expect(query.value.occurrences == (try await f.query(noIndex: true)).value.occurrences)
    let policy = try await f.policy()
    #expect(policy.cacheHit == false)
    #expect(policy.value.outcome == .fail)
    #expect(policy.value.outcome == (try await f.policy(noIndex: true)).value.outcome)
    #expect(try await f.policy().cacheHit)
  }

  @Test func policyAndDefinitionChangesInvalidate() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    _ = try await f.policy()
    try (f.root + ".md-utils/rules/people.mdrule.json").write("""
      {"md-utils-rule-schema":"1","name":"people","types":"person.mdtype.json",
       "relationshipPolicies":[{"id":"cycles","kind":"cycles","scope":"selected","mode":"forbidden",
        "relations":[{"type":"person.mdtype.json","name":"friends"}]}]}
      """)
    let cycle = try await f.policy()
    #expect(cycle.cacheHit == false)
    #expect(cycle.value.outcome == .fail)
    #expect(try await f.policy().cacheHit)
    let file = f.root + ".md-utils/types/person.mdtype.json"
    try file.write(file.read().replacingOccurrences(of: "\"name\"]", with: "\"missing\"]"))
    let changed = try await f.policy()
    #expect(changed.cacheHit == false)
    #expect(changed.value.typeEvidence.assessments.contains { $0.outcome == .fail })
  }

  @Test func limitedCoverageHasSeparateCacheAndNeverDiscovers() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    _ = try await f.query()
    let limited = try await f.query(indexedOnly: true)
    #expect(limited.cacheHit == false)
    #expect(limited.value.sourcesComplete == false)
    #expect(limited.value.candidatesComplete == false)
    #expect(try await f.query(indexedOnly: true).cacheHit)
    try (f.root + "other/").mkpath()
    try (f.root + "other/B.md").write("---\nname: Duplicate\n---\n")
    let stillLimited = try await f.query(indexedOnly: true)
    #expect(stillLimited.cacheHit)
    #expect(stillLimited.value.occurrences.first?.resolution?.status == .unavailable)
    #expect(try await f.query().value.occurrences.first?.resolution?.status == .ambiguous)
  }

  @Test func supersededAndChangedSessionsCannotPublish() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    let old = try await f.session()
    _ = try await f.session()
    await #expect(throws: (any Error).self) {
      try await old.relationships(roots: [("A.md", .init(rawValue: "Person"))])
    }
    let session = try await f.session()
    try (f.root + "B.md").write("changed")
    await #expect(throws: (any Error).self) {
      try await session.relationships(roots: [("A.md", .init(rawValue: "Person"))])
    }
    #expect(try await f.query().cacheHit == false)
  }

  @Test func contextChangesAndStatPreservingEditsInvalidate() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    _ = try await f.query()
    let path = (f.root + "B.md").string
    let date = try #require(FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
    try FileManager.default.setAttributes([.modificationDate: date.addingTimeInterval(10)], ofItemAtPath: path)
    #expect(try await f.query().cacheHit == false)
    let baseline = try #require(FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
    try (f.root + "B.md").write("---\nname: B\nfriends: ['[[Z]]']\n---\n")
    try FileManager.default.setAttributes([.modificationDate: baseline], ofItemAtPath: path)
    let changed = try await f.query()
    #expect(changed.cacheHit == false)
    #expect(changed.value.assessments.contains { $0.outcome == .fail })
  }

  @Test func limitsAreDependenciesAndTruncationIsNotCached() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    _ = try await f.query()
    var limits = MarkdownRelationshipLimits()
    limits.occurrences = 1
    let session = try await f.session(limits: limits)
    let result = try await session.relationships(roots: [("A.md", .init(rawValue: "Person"))])
    #expect(result.cacheHit == false)
    #expect(result.value.assessments.contains { $0.outcome == .unavailable })
    #expect(try await f.session(limits: limits).relationships(roots: [("A.md", .init(rawValue: "Person"))]).cacheHit == false)
  }

  @Test func sourceMoveChangesRelativeBaseAndAttachmentCandidatesInvalidate() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    try (f.root + "A.md").write("---\nname: A\nfriends: ['[[./B]]', '[[image.png]]']\n---\n")
    _ = try await f.query()
    try (f.root + "image.png").write("attachment")
    let attachment = try await f.query()
    #expect(attachment.cacheHit == false)
    #expect(attachment.value.occurrences.contains { $0.resolution?.destination == "image.png" && $0.outcome == .unavailable })
    try (f.root + "moved/").mkpath()
    try (f.root + "A.md").move(f.root + "moved/A.md")
    let session = try await f.session()
    let moved = try await session.relationships(roots: [("moved/A.md", .init(rawValue: "Person"))])
    #expect(moved.cacheHit == false)
    #expect(moved.value.occurrences.contains { $0.source == "moved/A.md" && $0.link?.target == "./B" && $0.resolution?.status == .unresolved })
  }

  @Test func nonmembersAndReachableInversePoliciesInvalidate() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    let rule = f.root + ".md-utils/rules/people.mdrule.json"
    try rule.write("""
      {"md-utils-rule-schema":"1","name":"people","match":{"frontmatter":{"active":{"equals":true}}},
       "types":"person.mdtype.json","relationshipPolicies":[{"id":"inverse","kind":"inverse","scope":"reachable",
        "from":{"type":"person.mdtype.json","name":"friends"},"to":{"type":"person.mdtype.json","name":"friends"}}]}
      """)
    try (f.root + "A.md").write("---\nname: A\nactive: true\nfriends: []\n---\n")
    try (f.root + "B.md").write("---\nname: B\nactive: false\nfriends: ['[[A]]']\n---\n")
    #expect(try await f.policy().value.outcome == .pass)
    #expect(try await f.policy().cacheHit)
    try (f.root + "B.md").write("---\nname: B\nactive: true\nfriends: ['[[A]]']\n---\n")
    let changed = try await f.policy()
    #expect(changed.cacheHit == false)
    #expect(changed.value.outcome == .fail)
    #expect(changed.value.outcome == (try await f.policy(noIndex: true)).value.outcome)
  }

  @Test func transitiveSchemasAndDefinitionResourceMovesInvalidate() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    let definition = f.root + ".md-utils/types/person.mdtype.json"
    try definition.write(definition.read().replacingOccurrences(
      of: "{\"inline\":{\"type\":\"object\",\"required\":[\"name\"]}}", with: "{\"ref\":\"schema.json\"}"))
    try (f.root + ".md-utils/types/schema.json").write("{\"$ref\":\"leaf.json\"}")
    try (f.root + ".md-utils/types/leaf.json").write("{\"type\":\"object\",\"required\":[\"name\"]}")
    _ = try await f.query()
    #expect(try await f.query().cacheHit)
    try (f.root + ".md-utils/types/leaf.json").write("{\"type\":\"object\",\"required\":[\"absent\"]}")
    let changed = try await f.query()
    #expect(changed.cacheHit == false)
    #expect(changed.value.assessments.contains { $0.outcome == .fail })
    // Identical declared names do not erase resource-binding and provenance changes.
    try definition.write(definition.read().replacingOccurrences(of: "person.mdtype.json", with: "renamed.mdtype.json"))
    try definition.move(f.root + ".md-utils/types/renamed.mdtype.json")
    let rule = f.root + ".md-utils/rules/people.mdrule.json"
    try rule.write(rule.read().replacingOccurrences(of: "person.mdtype.json", with: "renamed.mdtype.json"))
    #expect(try await f.query().cacheHit == false)
  }

  @Test func rebuildDropsDerivedEvidenceAndPreservesExternalIntent() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    _ = try await f.query()
    let original = try await f.session()
    // Opaque sentinel bytes verify the rebuild never rewrites durable intent directories.
    for directory in ["drafts/", "mutations/"] {
      try (f.root + ".md-utils/\(directory)").mkpath()
      try (f.root + ".md-utils/\(directory)sentinel.json").write("{\"preserve\":true}")
    }
    let root = URL(fileURLWithPath: f.root.string).resolvingSymlinksInPath()
    let evaluator = original.project
    try await f.database.rebuild(root: root.path) { database, lease in
      let indexer = try CollectionIndexer(database: database, root: root)
      _ = try await indexer.updateMany(adding: IndexScope(), writerLease: lease,
        fingerprint: evaluator.fingerprint, verifyHashes: true, evaluate: evaluator.evaluate)
    }
    await #expect(throws: (any Error).self) {
      try await original.relationships(roots: [("A.md", .init(rawValue: "Person"))])
    }
    #expect(try await f.query().cacheHit == false)
    for directory in ["drafts/", "mutations/"] {
      #expect(try (f.root + ".md-utils/\(directory)sentinel.json").read() == "{\"preserve\":true}")
    }
  }

  @Test func cancelledEvaluationDoesNotPopulateCache() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    let session = try await f.session()
    // Cancel this structured child before invoking the production API, without a timing race.
    await withTaskGroup(of: Void.self) { group in
      group.cancelAll()
      group.addTask {
        await #expect(throws: CancellationError.self) {
          try await session.relationships(roots: [("A.md", .init(rawValue: "Person"))])
        }
      }
    }
    #expect(try await f.query().cacheHit == false)
  }

  @Test func stableUnavailablePoliciesAndWitnessModesAreSeparateRequests() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    _ = try await f.policy()
    let limited = try await f.policy(indexedOnly: true)
    #expect(limited.value.outcome == .unavailable)
    #expect(limited.cacheHit == false)
    #expect(try await f.policy(indexedOnly: true).cacheHit)
    let first = try await f.session().policies(ruleNames: ["people"], cycleWitnessMode: .first)
    #expect(first.cacheHit == false)
    #expect(try await f.session().policies(ruleNames: ["people"], cycleWitnessMode: .first).cacheHit)
  }

  @Test func canonicalV1SchemaBindingChangesInvalidateIdenticalSchemaContents() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    let types = f.root + ".md-utils/types/"
    let person = types + "person.mdtype.json"
    try person.write(person.read().replacingOccurrences(of: "\"target\":{\"type\":\"person.mdtype.json\"}",
      with: "\"target\":{\"type\":\"target.mdtype.json\"}"))
    try (types + "target.mdtype.json").write("""
      {"md-utils-type-schema":"1","name":"Target","version":"1",
       "frontmatter":{"schemas":[{"ref":"alias.json"}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    for file in ["first.json", "second.json"] { try (types + file).write("{\"type\":\"object\"}") }
    let alias = (types + "alias.json").string
    try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: "first.json")
    _ = try await f.query()
    #expect(try await f.query().cacheHit)
    try FileManager.default.removeItem(atPath: alias)
    try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: "second.json")
    let changed = try await f.query()
    #expect(changed.cacheHit == false)
    #expect(changed.value.occurrences.first?.targetOutcome == .pass)
    #expect(try await f.query().cacheHit)
  }

  @Test func cachedMalformedAssertionsRetainOriginalValuesAndProvenance() async throws {
    let f = try Fixture()
    defer { try? f.root.delete() }
    try (f.root + "A.md").write("---\nname: A\nfriends: ['See [[B]]', 1.5, true, null, {key: value}, [nested]]\n---\n")
    let cold = try await f.query()
    let warm = try await f.query()
    #expect(warm.cacheHit)
    #expect(cold.value.occurrences.count == 6)
    #expect(warm.value.occurrences == cold.value.occurrences)
    #expect(warm.value.occurrences.allSatisfy { $0.outcome == .fail })
  }
}
