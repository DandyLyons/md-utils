import Foundation
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import md_utils

struct ArrayEmptyTests {
  @Test(arguments: ["yaml", "toml"], ["init", "clear"])
  func writesTypedEmptyArray(format: String, operation: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "post.md")
    let source = format == "yaml"
      ? "---\ntitle: Example\n\(operation == "clear" ? "tags: [swift, 42, true]\n" : "")---\nBody\n"
      : "+++\ntitle = \"Example\"\n\(operation == "clear" ? "tags = [\"swift\"]\n" : "")+++\nBody\n"
    try Data(source.utf8).write(to: file)

    let result = try run(operation, paths: [file.path])
    #expect(result.status == 0)
    #expect(result.standardOutput.isEmpty)
    let content = try String(contentsOf: file, encoding: .utf8)
    let document = try MarkdownDocument(content: content)
    #expect(document.getValue(forKey: "tags") == .array([]))
    #expect(document.getValue(forKey: "title") == .string("Example"))
    #expect(content.hasPrefix(format == "yaml" ? "---\n" : "+++\n"))
    #expect(content.hasSuffix("Body\n"))
  }

  @Test(arguments: [
    ("init", "empty"),
    ("init", "nonempty"),
    ("clear", "missing"),
    ("clear", "empty"),
  ])
  func preservesNoOpBytesAndModificationTime(operation: String, state: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "post.md")
    let entry = state == "missing" ? "" : "tags: \(state == "empty" ? "[]" : "[swift]") # retain this comment\n"
    let source = "---\n# retain formatting\n\(entry)title: 'Example'\n---\nBody\n"
    try Data(source.utf8).write(to: file)
    let date = Date(timeIntervalSince1970: 1_000_000)
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)

    let result = try run(operation, paths: [file.path], extra: ["--frontmatter-format", "toml"])
    #expect(result.status == 0)
    #expect(result.standardOutput.isEmpty)
    #expect(try Data(contentsOf: file) == Data(source.utf8))
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    #expect(attributes[.modificationDate] as? Date == date)
    if state == "nonempty" {
      #expect(result.standardError.contains("nonempty array already exists at key \"tags\"; unchanged"))
      #expect(result.standardError.contains(file.path))
    } else if state == "missing" {
      #expect(result.standardError.contains("nothing to clear"))
    }
  }

  @Test(arguments: ["init", "clear"], ["swift", "42", "true", "{nested: value}"])
  func rejectsNonArraysWithoutWriting(operation: String, value: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "post.md")
    let source = "---\ntags: \(value)\n---\nBody\n"
    try Data(source.utf8).write(to: file)

    let result = try run(operation, paths: [file.path])
    #expect(result.status == 1)
    #expect(result.standardError.contains("is not an array"))
    #expect(try Data(contentsOf: file) == Data(source.utf8))
  }

  @Test(arguments: ["init", "clear"])
  func handlesAbsentFrontmatter(operation: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "post.md")
    let source = "# Body\n"
    try Data(source.utf8).write(to: file)

    let result = try run(operation, paths: [file.path])
    #expect(result.status == 0)
    let content = try String(contentsOf: file, encoding: .utf8)
    if operation == "init" {
      #expect(try MarkdownDocument(content: content).getValue(forKey: "tags") == .array([]))
      #expect(content.hasSuffix(source))
    } else {
      #expect(content == source)
    }
  }

  @Test(arguments: ["init", "clear"])
  func convertsFormatOnlyOnMutation(operation: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "post.md")
    let source = "---\n\(operation == "clear" ? "tags: [swift]\n" : "")title: Example\n---\nBody\n"
    try Data(source.utf8).write(to: file)
    let result = try run(operation, paths: [file.path], extra: ["--frontmatter-format", "toml"])
    #expect(result.status == 0)
    let content = try String(contentsOf: file, encoding: .utf8)
    #expect(content.hasPrefix("+++\n"))
    #expect(try MarkdownDocument(content: content).getValue(forKey: "tags") == .array([]))
  }

  @Test(arguments: ["init", "clear"])
  func continuesBulkProcessingAfterTypeError(operation: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let bad = workspace.appending(path: "a-bad.md")
    let good = workspace.appending(path: "b-good.md")
    let badSource = "---\ntags: invalid\n---\nBody\n"
    try Data(badSource.utf8).write(to: bad)
    try Data("---\n\(operation == "clear" ? "tags: [swift]\n" : "")---\nBody\n".utf8).write(to: good)

    let result = try run(operation, paths: [workspace.path + "/"])
    #expect(result.status == 1)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("1 file(s); 0 unchanged; 1 failed"))
    #expect(try Data(contentsOf: bad) == Data(badSource.utf8))
    let content = try String(contentsOf: good, encoding: .utf8)
    #expect(try MarkdownDocument(content: content).getValue(forKey: "tags") == .array([]))
  }

  @Test
  func usesLiteralTopLevelKeys() throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "post.md")
    try Data("---\nproject: {tags: [swift]}\n---\nBody\n".utf8).write(to: file)
    let result = try CLIProcessTestHelper.run(["fm", "array", "init", "--key", "project.tags", file.path])
    #expect(result.status == 0)
    let document = try MarkdownDocument(content: String(contentsOf: file, encoding: .utf8))
    #expect(document.getValue(forKey: "project.tags") == .array([]))
    let expectedProject = FrontMatter(["tags": .array([.string("swift")])])
    #expect(document.getValue(forKey: "project") == .object(expectedProject))
  }

  @Test
  func nonMarkdownCreationRequiresAuthorizationAndClearDoesNotCreate() throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "example.swift")
    let source = "let answer = 42\n"
    try Data(source.utf8).write(to: file)
    let denied = try run("init", paths: [workspace.path + "/"], extra: ["--include-non-md"])
    #expect(denied.status == 1)
    #expect(denied.standardError.contains("requires --create-frontmatter"))
    #expect(try Data(contentsOf: file) == Data(source.utf8))
    let clear = try run("clear", paths: [file.path])
    #expect(clear.status == 0)
    #expect(try Data(contentsOf: file) == Data(source.utf8))
    let created = try run("init", paths: [file.path], extra: ["--create-frontmatter"])
    #expect(created.status == 0)
    let content = try String(contentsOf: file, encoding: .utf8)
    #expect(content.contains("tags: []"))
    #expect(content.hasSuffix(source))
    let cleared = try run("clear", paths: [file.path])
    #expect(cleared.status == 0)
    #expect(try String(contentsOf: file, encoding: .utf8) == content)
  }

  @Test(arguments: ["init", "clear"], ["wrapped", "line-comment"])
  func mutatesNonMarkdownFrontmatter(operation: String, syntax: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: syntax == "wrapped" ? "example.swift" : "example.conf")
    let entry = operation == "clear" ? "tags: [swift]\n" : ""
    let source = syntax == "wrapped"
      ? "/*\n---\ntitle: Example\n\(entry)---\n*/\nlet answer = 42\n"
      : "# ---\n# title: Example\n\(operation == "clear" ? "# tags: [swift]\n" : "")# ---\nanswer = 42\n"
    try Data(source.utf8).write(to: file)
    let extra = syntax == "wrapped" ? [] : ["--line-comment-frontmatter"]
    let result = try run(operation, paths: [file.path], extra: extra)
    #expect(result.status == 0)
    let parsed = try FrontMatterCLIMutator.parsedFile(
      at: Path(file.path),
      includeNonMarkdown: false,
      lineCommentFrontmatter: syntax == "line-comment",
    )
    #expect(parsed.document.getValue(forKey: "tags") == .array([]))
    let content = try String(contentsOf: file, encoding: .utf8)
    #expect(content.contains("title: Example"))
    #expect(content.hasSuffix(syntax == "wrapped" ? "let answer = 42\n" : "answer = 42\n"))
  }

  @Test(arguments: ["init", "clear"])
  func requiresKeyAndRejectsEmptySelection(operation: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let missingKey = try CLIProcessTestHelper.run(["fm", "array", operation, workspace.path + "/"])
    #expect(missingKey.status != 0)
    #expect(missingKey.standardError.contains("--key"))
    let empty = try run(operation, paths: [workspace.path + "/"])
    #expect(empty.status == 64)
    #expect(empty.standardError.contains("No Markdown files found"))
  }

  @Test(arguments: ["null", "~", ""], ["yaml", "toml"])
  func initializesNullAsTypedEmptyArray(value: String, format: String) throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "post.md")
    try Data("---\ntags: \(value)\ntitle: Example\n---\nBody\n".utf8).write(to: file)
    let result = try run("init", paths: [file.path], extra: ["--frontmatter-format", format])
    #expect(result.status == 0)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("1 file(s); 0 unchanged; 0 failed"))
    let content = try String(contentsOf: file, encoding: .utf8)
    let document = try MarkdownDocument(content: content)
    #expect(document.getValue(forKey: "tags") == .array([]))
    #expect(document.getValue(forKey: "title") == .string("Example"))
    #expect(content.hasPrefix(format == "yaml" ? "---\n" : "+++\n"))
    #expect(content.hasSuffix("Body\n"))
  }

  @Test
  func clearStillRejectsNull() throws {
    let workspace = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspace) }
    let file = workspace.appending(path: "post.md")
    let source = "---\ntags: null\n---\nBody\n"
    try Data(source.utf8).write(to: file)
    let result = try run("clear", paths: [file.path])
    #expect(result.status == 1)
    #expect(result.standardError.contains("is not an array"))
    #expect(try Data(contentsOf: file) == Data(source.utf8))
  }

  private func run(_ operation: String, paths: [String], extra: [String] = []) throws -> CLIProcessResult {
    try CLIProcessTestHelper.run(["fm", "array", operation, "--key", "tags"] + extra + paths)
  }

  private func makeWorkspace() throws -> URL {
    let root = URL(filePath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let workspace = root.appending(path: "tmp/array-empty-\(UUID().uuidString)/", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    return workspace
  }
}
