import Foundation
import MarkdownUtilitiesCore
import Testing
@testable import md_utils

struct InstanceCreationTests {
  struct Fixture {
    let root: URL
    init() throws {
      root = URL(fileURLWithPath: "tmp/creation-\(UUID().uuidString)/").standardizedFileURL
      try FileManager.default.createDirectory(at: root.appendingPathComponent(".md-utils/types/"), withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: root.appendingPathComponent(".md-utils/rules/"), withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: root.appendingPathComponent("Books/"), withIntermediateDirectories: true)
      try write(".md-utils/md-utils.json", #"{"configVersion":"0.3.0"}"#)
      try write(".md-utils/types/book.mdtype.json", ##"{"md-utils-type-schema":"1","name":"Book","version":"1","frontmatter":{},"body":{"requirements":[{"id":"review","heading":{"text":"Review","level":2}}],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},"creation":{"template":{"inline":"# {{ title }}","inputSchema":{"inline":{"type":"object","properties":{"title":{"type":"string","default":"Dune"}}}}}}}"##)
      try write(".md-utils/rules/books.mdrule.json", #"{"name":"Books","types":"book.mdtype.json","match":{"paths":["Books/**"]},"creation":{"directory":"./Books/"}}"#)
      try write("input.json", "{}")
    }
    func write(_ path: String, _ value: String) throws {
      try value.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    var typeArgs: [String] {
      ["types", "new", "--type", "Book", "--root", root.path, "--value", root.appendingPathComponent("input.json").path]
    }
    var ruleArgs: [String] {
      ["rules", "new", "--rule", "Books", "--config", root.appendingPathComponent(".md-utils/md-utils.json").path,
       "--value", root.appendingPathComponent("input.json").path]
    }
  }

  @Test func typeCreationWritesNonconformingInstanceAndReportsIt() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let result = try CLIProcessTestHelper.run(fixture.typeArgs + ["--filename-data", "$.title", fixture.root.appendingPathComponent("Books/").path])
    try #require(result.status == 0, "\(result.standardError)")
    #expect(result.standardOutput.contains("Type \"Book\": does not conform (advisory)"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Books/Dune.md"), encoding: .utf8) == "# Dune")
  }

  @Test(arguments: ["txt", ""])
  func ruleCreationSupportsExtensionsAndReportsBothAssessments(_ ext: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let result = try CLIProcessTestHelper.run(fixture.ruleArgs + ["--filename-data", "$.title", "--extension", ext])
    try #require(result.status == 0, "\(result.standardError)")
    #expect(result.standardOutput.contains("Type \"Book\""))
    #expect(result.standardOutput.contains("Rule \"Books\""))
    #expect(result.standardOutput.contains("Review"))
    let name = "Books/Dune" + (ext.isEmpty ? "" : "." + ext)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent(name), encoding: .utf8) == "# Dune")
  }

  @Test func dryRunAndCollisionsPreserveDirectory() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let args = fixture.typeArgs + ["--filename", "Dune", fixture.root.appendingPathComponent("Books/").path]
    let preview = try CLIProcessTestHelper.run(args + ["--dry-run"])
    try #require(preview.status == 0, "\(preview.standardError)")
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Books/").path).isEmpty)
    try fixture.write("Books/Dune", "existing")
    let collision = try CLIProcessTestHelper.run(args)
    #expect(collision.status != 0)
    #expect(collision.standardError.contains("already exists"))
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Books/Dune"), encoding: .utf8) == "existing")
  }

  @Test(arguments: ["[]", #"{"title":1}"#])
  func badInputBlocksWriting(_ input: String) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("input.json", input)
    let result = try CLIProcessTestHelper.run(fixture.ruleArgs + ["--filename", "Dune.md"])
    #expect(result.status != 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Books/").path).isEmpty)
  }

  @Test func atomicCreationDoesNotReplaceAnExistingDestination() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let destination = fixture.root.appendingPathComponent("Books/Dune.md")
    try InstanceCreation.create(Data("first".utf8), at: destination)
    #expect(throws: (any Error).self) { try InstanceCreation.create(Data("second".utf8), at: destination) }
    #expect(try String(contentsOf: destination, encoding: .utf8) == "first")
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Books/").path) == ["Dune.md"])
  }

  @Test(arguments: [
    ["--filename", "Dune.md", "--filename-data", "$.title"],
    ["--filename", "Dune.md", "--extension", "txt"],
    ["--filename-data", "$.missing"],
    ["--filename-data", "$.*"],
    ["--filename", "../escape.md"],
    [],
  ])
  func filenameFailuresLeaveNoFiles(_ flags: [String]) throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.write("input.json", #"{"title":"Dune","other":"Foundation"}"#)
    let result = try CLIProcessTestHelper.run(fixture.ruleArgs + flags)
    #expect(result.status != 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Books/").path).isEmpty)
  }

  @Test func referencedTemplateAndSchemaResolveRelativeToDefinition() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let file = fixture.root.appendingPathComponent(".md-utils/types/book.mdtype.json")
    var value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file)).objectValue ?? [:]
    value["creation"] = .object(["template": .object(["ref": .string("./book.knap"), "inputSchema": .object(["ref": .string("./input.json")])])])
    try JSONEncoder().encode(JSONValue.object(value)).write(to: file)
    try fixture.write(".md-utils/types/book.knap", "{{ title | h1 }}")
    try fixture.write(".md-utils/types/input.json", #"{"properties":{"title":{"default":"Dune"}}}"#)
    let result = try CLIProcessTestHelper.run(fixture.ruleArgs + ["--filename-data", "$.title"])
    try #require(result.status == 0, "\(result.standardError)")
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Books/Dune.md"), encoding: .utf8) == "# Dune")
  }

  @Test func missingDirectoryAndMissingRuleTargetFail() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let missing = try CLIProcessTestHelper.run(fixture.typeArgs + ["--filename", "Dune", fixture.root.appendingPathComponent("Missing/").path])
    #expect(missing.status != 0)
    #expect(missing.standardError.contains("must already exist"))
    try fixture.write(".md-utils/rules/books.mdrule.json", #"{"name":"Books","types":"book.mdtype.json","match":{"paths":["Books/**/*.md"]}}"#)
    let rule = try CLIProcessTestHelper.run(fixture.ruleArgs + ["--filename", "Dune.md"])
    #expect(rule.status != 0)
    #expect(rule.standardError.contains("creation.directory"))
  }

  @Test func multipleRuleTypesRequireExplicitCreationType() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let book = try String(contentsOf: fixture.root.appendingPathComponent(".md-utils/types/book.mdtype.json"), encoding: .utf8)
    try fixture.write(".md-utils/types/other.mdtype.json", book.replacingOccurrences(of: "\"name\":\"Book\"", with: "\"name\":\"Other\""))
    try fixture.write(".md-utils/rules/books.mdrule.json", #"{"name":"Books","types":{"anyOf":["book.mdtype.json","other.mdtype.json"]},"creation":{"directory":"./Books/"}}"#)
    let ambiguous = try CLIProcessTestHelper.run(fixture.ruleArgs + ["--filename", "Dune.md"])
    #expect(ambiguous.status != 0)
    #expect(ambiguous.standardError.contains("creation.type"))
    try fixture.write(".md-utils/rules/books.mdrule.json", #"{"name":"Books","types":{"anyOf":["book.mdtype.json","other.mdtype.json"]},"creation":{"directory":"./Books/","type":"Book"}}"#)
    let explicit = try CLIProcessTestHelper.run(fixture.ruleArgs + ["--filename", "Dune.md"])
    try #require(explicit.status == 0, "\(explicit.standardError)")
  }

  @Test func typeDestinationMayBeOutsideDefinitionProject() throws {
    let fixture = try Fixture()
    let outside = try Fixture()
    defer { fixture.remove(); outside.remove() }
    let result = try CLIProcessTestHelper.run(fixture.typeArgs + ["--filename", "Dune", outside.root.appendingPathComponent("Books/").path])
    try #require(result.status == 0, "\(result.standardError)")
    #expect(try String(contentsOf: outside.root.appendingPathComponent("Books/Dune"), encoding: .utf8) == "# Dune")
  }
}
