import Foundation
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import MarkdownUtilities

@Suite("Standalone rule file storage")
struct MarkdownRuleFileStoreTests {
  @Test
  func `Discovery is recursive deterministic and excludes legacy contents`() throws {
    let root = try project()
    defer { try? root.delete() }
    let rules = root + ".md-utils/rules"
    try (rules + "nested").mkpath()
    try (rules + "legacy/deep").mkpath()
    try (rules + "z.mdrule.json").write(rule("z"))
    try (rules + "nested/a.mdrule.json").write(rule("a"))
    try (rules + "legacy/deep/broken.mdrule.json").write("not json")
    try (rules + "unrelated.json").write("not json")
    let store = MarkdownRuleFileStore(projectRoot: root)
    #expect(try store.load().map(\.name) == ["a", "z"])
    #expect(try store.load() == store.load())
    try (rules + "duplicate.mdrule.json").write(rule("z"))
    let error = try #require(throws: MarkdownRuleFileError.self) { try store.load() }
    #expect(error.errorDescription?.contains("duplicate.mdrule.json") == true)
    #expect(error.errorDescription?.contains("z.mdrule.json") == true)
  }

  @Test
  func `Creating and removing a rule preserves other files and resolves nested type identity`() throws {
    let root = try project()
    defer { try? root.delete() }
    let store = MarkdownRuleFileStore(projectRoot: root)
    #expect(try store.load().isEmpty)
    let first = try store.create(rule("first"), relativePath: "first.mdrule.json")
    let original = try Path(first.source).read(.utf8)
    let second = try store.create(rule("second"), relativePath: "nested/second.mdrule.json")
    #expect(try store.typeBindings(for: second)["nested/book.mdtype.json"]?.rawValue == "BookContract")
    let replacement = try store.replace(named: "second", with: rule("renamed"))
    #expect(replacement.source == second.source)
    #expect(try Path(first.source).read(.utf8) == original)
    #expect(throws: MarkdownRuleFileError.self) {
      try store.create(rule("first"), relativePath: "different.mdrule.json")
    }
    _ = try store.remove(named: "renamed")
    #expect(Path(second.source).exists == false)
    #expect(try Path(first.source).read(.utf8) == original)
    #expect((root + ".md-utils/types/nested/book.mdtype.json").exists)
    #expect(throws: MarkdownRuleFileError.self) {
      try store.create(rule("legacy"), relativePath: "legacy/hidden.mdrule.json")
    }
  }

  @Test(arguments: [
    "not JSON",
    "{\"name\":\"book\",\"types\":\"book\"}",
    "{\"name\":\"book\",\"types\":\"../book.mdtype.json\"}",
    "{\"name\":\"book\",\"types\":{\"anyOf\":[]}}",
    "{\"name\":\"book\",\"types\":{\"oneOf\":[\"book.mdtype.json\",\"book.mdtype.json\"]}}",
    "{\"name\":\"book\",\"types\":\"book.mdtype.json\",\"match\":{\"paths\":[\"**\"],\"anyOf\":[{}]}}",
    "{\"name\":\"book\",\"types\":\"book.mdtype.json\",\"match\":{\"unknown\":true}}",
  ])
  func `Invalid rule data reports its source`(_ content: String) throws {
    let error = try #require(throws: MarkdownRuleFileError.self) {
      try MarkdownRuleFile.decode(content, source: "rules/bad.mdrule.json")
    }
    #expect(error.source == "rules/bad.mdrule.json")
    #expect(error.message.isEmpty == false)
  }

  @Test
  func `Recursive expressions round trip and missing types never fall back by basename`() throws {
    let content = """
      {"name":"books","match":{"allOf":[{"paths":["Books/**"]},{"not":{"frontmatter":{"draft":{"equals":true}}}}]},
       "types":{"allOf":["nested/book.mdtype.json",{"anyOf":["other.mdtype.yaml",{"not":"archive.mdtype.toml"}]}]}}
      """
    let value = try MarkdownRuleFile.decode(content, source: "rule.json")
    #expect(try MarkdownRuleFile.decode(value.encoded(), source: "rule.json") == value)
    let root = try project()
    defer { try? root.delete() }
    let missing = try MarkdownRuleFile.decode("{\"name\":\"missing\",\"types\":\"book.mdtype.json\"}", source: "missing.mdrule.json")
    #expect(throws: MarkdownRuleFileError.self) {
      try MarkdownRuleFileStore(projectRoot: root).typeBindings(for: missing)
    }
  }

  private func rule(_ name: String) -> String {
    "{\"name\":\"\(name)\",\"types\":\"nested/book.mdtype.json\",\"match\":{\"paths\":[\"Books/**\"]}}"
  }

  private func project() throws -> Path {
    let repo = Path(#filePath).parent().parent().parent().parent()
    let root = repo + "tmp/rule-files-\(UUID().uuidString)"
    let types = root + ".md-utils/types/nested"
    try types.mkpath()
    try (types + "book.mdtype.json").write("""
      {"md-utils-type-schema":"1","name":"BookContract","version":"1",
       "frontmatter":{},"body":{"requirements":[],"recommendations":[]},
       "context":{"requirements":[],"recommendations":[]}}
      """)
    return root
  }
}
