import Foundation
import JSONSchema
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit
import Testing
import Yams
@testable import md_utils

/// Each integration test owns a project-local vault, exercising the real native adapters.
struct RelationshipPolicyCommandsTests {
  private func fixture(mode: String = "forbidden") throws -> Path {
    let root = Path(#filePath).parent().parent().parent().parent() + "tmp/policies-178-\(UUID().uuidString)/"
    try (root + ".md-utils/types/").mkpath()
    try (root + ".md-utils/rules/").mkpath()
    try (root + ".md-utils/md-utils.json").write("{\"configVersion\":\"0.3.0\"}")
    try (root + ".md-utils/types/basic.mdtype.json").write("""
      {"md-utils-type-schema":"1","name":"Basic","version":"1","frontmatter":{},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    try (root + ".md-utils/types/person.mdtype.json").write("""
      {"md-utils-type-schema":"2","name":"Person","version":"1","requires":["document-relationships"],
       "frontmatter":{},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
       "relationships":{"friends":{"select":["friends",{"each":true}],"target":{"type":"person.mdtype.json"}}}}
      """)
    try (root + ".md-utils/rules/people.mdrule.json").write("""
      {"md-utils-rule-schema":"1","name":"people","types":"basic.mdtype.json",
       "relationshipPolicies":[{"id":"cycles","kind":"cycles","scope":"selected","mode":"\(mode)",
        "relations":[{"type":"person.mdtype.json","name":"friends"}]}]}
      """)
    for (path, target) in [("A", "B"), ("B", "A"), ("C", "D"), ("D", "C")] {
      try (root + "\(path).md").write("---\nfriends: ['[[\(target)]]']\n---\n")
    }
    return root
  }

  private func validate(_ root: Path, noIndex: Bool, indexedOnly: Bool = false) async throws -> RuleValidationSummary {
    try await RulesValidatorRunner.validate(ruleName: "people", root: root,
      configPath: root + ".md-utils/md-utils.json", projectRoot: root, noIndex: noIndex,
      indexedOnly: indexedOnly, verifyHashes: !indexedOnly)
  }

  @Test func directAndIndexedAgreeAndPolicyChangesAreRecomputed() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let direct = try await validate(root, noIndex: true)
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    try database.prepareCollection(root: URL(fileURLWithPath: root.string).resolvingSymlinksInPath().path)
    let indexed = try await validate(root, noIndex: false)
    #expect(direct.hasFailures && indexed.hasFailures)
    let left = try #require(direct.collectionAssessment?.rules.first?.policies.first)
    let right = try #require(indexed.collectionAssessment?.rules.first?.policies.first)
    #expect(left.outcome == right.outcome)
    #expect(left.diagnostics.map(\.occurrences) == right.diagnostics.map(\.occurrences))
    let file = root + ".md-utils/rules/people.mdrule.json"
    try file.write(file.read().replacingOccurrences(of: "forbidden", with: "discouraged"))
    let advisory = try await validate(root, noIndex: false)
    #expect(advisory.hasFailures == false)
    #expect(advisory.collectionAssessment?.rules.first?.policies.first?.outcome == .fail)
  }

  @Test func indexedOnlyCannotCertifyPolicyConsistency() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    for file in ["A.md", "B.md", "C.md", "D.md"] { try (root + file).write("# No assertions\n") }
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    try database.prepareCollection(root: URL(fileURLWithPath: root.string).resolvingSymlinksInPath().path)
    #expect(try await validate(root, noIndex: false).hasFailures == false)
    let limited = try await validate(root, noIndex: false, indexedOnly: true)
    #expect(limited.hasFailures)
    #expect(limited.results.contains { $0.status == .error })
  }

  @Test func cliWitnessFlagsAndFormats() throws {
    let root = try fixture()
    defer { try? root.delete() }
    let base = ["rules", "validate", "people", "--project-root", root.string,
      "--config", (root + ".md-utils/md-utils.json").string, "--no-index"]
    let perComponent = try CLIProcessTestHelper.run(base + ["--json", "--cycle-witness-per-component"])
    #expect(perComponent.status != 0)
    try #require(perComponent.standardOutput.isEmpty == false, "\(perComponent.standardError)")
    let json = try #require(JSONSerialization.jsonObject(with: Data(perComponent.standardOutput.utf8)) as? [String: Any])
    let collection = try #require(json["collectionAssessment"] as? [String: Any])
    let decoded = try JSONDecoder().decode(MarkdownRuleCollectionAssessment.self,
      from: JSONSerialization.data(withJSONObject: collection))
    #expect(decoded.rules[0].policies[0].diagnostics.count == 2)
    #expect(decoded.rules[0].policies[0].cycleWitnessMode == .perComponent)
    let first = try CLIProcessTestHelper.run(base + ["--yaml", "--cycle-witness-first"])
    #expect(first.status != 0)
    let yaml = try #require(Yams.load(yaml: first.standardOutput) as? [String: Any])
    let yamlCollection = try #require(yaml["collectionAssessment"] as? [String: Any])
    let firstDecoded = try JSONDecoder().decode(MarkdownRuleCollectionAssessment.self,
      from: JSONSerialization.data(withJSONObject: yamlCollection))
    #expect(firstDecoded.rules[0].policies[0].diagnostics.count == 1)
    #expect(firstDecoded.rules[0].policies[0].cycleSearchStoppedEarly)
    let invalid = try CLIProcessTestHelper.run(base + ["--cycle-witness-first", "--cycle-witness-per-component"])
    #expect(invalid.status != 0)
    #expect(invalid.standardError.contains("mutually exclusive"))
    let text = try CLIProcessTestHelper.run(base)
    #expect(text.standardOutput.contains("relationship.policy.cycle"))
    #expect(text.standardOutput.contains("friends"))
  }

  @Test func immutablePolicySchemaMatchesDecoderAndLegacyRejectsNewFields() throws {
    let repository = Path(#filePath).parent().parent().parent().parent()
    let schemaData = try (repository + "Sources/md-utils/Resources/1_mdrule.schema.json").read(.utf8)
    let schema = try #require(JSONSerialization.jsonObject(with: Data(schemaData.utf8)) as? [String: Any])
    let legacyData = try (repository + "Sources/md-utils/Resources/0.3.0_mdrule.schema.json").read(.utf8)
    let legacy = try #require(JSONSerialization.jsonObject(with: Data(legacyData.utf8)) as? [String: Any])
    let relation: [String: Any] = ["type": "person.mdtype.json", "name": "friends"]
    let policies: [[String: Any]] = [
      ["id": "cycle", "kind": "cycles", "scope": "selected", "relations": [relation], "mode": "forbidden"],
      ["id": "self", "kind": "selfLinks", "scope": "selected", "relations": [relation], "mode": "allow"],
      ["id": "return", "kind": "reciprocity", "scope": "reachable", "relation": relation],
      ["id": "inverse", "kind": "inverse", "scope": "reachable", "from": relation, "to": relation],
    ]
    for policy in policies {
      let document: [String: Any] = ["md-utils-rule-schema": "1", "name": "people", "types": "person.mdtype.json", "relationshipPolicies": [policy]]
      #expect(try JSONSchema.validate(document, schema: schema).valid)
      #expect(try JSONSchema.validate(document, schema: legacy).valid == false)
      let text = String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self)
      #expect(try MarkdownRuleFile.decode(text, source: "test").relationshipPolicies.count == 1)
    }
    var invalid = try #require(policies.first)
    invalid["severity"] = "advisory"
    let document: [String: Any] = ["md-utils-rule-schema": "1", "name": "people", "types": "person.mdtype.json", "relationshipPolicies": [invalid]]
    #expect(try JSONSchema.validate(document, schema: schema).valid == false)
    let text = String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self)
    #expect(throws: MarkdownRuleFileError.self) { try MarkdownRuleFile.decode(text, source: "test") }
  }
}
