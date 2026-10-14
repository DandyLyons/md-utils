import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import PathKit
import Testing
import Yams
@testable import md_utils

private struct RelationshipFixture {
  let root: Path
  init() throws {
    root = Path(#filePath).parent().parent().parent().parent() + "tmp/relationships-\(UUID().uuidString)/"
    try (root + ".md-utils/types/").mkpath()
    try (root + ".md-utils/rules/").mkpath()
    try (root + ".md-utils/md-utils.json").write("{\"configVersion\":\"0.3.0\"}")
    try (root + ".md-utils/types/person.mdtype.json").write("""
      {"md-utils-type-schema":"2","name":"Person","version":"1","requires":["document-relationships"],
       "frontmatter":{"schemas":[{"inline":{"type":"object","required":["name"]}}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
       "relationships":{"friends":{"select":["related",{"each":true}],"target":{"type":"person.mdtype.json"}}}}
      """)
    try (root + ".md-utils/rules/people.mdrule.json").write("""
      {"name":"people","match":{"paths":["*.md"]},"types":"person.mdtype.json"}
      """)
    try (root + "A.md").write("---\nname: A\nrelated: ['[[B]]', '[[#Self]]']\n---\n")
    try (root + "B.md").write("---\nname: B\nrelated: ['[[A]]']\n---\n")
  }
  func remove() { try? root.delete() }
  func index() throws -> SQLiteIndexDatabase {
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    try database.prepareCollection(root: URL(fileURLWithPath: root.string).resolvingSymlinksInPath().path)
    return database
  }
  func query(noIndex: Bool = false, indexedOnly: Bool = false) async throws -> MarkdownRelationshipQuery {
    let types = try MarkdownTypeFileRegistryLoader.load(projectRoot: root)
    let collection = try await MarkdownRelationshipNativeCollection.load(root: root, noIndex: noIndex, indexedOnly: indexedOnly)
    let result = try await MarkdownRelationshipEvaluator(registry: types).evaluate(
      roots: collection.records.keys.sorted().compactMap { collection.records[$0].map { ($0, .init(rawValue: "Person")) } }, collection: collection)
    return .init(evaluation: result, source: "A.md", direction: .both, type: "Person")
  }
}

@Suite("Relationship CLI and index integration")
struct RelationshipCommandsTests {
  @Test func `aliases parse and output flags conflict`() throws {
    let args = ["A.md", "--type", "Person", "--root", "./vault/"]
    #expect(try CLIEntry.parseAsRoot(["rel", "out"] + args + ["--yaml"]) is CLIEntry.Relationships.Outgoing)
    #expect(try CLIEntry.parseAsRoot(["rel", "in"] + args + ["--json"]) is CLIEntry.Relationships.Incoming)
    #expect(try CLIEntry.parseAsRoot(["relationships", "both"] + args) is CLIEntry.Relationships.Both)
    #expect(throws: (any Error).self) { try CLIEntry.parseAsRoot(["rel", "both"] + args + ["--json", "--yaml"]) }
    #expect(throws: (any Error).self) { try CLIEntry.parseAsRoot(["rel", "both"] + args + ["--no-index", "--indexed-only"]) }
  }

  @Test func `direct and indexed query sections agree and target edits are reassessed`() async throws {
    let fixture = try RelationshipFixture()
    defer { fixture.remove() }
    let direct = try await fixture.query(noIndex: true)
    #expect(direct.outgoing.count == 1)
    #expect(direct.incoming.count == 1)
    #expect(direct.selfLinks.count == 1)
    #expect(direct.outgoing[0].outcome == .pass)
    _ = try fixture.index()
    let indexed = try await fixture.query()
    #expect(indexed.outgoing == direct.outgoing)
    #expect(indexed.incoming == direct.incoming)
    #expect(indexed.selfLinks == direct.selfLinks)
    try (fixture.root + "B.md").write("---\nrelated: ['[[A]]']\n---\n")
    let changed = try await fixture.query()
    #expect(changed.outgoing[0].targetOutcome == .fail)
    #expect(changed.outgoing == (try await fixture.query(noIndex: true)).outgoing)
  }

  @Test func `indexed only never discovers new candidates and preserves uncertainty`() async throws {
    let fixture = try RelationshipFixture()
    defer { fixture.remove() }
    _ = try fixture.index()
    _ = try await fixture.query()
    try (fixture.root + "other/").mkpath()
    try (fixture.root + "other/B.md").write("---\nname: Other\n---\n")
    let limited = try await fixture.query(indexedOnly: true)
    #expect(limited.evidence.sourcesComplete == false)
    #expect(limited.evidence.candidatesComplete == false)
    #expect(limited.outgoing[0].resolution?.status == .unavailable)
    #expect(limited.evidence.limitations.contains { $0.contains("New files were not discovered") })
    let discovered = try await fixture.query()
    #expect(discovered.outgoing[0].resolution?.status == .ambiguous)
    #expect(discovered.outgoing[0].resolution?.candidates == ["B.md", "other/B.md"])
  }

  @Test func `indexed only requires registered scope and ordinary failures fall back`() async throws {
    let fixture = try RelationshipFixture()
    defer { fixture.remove() }
    await #expect(throws: (any Error).self) { try await fixture.query(indexedOnly: true) }
    _ = try fixture.index()
    await #expect(throws: (any Error).self) { try await fixture.query(indexedOnly: true) }
    let query = try await fixture.query()
    #expect(query.evidence.sourcesComplete)
  }

  @Test func `structured yaml and json preserve identical evidence`() async throws {
    let fixture = try RelationshipFixture()
    defer { fixture.remove() }
    let query = try await fixture.query(noIndex: true)
    let json = try JSONEncoder().encode(query)
    let yaml = try YAMLEncoder().encode(query)
    let decoded = try YAMLDecoder().decode(MarkdownRelationshipQuery.self, from: yaml)
    #expect(decoded.outgoing == query.outgoing)
    #expect(decoded.selfLinks == query.selfLinks)
    #expect(try JSONDecoder().decode(MarkdownRelationshipQuery.self, from: json).incoming == decoded.incoming)
  }

  @Test func `types and rules check full destination contracts through native collection`() async throws {
    let fixture = try RelationshipFixture()
    defer { fixture.remove() }
    let types = try await TypesRunner.assess(typeName: "Person", files: [fixture.root + "A.md"], root: fixture.root)
    #expect(types[0].assessment.outcome == .pass)
    let first = try await RulesValidatorRunner.validate(ruleName: "people", root: fixture.root,
      configPath: fixture.root + ".md-utils/md-utils.json", projectRoot: fixture.root, noIndex: true)
    #expect(first.hasFailures == false)
    try (fixture.root + "B.md").write("---\nrelated: ['[[A]]']\n---\n")
    _ = try fixture.index()
    let failed = try await RulesValidatorRunner.validate(ruleName: "people", root: fixture.root,
      configPath: fixture.root + ".md-utils/md-utils.json", projectRoot: fixture.root)
    #expect(failed.hasFailures)
    #expect(failed.results.contains { $0.filePath == "A.md" && $0.status == .error })
    let limited = try await RulesValidatorRunner.validate(ruleName: "people", root: fixture.root,
      configPath: fixture.root + ".md-utils/md-utils.json", projectRoot: fixture.root, indexedOnly: true)
    #expect(limited.indexedOnly)
  }

  @Test func `CLI emits parseable YAML and returns evidence for invalid assertions`() throws {
    let fixture = try RelationshipFixture()
    defer { fixture.remove() }
    try (fixture.root + "A.md").write("---\nname: A\nrelated: ['See [[B]]', '[[#Self]]']\n---\n")
    let args = ["rel", "both", "A.md", "--type", "Person", "--root", fixture.root.string, "--no-index"]
    let yaml = try CLIProcessTestHelper.run(args + ["--yaml"])
    #expect(yaml.status == 0)
    #expect(yaml.standardError.isEmpty)
    let decoded = try YAMLDecoder().decode(MarkdownRelationshipQuery.self, from: yaml.standardOutput)
    #expect(decoded.outgoing.count == 1)
    #expect(decoded.outgoing[0].outcome == .fail)
    #expect(decoded.selfLinks.count == 1)
    let json = try CLIProcessTestHelper.run(args + ["--json"])
    #expect(json.status == 0)
    #expect(try JSONDecoder().decode(MarkdownRelationshipQuery.self, from: Data(json.standardOutput.utf8)).outgoing == decoded.outgoing)
    let validation = try CLIProcessTestHelper.run(["types", "check", "Person", (fixture.root + "A.md").string, "--root", fixture.root.string, "--format", "json"])
    #expect(validation.status != 0)
    #expect(validation.standardOutput.contains("relationship.value.invalid"))
  }

  @Test func `unusable index warns and falls back without contaminating structured output`() throws {
    let fixture = try RelationshipFixture()
    defer { fixture.remove() }
    try (fixture.root + ".md-utils/index.sqlite").write("not a database")
    let result = try CLIProcessTestHelper.run(["rel", "out", "A.md", "--type", "Person", "--root", fixture.root.string, "--json"])
    #expect(result.status == 0)
    #expect(result.standardError.contains("reading source files directly"))
    let decoded = try JSONDecoder().decode(MarkdownRelationshipQuery.self, from: Data(result.standardOutput.utf8))
    #expect(decoded.outgoing[0].outcome == .pass)
  }

  @Test func `indexed only can certify a known exact path without a namespace scan`() async throws {
    let fixture = try RelationshipFixture()
    defer { fixture.remove() }
    try (fixture.root + "A.md").write("---\nname: A\nrelated: ['[[./B.md]]']\n---\n")
    try (fixture.root + "B.md").write("---\nname: B\n---\n")
    _ = try fixture.index()
    _ = try await fixture.query()
    let result = try await fixture.query(indexedOnly: true)
    #expect(result.evidence.candidatesComplete == false)
    #expect(result.outgoing[0].resolution?.namespaceComplete == true)
    #expect(result.outgoing[0].outcome == .pass)
  }

  @Test func `indexed relationship rule validation honors custom config paths`() async throws {
    let fixture = try RelationshipFixture()
    defer { fixture.remove() }
    let custom = fixture.root + "custom.json"
    try custom.write("{\"configVersion\":\"0.3.0\"}")
    try (fixture.root + ".md-utils/md-utils.json").delete()
    _ = try fixture.index()
    var warnings: [String] = []
    let result = try await RulesValidatorRunner.validate(ruleName: "people", root: fixture.root,
      configPath: custom, projectRoot: fixture.root, warning: { warnings.append($0) })
    #expect(!result.hasFailures)
    #expect(warnings.isEmpty)
    let limited = try await RulesValidatorRunner.validate(ruleName: "people", root: fixture.root,
      configPath: custom, projectRoot: fixture.root, indexedOnly: true)
    #expect(limited.indexedOnly)
  }
}
