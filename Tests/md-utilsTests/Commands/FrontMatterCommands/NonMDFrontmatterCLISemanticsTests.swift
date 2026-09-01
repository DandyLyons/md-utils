import Foundation
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import md_utils

@Suite("non-MD frontmatter CLI semantics")
struct NonMDFrontmatterCLISemanticsTests {
  @Test(arguments: [
    nil,
    "dump", "get", "has", "list", "remove", "rename", "replace", "search", "set",
    "remove-frontmatter", "sort-keys", "touch", "unique", "array", "array append", "array contains",
    "array prepend", "array remove",
  ] as [String?])
  func `relevant help pages explain valid wrapped frontmatter`(_ commandPath: String?) throws {
    var arguments = ["fm"]
    if let commandPath {
      arguments.append(contentsOf: commandPath.split(separator: " ").map(String.init))
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

  @Test(arguments: [
    "dump", "get", "has", "list", "remove", "rename", "replace", "search", "set",
    "remove-frontmatter", "sort-keys", "touch", "unique", "array append", "array contains",
    "array prepend", "array remove",
  ])
  func `every fm leaf exposes the explicit line-comment override`(_ commandPath: String) throws {
    let result = try CLIProcessTestHelper.run(
      ["fm"] + commandPath.split(separator: " ").map(String.init) + ["--help"]
    )

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("--line-comment-frontmatter"))
  }

  @Test
  func `remaining fm subcommands mutate existing wrapped frontmatter`() throws {
    let workspace = try makeWorkspace(from: "command-parity-existing")
    defer { removeWorkspace(workspace) }

    let commands = [
      ["fm", "remove", workspace.appending(path: "remove.swift").path, "--key", "obsolete"],
      ["fm", "rename", workspace.appending(path: "rename.swift").path, "--key", "legacy", "--new-key", "current"],
      ["fm", "replace", workspace.appending(path: "replace.swift").path, "--data", "{\"replacement\":\"yes\"}", "--yes"],
      ["fm", "sort-keys", workspace.appending(path: "sort.swift").path],
      ["fm", "touch", workspace.appending(path: "touch.swift").path, "--keys", "reviewed"],
      ["fm", "array", "append", workspace.appending(path: "append.swift").path, "--key", "tags", "--value", "omega"],
      ["fm", "array", "prepend", workspace.appending(path: "prepend.swift").path, "--key", "tags", "--value", "first"],
      ["fm", "array", "remove", workspace.appending(path: "array-remove.swift").path, "--key", "tags", "--value", "remove-me"],
    ]

    for command in commands {
      let result = try CLIProcessTestHelper.run(command)
      #expect(result.status == 0, "Command failed: \(command.joined(separator: " "))\n\(result.standardError)")
    }

    let contains = try CLIProcessTestHelper.run([
      "fm", "array", "contains", workspace.appending(path: "contains.swift").path,
      "--key", "tags", "--value", "swift",
    ])
    #expect(contains.status == 0)
    #expect(contains.standardOutput.contains("contains.swift"))
    try expectWorkspace(workspace, matches: "command-parity-existing")
  }

  @Test
  func `creating parity commands honor create-frontmatter`() throws {
    let workspace = try makeWorkspace(from: "command-parity-create")
    defer { removeWorkspace(workspace) }

    let commands = [
      ["fm", "touch", workspace.appending(path: "touch.swift").path, "--keys", "reviewed", "--create-frontmatter"],
      ["fm", "array", "append", workspace.appending(path: "append.swift").path, "--key", "tags", "--value", "last", "--create-frontmatter"],
      ["fm", "array", "prepend", workspace.appending(path: "prepend.swift").path, "--key", "tags", "--value", "first", "--create-frontmatter"],
      ["fm", "replace", workspace.appending(path: "replace.swift").path, "--data", "{\"created\":true}", "--yes", "--create-frontmatter"],
    ]

    for command in commands {
      let result = try CLIProcessTestHelper.run(command)
      #expect(result.status == 0, "Command failed: \(command.joined(separator: " "))\n\(result.standardError)")
    }

    try expectWorkspace(workspace, matches: "command-parity-create")
  }

  @Test
  func `creating parity commands refuse batch creation without create-frontmatter`() throws {
    let commandTails = [
      ["touch", "--keys", "reviewed"],
      ["array", "append", "--key", "tags", "--value", "last"],
      ["array", "prepend", "--key", "tags", "--value", "first"],
      ["replace", "--data", "{\"created\":true}", "--yes"],
    ]

    for commandTail in commandTails {
      let workspace = try makeWorkspace(from: "command-parity-batch-refused")
      defer { removeWorkspace(workspace) }
      let result = try CLIProcessTestHelper.run(
        ["fm"] + commandTail + [
          workspace.appending(path: "First.swift").path,
          workspace.appending(path: "Second.swift").path,
          "--include-non-md",
        ]
      )

      #expect(result.status != 0)
      #expect(result.standardError.contains("[y/N]") == false)
      #expect(result.standardError.lowercased().contains("requires --create-frontmatter"))
      try expectWorkspace(workspace, matches: "command-parity-batch-refused")
    }
  }

  @Test
  func `noncreating parity commands leave absent wrapped frontmatter unchanged`() throws {
    let workspace = try makeWorkspace(from: "command-parity-noncreating-absent")
    defer { removeWorkspace(workspace) }
    let cases: [([String], Int32)] = [
      (["remove", workspace.appending(path: "remove.swift").path, "--key", "missing"], 0),
      (["sort-keys", workspace.appending(path: "sort.swift").path], 0),
      (["rename", workspace.appending(path: "rename.swift").path, "--key", "missing", "--new-key", "current"], 1),
      (["array", "remove", workspace.appending(path: "array-remove.swift").path, "--key", "tags", "--value", "missing"], 1),
      (["array", "contains", workspace.appending(path: "contains.swift").path, "--key", "tags", "--value", "missing"], 1),
    ]

    for (command, expectedStatus) in cases {
      let result = try CLIProcessTestHelper.run(["fm"] + command)
      #expect(result.status == expectedStatus)
      #expect(result.standardError.contains("[y/N]") == false)
    }

    try expectWorkspace(workspace, matches: "command-parity-noncreating-absent")
  }

  @Test
  func `malformed YAML in the first wrapped block remains a YAML conversion error`() {
    let source = "/*\n---\ninvalid: yaml: syntax:\n---\n*/\n"

    #expect(throws: YAMLConversionError.self) {
      _ = try ParsedFrontMatterFile.parse(source: source, syntax: .wrapped(.cBlock))
    }
  }

  @Test
  func `line-comment rendering canonicalizes empty logical lines to bare hash`() throws {
    let source = "# ---\n# value: old\n# ---\nHOST_BYTES=true\n"
    let parsed = try ParsedFrontMatterFile.parse(source: source, syntax: .lineComment)
    var document = parsed.document
    document.frontMatter["value"] = .string("first\n\nthird")

    let rendered = try parsed.rendering(document)

    #expect(rendered.contains("\n#\n"))
    #expect(rendered.hasSuffix("HOST_BYTES=true\n"))
  }

  @Test
  func `explicit override never replaces Markdown or wrapped mappings`() {
    #expect(
      FrontMatterFileSyntax.resolve(
        for: Path("note.md"),
        includeNonMarkdown: false,
        lineCommentFrontmatter: true
      ) == .markdown
    )
    #expect(
      FrontMatterFileSyntax.resolve(
        for: Path("script.py"),
        includeNonMarkdown: false,
        lineCommentFrontmatter: true
      ) == .wrapped(.pythonDocstring)
    )
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
  func `an explicit TOML file uses the shipped line-comment mapping`() throws {
    let workspace = try makeWorkspace(from: "single-unsupported-toml")
    defer { removeWorkspace(workspace) }

    let result = try CLIProcessTestHelper.run([
      "fm", "set", workspace.appending(path: "settings.toml").path,
      "--key", "status",
      "--value", "approved",
    ])

    #expect(result.status != 0)
    #expect(result.standardError.contains("Create line-comment frontmatter using # prefixes? [y/N]"))
    #expect(result.standardError.lowercased().contains("no frontmatter syntax mapping") == false)
    try expectWorkspace(workspace, matches: "single-unsupported-toml")
  }

  @Test
  func `line-comment override reads and mutates an otherwise unmapped explicit file`() throws {
    let workspace = try makeScratchWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "settings.conf")
    try Data("# ---\n# title: Before\n# ---\nHOST_BYTES=true\n".utf8).write(to: file)

    let set = try CLIProcessTestHelper.run([
      "fm", "set", file.path, "--key", "title", "--value", "After",
      "--line-comment-frontmatter",
    ])
    #expect(set.status == 0, "\(set.standardError)")

    let get = try CLIProcessTestHelper.run([
      "fm", "get", file.path, "--key", "title", "--line-comment-frontmatter",
    ])
    #expect(get.status == 0, "\(get.standardError)")
    #expect(get.standardOutput.contains("After"))
    let updated = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    #expect(updated.contains("# title: After"))
    #expect(updated.hasSuffix("HOST_BYTES=true\n"))

    let search = try CLIProcessTestHelper.run([
      "fm", "search", "title == `\"After\"`", file.path,
      "--line-comment-frontmatter",
    ])
    #expect(search.status == 0, "\(search.standardError)")
    #expect(search.standardOutput.contains(file.lastPathComponent))
  }

  @Test
  func `line-comment creation preserves BOM and uses canonical placement`() throws {
    let workspace = try makeScratchWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: ".env.schema")
    let original = "\u{FEFF}# @defaultSensitive=false\n# ---\nPUBLIC_URL=https://example.invalid\n"
    try Data(original.utf8).write(to: file)

    let result = try CLIProcessTestHelper.run([
      "fm", "set", file.path, "--key", "owner", "--value", "platform",
      "--create-frontmatter",
    ])

    #expect(result.status == 0, "\(result.standardError)")
    let updated = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    #expect(updated.hasPrefix("\u{FEFF}# ---\n# owner: platform\n# ---\n\n"))
    #expect(updated.hasSuffix(String(original.dropFirst())))
  }

  @Test
  func `line-comment creation reuses one empty post-shebang line`() throws {
    let workspace = try makeScratchWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "script.sh")
    try Data("#!/bin/sh\n\necho unchanged\n".utf8).write(to: file)

    let result = try CLIProcessTestHelper.run([
      "fm", "set", file.path, "--key", "owner", "--value", "platform",
      "--create-frontmatter",
    ])

    #expect(result.status == 0, "\(result.standardError)")
    let updated = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    #expect(
      updated
        == "#!/bin/sh\n# ---\n# owner: platform\n# ---\n\necho unchanged\n"
    )
  }

  @Test
  func `structural failure leaves a line-comment file byte-for-byte unchanged`() throws {
    let workspace = try makeScratchWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "script.sh")
    let original = "# ---\n# owner: platform\n#invalid\n# ---\necho unchanged\n"
    try Data(original.utf8).write(to: file)

    let result = try CLIProcessTestHelper.run([
      "fm", "set", file.path, "--key", "owner", "--value", "changed",
    ])

    #expect(result.status != 0)
    #expect(result.standardError.contains("must be empty, bare #, or begin with exactly # "))
    #expect(try Data(contentsOf: file) == Data(original.utf8))
  }

  @Test
  func `dump automatically discovers shipped line-comment mappings`() throws {
    let workspace = try makeScratchWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "Makefile")
    try Data("# ---\n# owner: platform\n# ---\nall:\n\t@true\n".utf8).write(to: file)

    let result = try CLIProcessTestHelper.run(["fm", "dump", workspace.path])

    #expect(result.status == 0, "\(result.standardError)")
    #expect(result.standardOutput.contains("platform"))
    #expect(result.standardOutput.contains("Makefile"))
  }

  @Test
  func `TOML mutation and complete-block removal preserve host bytes`() throws {
    let workspace = try makeScratchWorkspace()
    defer { removeWorkspace(workspace) }
    let file = workspace.appending(path: "settings.toml")
    let host = "enabled = resolver(keep-this)\n"
    try Data(("# +++\n# owner = \"before\"\n# +++\n" + host).utf8).write(to: file)

    let set = try CLIProcessTestHelper.run([
      "fm", "set", file.path, "--key", "owner", "--value", "after",
    ])
    #expect(set.status == 0, "\(set.standardError)")
    let mutated = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    #expect(mutated.hasPrefix("# +++\n# owner = \"after\"\n# +++\n"))
    #expect(mutated.hasSuffix(host))

    let removed = try CLIProcessTestHelper.run([
      "fm", "remove-frontmatter", file.path, "--yes",
    ])
    #expect(removed.status == 0, "\(removed.standardError)")
    #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == host)
  }

  @Test(arguments: [
    ["fm", "dump", "--line-comment-frontmatter"],
    ["fm", "set", ".", "--key", "title", "--value", "No", "--line-comment-frontmatter"],
  ])
  func `line-comment override rejects implicit and directory input`(_ arguments: [String]) throws {
    let result = try CLIProcessTestHelper.run(arguments)

    #expect(result.status != 0)
    #expect(result.standardError.contains("requires explicitly supplied regular files"))
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

  private func makeScratchWorkspace() throws -> URL {
    let temporaryRoot = URL(
      filePath: FileManager.default.currentDirectoryPath,
      directoryHint: .isDirectory
    ).appending(path: "tmp/", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    let workspace = temporaryRoot.appending(
      path: "md-utils-line-comment-\(UUID().uuidString)/",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
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
      #expect(actualData == expectedData, "Fixture mismatch: \(fixture)/\(fileName)")
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
