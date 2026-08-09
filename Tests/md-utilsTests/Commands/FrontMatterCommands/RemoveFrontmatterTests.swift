import Foundation
import Testing

@Suite("fm remove-frontmatter command")
struct RemoveFrontmatterTests {
  @Test
  func `yes flag removes complete Markdown frontmatter and preserves body`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "post.md")
    try write("""
      ---
      title: Example
      tags:
        - swift
      ---
      # Heading

      Body text.
      """, to: file)

    let result = try CLIProcessTestHelper.run([
      "fm", "remove-frontmatter", file.path, "--yes",
    ])

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("Removed frontmatter"))
    #expect(try read(file) == "# Heading\n\nBody text.")
  }

  @Test
  func `rmfm alias accepts short yes flag and removes empty frontmatter`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "empty.md")
    try write("---\n---\nBody\n", to: file)

    let result = try CLIProcessTestHelper.run(["fm", "rmfm", file.path, "-y"])

    #expect(result.status == 0)
    #expect(try read(file) == "Body\n")
  }

  @Test
  func `interactive removal requires y and displays are you sure prompt`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "confirmed.md")
    try write("---\ntitle: Confirmed\n---\nBody", to: file)

    let result = try CLIProcessTestHelper.run([
      "fm", "remove-frontmatter", file.path,
    ], standardInput: "y\n")

    #expect(result.status == 0)
    #expect(result.standardOutput.lowercased().contains("are you sure"))
    #expect(try read(file) == "Body")
  }

  @Test(arguments: ["yes\n", "Y\n", "n\n"])
  func `responses other than lowercase y cancel without changing the file`(
    _ response: String
  ) throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "cancelled.md")
    let original = "---\ntitle: Keep Me\n---\nBody"
    try write(original, to: file)

    let result = try CLIProcessTestHelper.run([
      "fm", "remove-frontmatter", file.path,
    ], standardInput: response)

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("Cancelled."))
    #expect(try read(file) == original)
  }

  @Test
  func `files without frontmatter remain unchanged without prompting`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "plain.md")
    let original = "# No Frontmatter\n\nBody\n"
    try write(original, to: file)

    let result = try CLIProcessTestHelper.run([
      "fm", "remove-frontmatter", file.path,
    ])

    #expect(result.status == 0)
    #expect(result.standardOutput.lowercased().contains("are you sure") == false)
    #expect(try read(file) == original)
  }

  @Test
  func `include-non-md removes wrapped and plain text frontmatter in a directory`() throws {
    let workspace = try makeWorkspace()
    defer { removeWorkspace(workspace) }
    let swiftFile = workspace.appending(path: "Example.swift")
    let textFile = workspace.appending(path: "notes.txt")
    try write("""
      /*
      ---
      title: Swift Example
      ---
      */
      import Foundation
      """, to: swiftFile)
    try write("---\ntitle: Notes\n---\nPlain text\n", to: textFile)

    let result = try CLIProcessTestHelper.run([
      "fm", "rmfm", workspace.path, "--include-non-md", "--yes",
    ])

    #expect(result.status == 0)
    #expect(try read(swiftFile) == "import Foundation")
    #expect(try read(textFile) == "Plain text\n")
  }

  @Test
  func `help documents alias confirmation and non-MD flag`() throws {
    let groupHelp = try CLIProcessTestHelper.run(["fm", "--help"])
    let commandHelp = try CLIProcessTestHelper.run(["fm", "rmfm", "--help"])

    #expect(groupHelp.status == 0)
    #expect(groupHelp.standardOutput.contains("remove-frontmatter"))
    #expect(commandHelp.status == 0)
    #expect(commandHelp.standardOutput.contains("--include-non-md"))
    #expect(commandHelp.standardOutput.contains("--yes"))
    #expect(commandHelp.standardOutput.contains("exactly y"))
  }

  private func makeWorkspace() throws -> URL {
    let temporaryRoot = URL(
      filePath: FileManager.default.currentDirectoryPath,
      directoryHint: .isDirectory
    ).appending(path: "tmp/", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: temporaryRoot,
      withIntermediateDirectories: true
    )
    let workspace = temporaryRoot.appending(
      path: "md-utils-remove-frontmatter-\(UUID().uuidString)/",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
      at: workspace,
      withIntermediateDirectories: true
    )
    return workspace
  }

  private func removeWorkspace(_ workspace: URL) {
    try? FileManager.default.removeItem(at: workspace)
  }

  private func write(_ content: String, to file: URL) throws {
    try Data(content.utf8).write(to: file)
  }

  private func read(_ file: URL) throws -> String {
    String(decoding: try Data(contentsOf: file), as: UTF8.self)
  }
}
