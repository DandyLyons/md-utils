import Foundation
import Testing

@Suite("non-MD rules CLI semantics")
struct RulesNonMDCLISemanticsTests {
  @Test
  func `rules validate is Markdown only by default and includes opted in source files`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }

    let defaultResult = try run(["rules", "validate", "swift-components", "--include-ok"], in: workspace)
    #expect(defaultResult.status == 0)
    #expect(defaultResult.standardOutput.contains("No files matched configured rules."))

    let includedResult = try run([
      "rules", "validate", "swift-components", "--include-non-md", "--include-ok",
    ], in: workspace)
    #expect(includedResult.status == 0)
    #expect(includedResult.standardOutput.contains("OK Sources/APIClient.swift"))
  }

  @Test
  func `rules files matching requires scan opt in for non-MD files`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }

    let defaultResult = try run(["rules", "files-matching", "swift-components"], in: workspace)
    #expect(defaultResult.status == 0)
    #expect(defaultResult.standardOutput.contains("No files matched"))

    let includedResult = try run([
      "rules", "files-matching", "swift-components", "--include-non-md",
    ], in: workspace)
    #expect(includedResult.status == 0)
    #expect(includedResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "Sources/APIClient.swift")
  }

  @Test
  func `rules matching opts in an explicit mapped file`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }

    let result = try run(["rules", "matching", "Sources/APIClient.swift"], in: workspace)

    #expect(result.status == 0)
    #expect(result.standardOutput.split(whereSeparator: \.isNewline).contains("swift-components"))
    #expect(result.standardOutput.contains("wrapper-is-not-body") == false)
  }

  @Test
  func `rules matching requires include non md for txt`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }

    let defaultResult = try run(["rules", "matching", "Notes/notes.txt"], in: workspace)
    #expect(defaultResult.status != 0)
    #expect(defaultResult.standardError.contains("--include-non-md"))

    let includedResult = try run([
      "rules", "matching", "Notes/notes.txt", "--include-non-md",
    ], in: workspace)
    #expect(includedResult.status == 0)
    #expect(includedResult.standardOutput.split(whereSeparator: \.isNewline).contains("text-frontmatter"))
  }

  @Test
  func `unmapped files support file and raw body predicates after opt in`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }

    let files = try run([
      "rules", "files-matching", "toml-file", "--include-non-md",
    ], in: workspace)
    #expect(files.status == 0)
    #expect(files.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "Config/settings.toml")

    let frontmatter = try run([
      "rules", "matching", "Config/settings.toml", "--explain",
    ], in: workspace)
    #expect(frontmatter.status != 0)
    #expect((frontmatter.standardOutput + frontmatter.standardError).contains("no frontmatter syntax mapping for extension \"toml\""))
  }

  @Test
  func `wrapped frontmatter and wrapper excluded body reach rule predicates and schema`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }

    let result = try run([
      "rules", "validate", "swift-components", "--include-non-md", "--include-ok",
    ], in: workspace)

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("OK Sources/APIClient.swift"))
    #expect(!result.standardOutput.contains("ERROR"))
  }

  @Test(arguments: [
    ("missing-frontmatter", "required by rule"),
    ("incomplete-frontmatter", "required by rule"),
    ("malformed-frontmatter", "invalid YAML"),
    ("multiple-frontmatter", "additional block opens at line 9"),
  ])
  func `wrapped frontmatter failures are deterministic`(_ ruleName: String, _ diagnostic: String) throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }

    let result = try run([
      "rules", "validate", ruleName, "--include-non-md",
    ], in: workspace)

    #expect(result.status != 0)
    #expect((result.standardOutput + result.standardError).contains(diagnostic))
  }

  @Test(arguments: ["source-heading", "source-section", "source-wikilink", "source-required-heading"])
  func `Markdown structural rules are unsupported for non-MD files`(_ ruleName: String) throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }

    let result = try run([
      "rules", "validate", ruleName, "--include-non-md",
    ], in: workspace)

    #expect(result.status != 0)
    #expect((result.standardOutput + result.standardError).contains("unsupported for non-Markdown files"))
  }

  @Test
  func `matching commands surface unsupported structure without explain`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }

    let listed = try run([
      "rules", "files-matching", "source-heading", "--include-non-md",
    ], in: workspace)
    #expect(listed.status != 0)
    #expect(listed.standardError.contains("unsupported for non-Markdown files"))

    let explicit = try run([
      "rules", "matching", "Sources/Structural.swift",
    ], in: workspace)
    #expect(explicit.status != 0)
    #expect(explicit.standardOutput.contains("ERROR: Markdown structural predicates are unsupported"))
  }

  @Test(arguments: ["validate", "files-matching", "matching"])
  func `rules help explains non-MD opt in`(_ command: String) throws {
    let result = try CLIProcessTestHelper.run(["rules", command, "--help"])

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("--include-non-md"))
    #expect(result.standardOutput.contains("NON-MARKDOWN FILES"))
  }

  private func run(_ arguments: [String], in workspace: URL) throws -> CLIProcessResult {
    try CLIProcessTestHelper.run(arguments, workingDirectory: workspace)
  }

  private func makeWorkspace() throws -> URL {
    let fixture = try fixtureDirectory()
      .appending(path: "project/", directoryHint: .isDirectory)
    let root = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
      .appending(path: "tmp/", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let workspace = root.appending(path: "md-utils-rules-non-md-\(UUID().uuidString)/", directoryHint: .isDirectory)
    try FileManager.default.copyItem(at: fixture, to: workspace)
    return workspace
  }

  private func fixtureDirectory() throws -> URL {
    try #require(Bundle.module.url(forResource: "RulesNonMD", withExtension: nil))
  }

  private func removeWorkspace(_ workspace: URL) {
    try? FileManager.default.removeItem(at: workspace)
  }
}
