import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit
import Testing
@testable import md_utils

// Regression fixtures isolate native rule-selection and unsupported-target behavior.
// Each test owns a project-local directory and removes it after the assertion.
struct RelationshipRegressionCommandsTests {
  private func fixture() throws -> Path {
    let root = Path(#filePath).parent().parent().parent().parent() + "tmp/review-177-\(UUID().uuidString)/"
    try (root + ".md-utils/types/").mkpath()
    try (root + ".md-utils/rules/").mkpath()
    try (root + ".md-utils/md-utils.json").write("{\"configVersion\":\"0.3.0\"}")
    try (root + ".md-utils/types/person.mdtype.json").write("""
      {"md-utils-type-schema":"1","name":"Person","version":"1","frontmatter":{},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    try (root + ".md-utils/types/article.mdtype.json").write("""
      {"md-utils-type-schema":"2","name":"Article","version":"1","requires":["document-relationships"],
       "frontmatter":{},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
       "relationships":{"related":{"select":["related",{"each":true}],"target":{"type":"person.mdtype.json"}}}}
      """)
    return root
  }

  private func prepareIndex(root: Path) throws {
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    try database.prepareCollection(root: URL(fileURLWithPath: root.string).resolvingSymlinksInPath().path)
  }

  @Test(arguments: [true, false]) func `unrelated relationship definition does not broaden a local rule`(noIndex: Bool) async throws {
    let root = try fixture()
    defer { try? root.delete() }
    try (root + ".md-utils/rules/basic.mdrule.json").write("""
      {"name":"basic","match":{"paths":["A.md"]},"types":"person.mdtype.json"}
      """)
    try (root + "A.md").write("# A")
    try Data([0xff]).write(to: URL(fileURLWithPath: (root + "unrelated.md").string))
    if !noIndex { try prepareIndex(root: root) }
    let result = try await RulesValidatorRunner.validate(ruleName: "basic", root: root,
      configPath: root + ".md-utils/md-utils.json", projectRoot: root, noIndex: noIndex)
    #expect(result.hasFailures == false)
    try (root + ".md-utils/types/article.mdtype.json").delete()
    let baseline = try await RulesValidatorRunner.validate(ruleName: "basic", root: root,
      configPath: root + ".md-utils/md-utils.json", projectRoot: root, noIndex: true)
    #expect(baseline.hasFailures == false)
  }

  @Test(arguments: [true, false]) func `native unsupported attachment is not certified by an empty type`(noIndex: Bool) async throws {
    let root = try fixture()
    defer { try? root.delete() }
    try (root + ".md-utils/rules/articles.mdrule.json").write("""
      {"name":"articles","match":{"paths":["A.md"]},"types":"article.mdtype.json"}
      """)
    try (root + "A.md").write("---\nrelated: ['[[./B.pdf]]']\n---\n")
    try (root + "B.pdf").write("%PDF-1.4")
    if !noIndex { try prepareIndex(root: root) }
    let result = try await RulesValidatorRunner.validate(ruleName: "articles", includeNonMarkdown: true, root: root,
      configPath: root + ".md-utils/md-utils.json", projectRoot: root, noIndex: noIndex)
    #expect(result.hasFailures)
  }

  @Test(arguments: [false, true]) func `native type hint verification receives collection context`(indexed: Bool) async throws {
    let root = try fixture()
    defer { try? root.delete() }
    try (root + "A.md").write("---\n$md-utils:\n  typeHints: [Article]\nrelated: ['[[B]]']\n---\n")
    try (root + "B.md").write("# B")
    if indexed { try prepareIndex(root: root) }
    let result = try await TypesRunner.verifiedHints(files: [root + "A.md"], root: root)
    #expect(result.first?.1.first?.status == .confirmed)
    let cli = try CLIProcessTestHelper.run(["types", "verify", (root + "A.md").string,
      "--root", root.string, "--format", "json", "--include-confirmed"])
    #expect(cli.status == 0)
    #expect(cli.standardOutput.contains("confirmed"))
  }
}
