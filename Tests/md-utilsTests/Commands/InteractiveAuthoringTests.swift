import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import md_utils

@Suite("Interactive 0.3.0 authoring")
struct InteractiveAuthoringTests {
  @Test
  func `Shared rule flow creates a nested type only after complete preview and confirmation`() throws {
    let root = try project()
    defer { try? root.delete() }
    let script = Script(choices: ["Create", "Create new type", "Done", "Done"],
      texts: ["books", "nested/books.mdrule.json", "book", "1.0.0", "nested/book.mdtype.yaml"])
    script.onConfirm = {
      #expect((root + ".md-utils/types/nested/book.mdtype.yaml").exists == false)
      #expect((root + ".md-utils/rules/nested/books.mdrule.json").exists == false)
      #expect(script.output.contains { $0.contains("Create") && $0.contains("nested/book.mdtype.yaml") && $0.contains("nested/books.mdrule.json") })
    }
    try InteractiveAuthoring(prompts: script.prompts).run(types: false, selectedName: nil, root: root)
    let loaded = try MarkdownStandaloneRuleProject(configPath: root + ".md-utils/md-utils.json")
    #expect(loaded.files.first?.types == .reference("nested/book.mdtype.yaml"))
    #expect(loaded.types.definition(named: "book")?.version == "1.0.0")
    #expect(script.choices.isEmpty && script.texts.isEmpty)
  }

  @Test(arguments: [false, true])
  func `Decline and cancellation discard shared type drafts without changing project`(cancel: Bool) throws {
    let root = try project()
    defer { try? root.delete() }
    let before = try snapshot(root)
    let script = Script(choices: ["Create", "Create new type", "Done", cancel ? "Cancel" : "Done"],
      texts: ["books", "books.mdrule.json", "book", "1", "book.mdtype.json"], confirmed: false)
    try InteractiveAuthoring(prompts: script.prompts).run(types: false, selectedName: nil, root: root)
    #expect(try snapshot(root) == before)
    #expect(script.output.contains { $0.contains("Cancelled") })
  }

  @Test(arguments: ["yaml", "yml", "json", "toml"])
  func `Type edit preserves source format schemas and all constraints and remove preserves other files`(suffix: String) throws {
    let root = try project()
    defer { try? root.delete() }
    let path = root + ".md-utils/types/nested/original.mdtype.\(suffix)"
    var definition = MarkdownTypeDefinition(name: .init(rawValue: "book"), version: "1",
      frontmatter: .init(presence: .optional, schemas: [.reference("../../schemas/book.schema.json")]),
      body: .init(requirements: [.init(id: "title", predicate: .heading(.init(text: "Title", level: 1)))],
        recommendations: [.init(id: "short", predicate: .maxBodyWords(400))]),
      context: .init(requirements: [.init(id: "path", predicate: .path(.init(glob: "Books/**")))]), source: path.string)
    try path.parent().mkpath()
    try path.write(InteractiveDraftSession.encode(definition, path: path))
    let schema = try (root + ".md-utils/schemas/book.schema.json").read(.utf8)
    let script = Script(choices: ["Edit", "Done"], texts: ["renamed", "2"])
    try InteractiveAuthoring(prompts: script.prompts).run(types: true, selectedName: "book", root: root)
    definition.name = .init(rawValue: "renamed")
    definition.version = "2"
    #expect(try MarkdownTypeDefinitionDecoder.decode(path.read(.utf8), format: InteractiveDraftSession.format(path), source: path.string) == definition)
    let remove = Script(choices: ["Remove"])
    try InteractiveAuthoring(prompts: remove.prompts).run(types: true, selectedName: "renamed", root: root)
    #expect(path.exists == false)
    #expect(try (root + ".md-utils/schemas/book.schema.json").read(.utf8) == schema)
    #expect((root + ".md-utils/types/keep.txt").exists)
  }

  @Test
  func `Rule edit preserves recursive expressions schema and nested source then removal preserves types`() throws {
    let root = try project()
    defer { try? root.delete() }
    try seedType(root)
    let path = root + ".md-utils/rules/nested/original.mdrule.json"
    try path.parent().mkpath()
    try path.write(#"{"$schema":"editor-schema","name":"books","types":{"not":{"not":"book.mdtype.json"}},"match":{"anyOf":[{"paths":["Books/**"]},{"frontmatter":{"status":{"equals":"published"}}}]}}"#)
    let original = try MarkdownRuleFile.decode(path.read(.utf8), source: path.string)
    let script = Script(choices: ["Edit", "Done"], texts: ["renamed"])
    try InteractiveAuthoring(prompts: script.prompts).run(types: false, selectedName: "books", root: root)
    let updated = try MarkdownRuleFile.decode(path.read(.utf8), source: path.string)
    #expect(updated.name == "renamed")
    #expect(updated.match == original.match && updated.types == original.types && updated.schemaReference == original.schemaReference)
    let remove = Script(choices: ["Remove"])
    try InteractiveAuthoring(prompts: remove.prompts).run(types: false, selectedName: "renamed", root: root)
    #expect(path.exists == false)
    #expect((root + ".md-utils/types/book.mdtype.json").exists)
    #expect((root + ".md-utils/rules/legacy/invalid.mdrule.json").exists)
  }

  @Test
  func `Validation failures and referenced type removal never reach confirmation`() throws {
    let root = try project()
    defer { try? root.delete() }
    try seedType(root)
    let rule = root + ".md-utils/rules/books.mdrule.json"
    try rule.write(#"{"name":"books","types":"book.mdtype.json"}"#)
    let before = try snapshot(root)
    var removal = InteractiveDraftSession(root: root)
    try removal.stage(path: root + ".md-utils/types/book.mdtype.json", content: nil)
    let script = Script()
    #expect(throws: (any Error).self) { try InteractiveAuthoring(prompts: script.prompts).finish(removal) }
    #expect(script.confirmations == 0)
    for content in [
      #"{"name":"invalid","types":"missing.mdtype.json"}"#,
      #"{"name":"books","types":"book.mdtype.json"}"#,
      #"{"name":"invalid","types":{"oneOf":["book.mdtype.json","book.mdtype.json"]}}"#,
      #"{"name":"invalid","types":"book.mdtype.json","match":{"frontmatterQuery":{"jmespath":"["}}}"#,
      #"{"name":"invalid","types":"book.mdtype.json","checks":[]}"#
    ] {
      var session = InteractiveDraftSession(root: root)
      try session.stage(path: root + ".md-utils/rules/invalid.mdrule.json", content: content, creating: true)
      #expect(throws: (any Error).self) { try session.validate() }
    }
    #expect(try snapshot(root) == before)
  }

  @Test
  func `Duplicate type IDs missing schemas and destination escapes are rejected`() throws {
    let root = try project()
    defer { try? root.delete() }
    try seedType(root)
    let before = try snapshot(root)
    for definition in [
      MarkdownTypeDefinition(name: .init(rawValue: "book"), version: "1"),
      MarkdownTypeDefinition(name: .init(rawValue: "other"), version: "1", frontmatter: .init(schemas: [.reference("../schemas/missing.json")])),
      MarkdownTypeDefinition(name: .init(rawValue: "other"), version: "1", body: .init(requirements: [
        .init(id: "same", predicate: .maxBodyLines(1)), .init(id: "same", predicate: .maxBodyWords(1))]))
    ] {
      var session = InteractiveDraftSession(root: root)
      let path = root + ".md-utils/types/other.mdtype.json"
      try session.stage(path: path, content: InteractiveDraftSession.encode(definition, path: path), creating: true)
      #expect(throws: (any Error).self) { try session.validate() }
    }
    let session = InteractiveDraftSession(root: root)
    for reference in ["../evil.mdtype.json", "/evil.mdtype.json", "a/../evil.mdtype.yaml", "book", "https://example.com/a.mdtype.json"] {
      #expect(throws: (any Error).self) { try session.resourcePath(reference, types: true) }
    }
    #expect(throws: (any Error).self) { try session.resourcePath("legacy/evil.mdrule.json", types: false) }
    #expect(try snapshot(root) == before)
  }

  @Test
  func `Save refuses resources modified since draft began`() throws {
    let root = try project()
    defer { try? root.delete() }
    try seedType(root)
    let path = root + ".md-utils/types/book.mdtype.json"
    var session = InteractiveDraftSession(root: root)
    try session.stage(path: path, content: path.read(.utf8))
    try path.write(TypesProject.scaffold(name: "book", version: "changed", format: .json))
    #expect(throws: (any Error).self) { try session.commit() }
    #expect(try path.read(.utf8).contains("changed"))
  }

  @Test
  func `Commands use explicit project root and reject legacy config`() async throws {
    let root = try project()
    defer { try? root.delete() }
    let custom = root + "custom.json"
    try custom.write(#"{"configVersion":"0.3.0"}"#)
    let options = try RuleProjectOptions.parse(["--config", custom.string, "--project-root", root.string + "/"])
    #expect(try options.load().standaloneProject?.projectRoot == root)
    try custom.write(#"{"configVersion":"0.2.0","rules":[]}"#)
    var command = try CLIEntry.TypesCommands.Interactive.parse(["--config", custom.string])
    await #expect(throws: (any Error).self) { try await command.run() }
    var ruleCommand = try CLIEntry.RulesCommands.Interactive.parse(["--config", custom.string])
    await #expect(throws: (any Error).self) { try await ruleCommand.run() }
  }

  @Test
  func `Specialized type prompts author schema presence and required and recommended constraints`() throws {
    let root = try project()
    defer { try? root.delete() }
    let script = Script(choices: ["Create", "Frontmatter presence", "optional", "Schema references", "Add reference", "Done",
      "Body constraints", "Add requirement", "heading", "1", "Add recommendation", "maxBodyWords", "Done",
      "Context constraints", "Add requirement", "path", "Done", "Done"],
      texts: ["book", "1", "book.mdtype.json", "../schemas/book.schema.json", "title", "Title", "short", "100", "location", "Books/**"])
    try InteractiveAuthoring(prompts: script.prompts).run(types: true, selectedName: nil, root: root)
    let type = try #require(MarkdownTypeFileRegistryLoader.load(projectRoot: root).definition(named: "book"))
    #expect(type.frontmatter.presence == .optional)
    #expect(type.frontmatter.schemas == [.reference("../schemas/book.schema.json")])
    #expect(type.body.requirements == [.init(id: "title", predicate: .heading(.init(text: "Title", level: 1)))])
    #expect(type.body.recommendations == [.init(id: "short", predicate: .maxBodyWords(100))])
    #expect(type.context.requirements == [.init(id: "location", predicate: .path(.init(glob: "Books/**")))])
    #expect(script.choices.isEmpty && script.texts.isEmpty)
  }

  @Test
  func `Rule prompts compose types and author every matcher domain`() throws {
    let root = try project()
    defer { try? root.delete() }
    try seedType(root)
    let script = Script(choices: ["Create", "not", "not", "Existing type", "book.mdtype.json", "Matcher expression", "Build expression",
      "allOf", "Matcher leaf", "paths", "Done", "excludePaths", "Done", "file", "filenameEquals", "Done",
      "frontmatter", "frontmatterQuery", "document", "hasHeading", "Done", "Done", "Add child", "not", "Matcher leaf",
      "paths", "Done", "Done", "Done", "Done"],
      texts: ["books", "books.mdrule.json", "Books/**", "Books/drafts/**", #""book.md""#, "status", #"{"equals":"published"}"#,
        "status == 'published'", #""Title""#, "Archive/**"])
    try InteractiveAuthoring(prompts: script.prompts).run(types: false, selectedName: nil, root: root)
    let project = try MarkdownStandaloneRuleProject(configPath: root + ".md-utils/md-utils.json")
    let file = try #require(project.files.first)
    #expect(file.types == .not(.not(.reference("book.mdtype.json"))))
    let group = try #require(file.match?.objectValue?["allOf"])
    guard case .array(let children) = group else {
      Issue.record("Expected allOf children")
      return
    }
    let leaf = try #require(children.first?.objectValue)
    #expect(Set(leaf.keys) == ["paths", "excludePaths", "file", "frontmatter", "frontmatterQuery", "document"])
    #expect(children.count == 2)
    #expect(script.choices.isEmpty && script.texts.isEmpty)
  }

  @Test
  func `Invalid draft can be corrected before confirmation and exact names are required`() throws {
    let root = try project()
    defer { try? root.delete() }
    try seedType(root)
    let script = Script(choices: ["Create", "Done", "Name and version", "Done"], texts: ["book", "1", "other.mdtype.json", "other", "1"])
    try InteractiveAuthoring(prompts: script.prompts).run(types: true, selectedName: nil, root: root)
    #expect(script.output.contains { $0.contains("Duplicate Markdown type name") })
    #expect(script.confirmations == 1)
    let missing = Script(choices: ["Edit"])
    #expect(throws: (any Error).self) {
      try InteractiveAuthoring(prompts: missing.prompts).run(types: true, selectedName: "boo", root: root)
    }
  }

  private func project() throws -> Path {
    let root = (Path(#filePath).parent().parent().parent().parent() + "tmp/interactive-\(UUID().uuidString)/").absolute().normalize()
    try (root + ".md-utils/types/").mkpath()
    try (root + ".md-utils/schemas/").mkpath()
    try (root + ".md-utils/rules/legacy/").mkpath()
    try (root + ".md-utils/md-utils.json").write("{\"configVersion\":\"0.3.0\"}\n")
    try (root + ".md-utils/schemas/book.schema.json").write(#"{"type":"object"}"#)
    try (root + ".md-utils/types/keep.txt").write("unrelated")
    try (root + ".md-utils/rules/legacy/invalid.mdrule.json").write("preserve invalid legacy payload")
    return root
  }

  private func seedType(_ root: Path) throws {
    try (root + ".md-utils/types/book.mdtype.json").write(TypesProject.scaffold(name: "book", version: "1", format: .json))
  }

  private func snapshot(_ root: Path) throws -> [String: Data] {
    try Dictionary(uniqueKeysWithValues: root.recursiveChildren().filter(\.isFile).map {
      ($0.string, try Data(contentsOf: URL(fileURLWithPath: $0.string)))
    })
  }
}

private final class Script {
  var choices: [String]
  var texts: [String]
  var output: [String] = []
  var confirmations = 0
  let confirmed: Bool
  var onConfirm: (() -> Void)?

  init(choices: [String] = [], texts: [String] = [], confirmed: Bool = true) {
    self.choices = choices
    self.texts = texts
    self.confirmed = confirmed
  }

  var prompts: InteractivePrompts {
    InteractivePrompts(choose: { question, options in
      let value = try #require(self.choices.first, "Unexpected choice: \(question)")
      self.choices.removeFirst()
      if value == "Cancel" { throw InteractiveCancellation.cancelled }
      #expect(options.contains(value), "\(question): \(value) not in \(options)")
      return value
    }, text: { question, _, _ in
      let value = try #require(self.texts.first, "Unexpected text: \(question)")
      self.texts.removeFirst()
      return value
    }, confirm: { _ in
      self.confirmations += 1
      self.onConfirm?()
      return self.confirmed
    }, output: { self.output.append($0) })
  }
}
