import Foundation
import MarkdownUtilities
import PathKit
import Testing
@testable import md_utils

@Suite("Standalone config integration", .serialized)
struct StandaloneConfigIntegrationTests {
  @Test
  func `Migration previews then loads and validates standalone rules from config root`() async throws {
    let root = try project()
    defer { try? root.delete() }
    let configPath = root + ".md-utils/md-utils.json"
    let original = try Data(contentsOf: URL(fileURLWithPath: configPath.string))
    let preview = try ConfigMigrator.migrate(configPath: configPath, to: "0.3.0", dryRun: true)
    #expect(preview.files.count == 5)
    #expect(preview.warnings.contains { $0.contains("malformed") })
    #expect(!(root + ".md-utils/types").exists)
    #expect(try Data(contentsOf: URL(fileURLWithPath: configPath.string)) == original)
    _ = try ConfigMigrator.migrate(configPath: configPath, to: "0.3.0")
    #expect(try Data(contentsOf: URL(fileURLWithPath: (root + ".md-utils/md-utils.legacy-0.2.0.json").string)) == original)
    let loaded = try MdUtilsConfig.load(from: configPath)
    #expect(loaded.schemaRules.map(\.name) == ["books"])
    #expect(loaded.schemaRules.first?.standaloneFile != nil)
    try (root + "good.md").write("---\ntitle: Book\n---\n# Book")
    try (root + "bad.md").write("# Book")
    try (root + "hint.md").write("---\ntitle: Book\n$md-utils:\n  typeHints: invalid\n---\n# Book")
    let result = try await RulesValidatorRunner.validate(configPath: configPath)
    #expect(result.results.count == 3)
    #expect(result.results.filter { $0.status == .ok }.count == 1)
    #expect(result.results.filter { $0.status == .error }.count == 2)
    #expect(try ConfigMigrator.migrate(configPath: configPath, to: "0.3.0").changed == false)
  }

  @Test
  func `Standalone commands preserve unrelated files and explain grouped selection`() async throws {
    let root = try project()
    defer { try? root.delete() }
    let config = root + ".md-utils/md-utils.json"
    _ = try ConfigMigrator.migrate(configPath: config, to: "0.3.0")
    let original = try (root + ".md-utils/rules/books.mdrule.json").read(.utf8)
    let created = try RuleManager.addStandaloneRule(name: "other", type: "books.mdtype.json", path: "Other/**", tag: nil, configPath: config)
    #expect(created.exists)
    let description = try RuleDescriptionBuilder.describe(ruleName: "other", configPath: config)
    #expect(RuleDescriptionJSONRenderer.render(description)["source"] as? String == created.string)
    #expect(RulesListFormatter.render(try MdUtilsConfig.load(from: config), verbose: true).contains("books.mdtype.json"))
    try (root + "good.md").write("---\ntitle: Book\n---\n")
    let evaluations = try await RulesValidatorRunner.rulesMatching(fileName: (root + "good.md").string, configPath: config)
    #expect(evaluations.filter(\.matched).map { $0.rule.name } == ["books"])
    #expect(evaluations.first?.reasons.contains { $0.contains("types") } == true)
    _ = try RuleManager.removeRule(named: "other", deleteSchema: false, configPath: config)
    #expect(!created.exists)
    #expect(try (root + ".md-utils/rules/books.mdrule.json").read(.utf8) == original)
    #expect((root + ".md-utils/types/books.mdtype.json").exists)
    let custom = root + "custom.json"
    try custom.write("{\"configVersion\":\"0.3.0\"}")
    #expect(throws: (any Error).self) { try MdUtilsConfig.load(from: custom) }
    #expect(try MdUtilsConfig.load(from: custom, projectRoot: root).schemaRules.count == 1)
  }

  @Test
  func `Migration resumes verified artifacts left before active config replacement`() throws {
    let root = try project()
    defer { try? root.delete() }
    let path = root + ".md-utils/md-utils.json"
    let original = try path.read(.utf8)
    _ = try ConfigMigrator.migrate(configPath: path, to: "0.3.0")
    let type = try (root + ".md-utils/types/books.mdtype.json").read(.utf8)
    // Reconstruct the documented interruption state: generated files, legacy config active.
    try path.write(original)
    _ = try ConfigMigrator.migrate(configPath: path, to: "0.3.0")
    #expect(try (root + ".md-utils/types/books.mdtype.json").read(.utf8) == type)
    try path.write(original)
    try (root + ".md-utils/rules/unrelated.mdrule.json").write("{\"name\":\"unrelated\",\"types\":\"books.mdtype.json\"}")
    #expect(throws: (any Error).self) { try ConfigMigrator.migrate(configPath: path, to: "0.3.0") }
    #expect(try path.read(.utf8) == original)
  }

  @Test
  func `Migration refuses collisions and optional schemas before writing`() throws {
    let root = try project()
    defer { try? root.delete() }
    let configPath = root + ".md-utils/md-utils.json"
    try (root + ".md-utils/types").mkpath()
    try (root + ".md-utils/types/books.mdtype.json").write("{}")
    #expect(throws: (any Error).self) { try ConfigMigrator.migrate(configPath: configPath, to: "0.3.0") }
    #expect(!(root + ".md-utils/md-utils.legacy-0.2.0.json").exists)
    try (root + ".md-utils/types/books.mdtype.json").delete()
    try MdUtilsConfig(schemaRules: [Rule(name: "books", schema: "book.schema.json", frontmatterRequired: false,
      match: .init(paths: ["**/*.md"]))]).save(to: configPath)
    #expect(throws: (any Error).self) { try ConfigMigrator.migrate(configPath: configPath, to: "0.3.0") }
    #expect(!(root + ".md-utils/md-utils.legacy-0.2.0.json").exists)
  }

  private func project() throws -> Path {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let root = Path(repo.path) + "tmp/standalone-integration-\(UUID().uuidString)"
    try (root + ".md-utils/schemas").mkpath()
    try (root + ".md-utils/schemas/book.schema.json").write("{\"type\":\"object\",\"required\":[\"title\"]}")
    try MdUtilsConfig(schemaRules: [Rule(name: "books", schema: "book.schema.json", match: .init(paths: ["**/*.md"]))])
      .save(to: root + ".md-utils/md-utils.json")
    return root
  }
}
