import Foundation
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import md_utils

@Suite("non-MD frontmatter CLI semantics")
struct NonMDFrontmatterCLISemanticsTests {
  @Test(arguments: [nil, "dump", "get", "has", "list", "search", "set", "unique"] as [String?])
  func `relevant help pages explain valid wrapped frontmatter`(_ subcommand: String?) throws {
    var arguments = ["fm"]
    if let subcommand {
      arguments.append(subcommand)
    }
    arguments.append("--help")

    let result = try CLIProcessTestHelper.run(arguments)

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("FRONTMATTER ON NON-MD FILES"))
    #expect(result.standardOutput.contains("mapped opening wrapper"))
    #expect(result.standardOutput.contains("matching mapped closing wrapper"))
    #expect(result.standardOutput.contains("Incomplete blocks are treated as absent"))
    #expect(result.standardOutput.contains("blocks are invalid"))
  }

  @Test
  func `malformed YAML in the first wrapped block remains a YAML conversion error`() {
    let source = "/*\n---\ninvalid: yaml: syntax:\n---\n*/\n"

    #expect(throws: YAMLConversionError.self) {
      _ = try ParsedFrontMatterFile.parse(source: source, syntax: .wrapped(.cBlock))
    }
  }

  @Test
  func `an explicit supported non-Markdown file infers its wrapper without opt-in`() throws {
    let workspace = try makeWorkspace(from: "single-existing-swift")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "Example.swift").path,
      "--key", "title",
      "--value", "Updated Swift",
    ])

    #expect(result.status == 0)
    try expectWorkspace(workspace, matches: "single-existing-swift")
  }

  @Test
  func `an explicit txt file is ignored without include-non-md`() throws {
    let workspace = try makeWorkspace(from: "single-txt-ignored")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "notes.txt").path,
      "--key", "title",
      "--value", "Updated Plain Text",
    ])

    #expect(result.status != 0)
    #expect(result.standardError.lowercased().contains("ignored non-markdown file"))
    #expect(result.standardError.contains("--include-non-md"))
    try expectWorkspace(workspace, matches: "single-txt-ignored")
  }

  @Test
  func `include-non-md lets an explicit txt file use Markdown-style frontmatter`() throws {
    let workspace = try makeWorkspace(from: "single-txt-included")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "notes.txt").path,
      "--key", "title",
      "--value", "Updated Plain Text",
      "--include-non-md",
    ])

    #expect(result.status == 0)
    try expectWorkspace(workspace, matches: "single-txt-included")
  }

  @Test
  func `jsonc uses the c-block syntax mapping`() throws {
    let workspace = try makeWorkspace(from: "single-jsonc")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "settings.jsonc").path,
      "--key", "title",
      "--value", "Updated JSONC Configuration",
    ])

    #expect(result.status == 0)
    try expectWorkspace(workspace, matches: "single-jsonc")
  }

  @Test
  func `an explicit unsupported extension explains that no syntax mapping exists`() throws {
    let workspace = try makeWorkspace(from: "single-unsupported-toml")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "settings.toml").path,
      "--key", "status",
      "--value", "approved",
    ])

    #expect(result.status != 0)
    #expect(result.standardError.lowercased().contains("no frontmatter syntax mapping"))
    try expectWorkspace(workspace, matches: "single-unsupported-toml")
  }

  @Test
  func `a single file without non-MD frontmatter can be confirmed interactively`() throws {
    let workspace = try makeWorkspace(from: "single-missing-confirmed")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "Example.swift").path,
      "--key", "status",
      "--value", "approved",
    ], standardInput: "y\n")

    #expect(result.status == 0)
    #expect(result.standardError.contains("Create wrapped frontmatter using c-block (/* … */)? [y/N]"))
    try expectWorkspace(workspace, matches: "single-missing-confirmed")
  }

  @Test
  func `declining single-file creation preserves the file and fails the requested edit`() throws {
    let workspace = try makeWorkspace(from: "single-missing-declined")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "Example.swift").path,
      "--key", "status",
      "--value", "approved",
    ], standardInput: "n\n")

    #expect(result.status != 0)
    #expect(result.standardError.contains("[y/N]"))
    try expectWorkspace(workspace, matches: "single-missing-declined")
  }

  @Test
  func `create-frontmatter authorizes noninteractive single-file creation`() throws {
    let workspace = try makeWorkspace(from: "single-missing-create-flag")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "Example.swift").path,
      "--key", "status",
      "--value", "approved",
      "--create-frontmatter",
    ])

    #expect(result.status == 0)
    #expect(result.standardError.contains("[y/N]") == false)
    try expectWorkspace(workspace, matches: "single-missing-create-flag")
  }

  @Test
  func `create-frontmatter is accepted and ignored for ordinary Markdown`() throws {
    let workspace = try makeWorkspace(from: "markdown-create-flag-ignored")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "note.md").path,
      "--key", "status",
      "--value", "approved",
      "--create-frontmatter",
    ])

    #expect(result.status == 0)
    #expect(result.standardError.contains("[y/N]") == false)
    try expectWorkspace(workspace, matches: "markdown-create-flag-ignored")
  }

  @Test
  func `multiple non-MD frontmatter blocks refuse mutation and diagnose the second`() throws {
    let workspace = try makeWorkspace(from: "single-multiple-refused")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "Example.swift").path,
      "--key", "title",
      "--value", "Updated First Block",
    ])

    #expect(result.status != 0)
    #expect(result.standardError.lowercased().contains("multiple frontmatter blocks"))
    #expect(result.standardError.contains("line 9"))
    try expectWorkspace(workspace, matches: "single-multiple-refused")
  }

  @Test
  func `an explicit file list ignores non-Markdown files by default`() throws {
    let workspace = try makeWorkspace(from: "explicit-list-default")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set",
      workspace.appending(path: "note.md").path,
      workspace.appending(path: "Source.swift").path,
      "--key", "reviewed",
      "--value", "approved",
    ])

    #expect(result.status == 0)
    #expect(result.standardError.lowercased().contains("ignored non-markdown file"))
    #expect(result.standardError.contains("--include-non-md"))
    try expectWorkspace(workspace, matches: "explicit-list-default")
  }

  @Test
  func `include-non-md opts an explicit file list into syntax mapping`() throws {
    let workspace = try makeWorkspace(from: "explicit-list-included")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set",
      workspace.appending(path: "note.md").path,
      workspace.appending(path: "Source.swift").path,
      "--key", "reviewed",
      "--value", "approved",
      "--include-non-md",
    ])

    #expect(result.status == 0)
    #expect(result.standardError.contains("--include-non-md") == false)
    try expectWorkspace(workspace, matches: "explicit-list-included")
  }

  @Test
  func `a directory ignores non-Markdown files by default`() throws {
    let workspace = try makeWorkspace(from: "directory-default")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.path,
      "--key", "reviewed",
      "--value", "approved",
    ])

    #expect(result.status == 0)
    #expect(result.standardError.contains("--include-non-md") == false)
    try expectWorkspace(workspace, matches: "directory-default")
  }

  @Test
  func `include-non-md opts a directory into mapped non-Markdown extensions`() throws {
    let workspace = try makeWorkspace(from: "directory-included")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.path,
      "--key", "reviewed",
      "--value", "approved",
      "--include-non-md",
    ])

    #expect(result.status == 0)
    try expectWorkspace(workspace, matches: "directory-included")
  }

  @Test
  func `recursive directory traversal remains Markdown-only by default`() throws {
    let workspace = try makeWorkspace(from: "recursive-directory-default")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.path,
      "--key", "reviewed",
      "--value", "approved",
    ])

    #expect(result.status == 0)
    #expect(result.standardError.contains("--include-non-md") == false)
    try expectWorkspace(workspace, matches: "recursive-directory-default")
  }

  @Test
  func `include-non-md processes mapped files recursively`() throws {
    let workspace = try makeWorkspace(from: "recursive-directory-included")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.path,
      "--key", "reviewed",
      "--value", "approved",
      "--include-non-md",
    ])

    #expect(result.status == 0)
    try expectWorkspace(workspace, matches: "recursive-directory-included")
  }

  @Test
  func `batch mutation never prompts to create missing non-MD frontmatter`() throws {
    let workspace = try makeWorkspace(from: "batch-missing-without-create")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set",
      workspace.appending(path: "note.md").path,
      workspace.appending(path: "Source.swift").path,
      "--key", "reviewed",
      "--value", "approved",
      "--include-non-md",
    ])

    #expect(result.status != 0)
    #expect(result.standardError.contains("[y/N]") == false)
    #expect(result.standardError.lowercased().contains("requires --create-frontmatter"))
    try expectWorkspace(workspace, matches: "batch-missing-without-create")
  }

  @Test
  func `create-frontmatter authorizes noninteractive creation in a batch`() throws {
    let workspace = try makeWorkspace(from: "batch-missing-with-create")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set",
      workspace.appending(path: "note.md").path,
      workspace.appending(path: "Source.swift").path,
      "--key", "reviewed",
      "--value", "approved",
      "--include-non-md",
      "--create-frontmatter",
    ])

    #expect(result.status == 0)
    #expect(result.standardError.contains("[y/N]") == false)
    try expectWorkspace(workspace, matches: "batch-missing-with-create")
  }

  private func makeWorkspace(from fixture: String) throws -> URL {
    let input = try fixtureDirectory(fixture).appending(path: "input/", directoryHint: .isDirectory)
    let temporaryRoot = URL(
      filePath: FileManager.default.currentDirectoryPath,
      directoryHint: .isDirectory
    ).appending(path: "tmp/", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: temporaryRoot,
      withIntermediateDirectories: true
    )
    let workspace = temporaryRoot.appending(
      path: "md-utils-non-md-frontmatter-\(UUID().uuidString)/",
      directoryHint: .isDirectory
    )
    try FileManager.default.copyItem(at: input, to: workspace)
    return workspace
  }

  private func removeWorkspace(_ workspace: URL) {
    try? FileManager.default.removeItem(at: workspace)
  }

  private func expectWorkspace(_ workspace: URL, matches fixture: String) throws {
    let expected = try fixtureDirectory(fixture)
      .appending(path: "expected/", directoryHint: .isDirectory)
    let expectedFiles = try relativeFilePaths(in: expected)
    let actualFiles = try relativeFilePaths(in: workspace)
    #expect(actualFiles == expectedFiles)

    for fileName in expectedFiles {
      let expectedData = try Data(contentsOf: expected.appending(path: fileName))
      let actualData = try Data(contentsOf: workspace.appending(path: fileName))
      #expect(actualData == expectedData)
    }
  }

  private func relativeFilePaths(in directory: URL) throws -> [String] {
    let root = Path(directory.path).normalize()
    let rootComponentCount = root.components.count
    return try root.recursiveChildren()
      .filter(\.isFile)
      .map { child in
        child.components
          .dropFirst(rootComponentCount)
          .joined(separator: "/")
      }
    .sorted()
  }

  private func fixtureDirectory(_ fixture: String) throws -> URL {
    let root = try #require(
      Bundle.module.url(forResource: "NonMDFrontmatter", withExtension: nil)
    )
    return root.appending(path: "\(fixture)/", directoryHint: .isDirectory)
  }
}
