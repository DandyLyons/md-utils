import Foundation
import MarkdownUtilitiesCore
import Testing
@testable import md_utils

struct SetStringRoundTripTests {
  @Test(.bug("https://github.com/DandyLyons/md-utils/issues/164"), arguments: ["yaml", "toml"])
  func emptyStringSurvivesCLIAndStringSchema(format: String) async throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "example.md")
    let body = "# Body\n\nKeep this text.\n"
    let source = format == "yaml"
      ? "---\nsummary: null\nuntouched: null\n---\n" + body
      : "+++\nsummary = \"before\"\n+++\n" + body
    try Data(source.utf8).write(to: file)

    let set = try CLIProcessTestHelper.run([
      "fm", "set", "--key", "summary", "--value", "", file.path,
    ])
    #expect(set.status == 0)
    let content = try String(contentsOf: file, encoding: .utf8)
    let document = try MarkdownDocument(content: content)
    #expect(document.getValue(forKey: "summary") == .string(""))
    #expect(document.body == body)
    #expect(document.frontMatterFormat == (format == "yaml" ? .yaml : .toml))
    if format == "yaml" {
      #expect(document.getValue(forKey: "untouched") == .null)
    }

    let get = try CLIProcessTestHelper.run([
      "fm", "get", "--key", "summary", file.path,
    ])
    #expect(get.status == 0)
    let rows = try #require(
      JSONSerialization.jsonObject(with: Data(get.standardOutput.utf8)) as? [[String: Any]]
    )
    #expect(try #require(rows.first)["value"] as? String == "")

    let schema = try JSONValue(any: [
      "type": "object",
      "required": ["summary"],
      "properties": ["summary": ["type": "string"]],
    ])
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Summary"),
      version: "1.0.0",
      frontmatter: MarkdownFrontmatterDefinition(schemas: [.inline(schema)]),
    )
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    #expect(try await checker.assess(MarkdownRecord(content: content), as: "Summary").conforms)
    if format == "yaml" {
      #expect(try await checker.assess(MarkdownRecord(content: source), as: "Summary").conforms == false)
    }
  }

  @Test(arguments: ["null", "~", "true", "42", "1.5"])
  func yamlStringsRetainTheirExplicitType(value: String) throws {
    var document = try MarkdownDocument(content: "---\nuntouched: null\n---\nBody\n")
    document.setValue(value, forKey: "summary")
    let reread = try MarkdownDocument(content: document.render())
    #expect(reread.getValue(forKey: "summary") == .string(value))
    #expect(reread.getValue(forKey: "untouched") == .null)
    #expect(reread.body == document.body)
  }

  @Test(arguments: ["absent", "missing", "string", "null", "toml"])
  func explicitNullSurvivesCLIWriteRead(state: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "example.md")
    let body = "# Body\n\nKeep this text.\n"
    let header: String
    switch state {
    case "absent": header = ""
    case "missing": header = "---\ntitle: Example\n---\n"
    case "string": header = "---\nsummary: before\n---\n"
    case "toml": header = "+++\nsummary = \"before\"\n+++\n"
    default: header = "---\nsummary: null\n---\n"
    }
    try Data((header + body).utf8).write(to: file)
    let extra = state == "toml" ? ["--frontmatter-format", "yaml"] : []
    let set = try CLIProcessTestHelper.run([
      "fm", "set", "--key", "summary", "--null",
    ] + extra + [file.path])
    #expect(set.status == 0)
    let document = try MarkdownDocument(content: String(contentsOf: file, encoding: .utf8))
    #expect(document.getValue(forKey: "summary") == .null)
    #expect(document.frontMatterFormat == .yaml)
    #expect(document.body == body)
    let get = try CLIProcessTestHelper.run(["fm", "get", "--key", "summary", file.path])
    #expect(get.status == 0)
    let rows = try #require(
      JSONSerialization.jsonObject(with: Data(get.standardOutput.utf8)) as? [[String: Any]]
    )
    #expect(try #require(rows.first)["value"] is NSNull)
  }

  @Test(arguments: [
    [String](),
    ["--value", "", "--null"],
    ["--value", "null", "--null"],
    ["--null", "--frontmatter-format", "toml"],
  ])
  func rejectsInvalidNullOptionsWithoutWriting(extra: [String]) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "example.md")
    let source = "---\nsummary: before\n---\nBody\n"
    try Data(source.utf8).write(to: file)
    let result = try CLIProcessTestHelper.run(["fm", "set", "--key", "summary"] + extra + [file.path])
    #expect(result.status != 0)
    #expect(result.standardError.contains(extra.contains("toml")
      ? "TOML cannot represent null" : "Supply exactly one of --value or --null"))
    #expect(try String(contentsOf: file, encoding: .utf8) == source)
  }

  @Test
  func nullBatchRejectsTOMLAndContinuesWithYAML() throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let toml = workspace.appending(path: "a.md")
    let yaml = workspace.appending(path: "b.md")
    let source = "+++\nsummary = \"before\"\n+++\nBody\n"
    try Data(source.utf8).write(to: toml)
    try Data("---\nsummary: before\n---\nBody\n".utf8).write(to: yaml)
    let result = try CLIProcessTestHelper.run([
      "fm", "set", "--key", "summary", "--null", toml.path, yaml.path,
    ])
    #expect(result.status == 1)
    #expect(result.standardError.contains("TOML cannot represent null"))
    #expect(try String(contentsOf: toml, encoding: .utf8) == source)
    let document = try MarkdownDocument(content: String(contentsOf: yaml, encoding: .utf8))
    #expect(document.getValue(forKey: "summary") == .null)
    #expect(document.body == "Body\n")
  }

  private func makeWorkspace() throws -> URL {
    let root = URL(filePath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let workspace = root.appending(path: "tmp/set-string-\(UUID().uuidString)/", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    return workspace
  }
}
