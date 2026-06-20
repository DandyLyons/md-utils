//
//  OKFCommandsTests.swift
//  md-utilsTests
//

import ArgumentParser
import Foundation
import JSONSchema
import PathKit
import Testing

@testable import md_utils

@Suite("OKF commands", .serialized)
struct OKFCommandsTests {
  @Test
  func `okf command group has correct configuration`() {
    let config = CLIEntry.OKFCommands.configuration

    #expect(config.commandName == "okf")
    #expect(config.subcommands.count == 2)
    #expect(config.subcommands[0] is CLIEntry.OKFCommands.Validate.Type)
    #expect(config.subcommands[1] is CLIEntry.OKFCommands.TypeCommands.Type)
  }

  @Test
  func `okf validate parses bundle path`() throws {
    let parsed = try CLIEntry.parseAsRoot(["okf", "validate", "./knowledge/"])
    let command = try #require(parsed as? CLIEntry.OKFCommands.Validate)

    #expect(command.bundlePath == Path("./knowledge/"))
  }

  @Test
  func `okf type set parses without dir`() throws {
    let parsed = try CLIEntry.parseAsRoot(["okf", "type", "set", "--type=Book"])
    let command = try #require(parsed as? CLIEntry.OKFCommands.TypeCommands.SetType)

    #expect(command.type == "Book")
    #expect(command.dir == nil)
  }

  @Test
  func `conformant bundle passes validation`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "books/dune.md", content: concept(type: "Book"))
    try writeFile(project + "index.md", content: "# Index\n\n* [Dune](books/dune.md) - A book.\n")
    try writeFile(project + "log.md", content: "# Directory Update Log\n\n## 2026-06-20\n* **Update**: Added [Dune](books/dune.md).\n")

    let summary = try OKFValidator.validate(bundlePath: project)

    #expect(summary.filesScanned == 3)
    #expect(summary.conceptDocuments == 1)
    #expect(summary.reservedFiles == 2)
    #expect(!summary.hasErrors)
  }

  @Test
  func `missing frontmatter fails validation`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "books/dune.md", content: "# Dune\n")

    let summary = try OKFValidator.validate(bundlePath: project)

    #expect(summary.hasErrors)
    #expect(summary.issues.first?.path == "frontmatter")
  }

  @Test
  func `unclosed frontmatter fails validation`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "books/dune.md", content: "---\ntype: Book\n# Dune\n")

    let summary = try OKFValidator.validate(bundlePath: project)

    #expect(summary.hasErrors)
    #expect(summary.issues.first?.message.contains("not closed") == true)
  }

  @Test
  func `invalid yaml fails validation`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "books/dune.md", content: "---\ntype: [\n---\n# Dune\n")

    let summary = try OKFValidator.validate(bundlePath: project)

    #expect(summary.hasErrors)
    #expect(summary.issues.first?.message.contains("invalid YAML") == true)
  }

  @Test
  func `missing type fails validation`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "books/dune.md", content: "---\ntitle: Dune\n---\n# Dune\n")

    let summary = try OKFValidator.validate(bundlePath: project)

    #expect(summary.hasErrors)
    #expect(summary.issues.first?.path == "frontmatter.type")
  }

  @Test
  func `empty type fails validation`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "books/dune.md", content: "---\ntype: \"\"\n---\n# Dune\n")

    let summary = try OKFValidator.validate(bundlePath: project)

    #expect(summary.hasErrors)
    #expect(summary.issues.first?.message == "must not be empty")
  }

  @Test
  func `unknown type and extra keys pass validation`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "books/dune.md", content: "---\ntype: Strange Custom Thing\nextra: value\n---\n# Dune\n")

    let summary = try OKFValidator.validate(bundlePath: project)

    #expect(!summary.hasErrors)
  }

  @Test
  func `reserved files are not concept documents`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "index.md", content: "# Index\n")
    try writeFile(project + "log.md", content: "# Directory Update Log\n")

    let summary = try OKFValidator.validate(bundlePath: project)

    #expect(summary.conceptDocuments == 0)
    #expect(summary.reservedFiles == 2)
    #expect(!summary.hasErrors)
  }

  @Test
  func `invalid log date heading fails validation`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "log.md", content: "# Directory Update Log\n\n## June 20 2026\n* Update.\n")

    let summary = try OKFValidator.validate(bundlePath: project)

    #expect(summary.hasErrors)
    #expect(summary.issues.first?.filePath == "log.md")
  }

  @Test
  func `validation formatter uses trailing slash for directory`() throws {
    let summary = OKFValidationSummary(
      bundlePath: Path("./knowledge"),
      filesScanned: 0,
      conceptDocuments: 0,
      reservedFiles: 0,
      issues: []
    )

    let output = OKFValidationFormatter.render(summary)

    #expect(output.contains("./knowledge/"))
  }

  @Test
  func `type set updates concepts and skips reserved files`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "books/dune.md", content: "# Dune\n")
    try writeFile(project + "books/index.md", content: "# Books\n")

    let summary = try OKFTypeSetter.setType(options: OKFTypeSetOptions(
      directory: project + "books",
      type: "Book",
      arrayKey: nil,
      arrayContains: nil
    ))

    #expect(summary.updatedFiles == ["dune.md"])
    #expect(summary.skippedReservedFiles == ["index.md"])
    #expect(try (project + "books/dune.md").read().contains("type: Book"))
    #expect(try !(project + "books/index.md").read().contains("type: Book"))
  }

  @Test
  func `type set defaults to current directory`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "books/dune.md", content: "# Dune\n")

    try withCurrentDirectory(project) {
      let summary = try OKFTypeSetter.setType(options: OKFTypeSetOptions(
        directory: .current,
        type: "Book",
        arrayKey: nil,
        arrayContains: nil
      ))

      #expect(summary.updatedFiles == ["books/dune.md"])
    }
  }

  @Test
  func `type set filters by yaml array membership`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }
    try writeFile(project + "dune.md", content: concept(type: "Reference", tags: ["Books"]))
    try writeFile(project + "note.md", content: concept(type: "Reference", tags: ["Notes"]))

    let summary = try OKFTypeSetter.setType(options: OKFTypeSetOptions(
      directory: project,
      type: "Book",
      arrayKey: "tags",
      arrayContains: "Books"
    ))

    #expect(summary.updatedFiles == ["dune.md"])
    #expect(try (project + "dune.md").read().contains("type: Book"))
    #expect(try (project + "note.md").read().contains("type: Reference"))
  }

  @Test
  func `type set requires paired array filter options`() throws {
    let project = try createTempProject()
    defer { try? project.delete() }

    #expect(throws: ValidationError.self) {
      try OKFTypeSetter.setType(options: OKFTypeSetOptions(
        directory: project,
        type: "Book",
        arrayKey: "tags",
        arrayContains: nil
      ))
    }
  }

  @Test
  func `bundled okf concept schema requires type`() throws {
    let url = try #require(Bundle.module.url(forResource: "OKF-concept.schema", withExtension: "json"))
    let data = try Data(contentsOf: url)
    let schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    let valid = try JSONSchema.validate(["type": "Book"], schema: schema)
    let invalid = try JSONSchema.validate(["title": "Dune"], schema: schema)

    #expect(valid.valid)
    #expect(!invalid.valid)
  }

  private func createTempProject() throws -> Path {
    let path = Path(NSTemporaryDirectory()) + "md-utils-okf-tests-\(UUID().uuidString)"
    try path.mkpath()
    return path
  }

  private func writeFile(_ path: Path, content: String) throws {
    try path.parent().mkpath()
    try path.write(content)
  }

  private func withCurrentDirectory<T>(_ path: Path, operation: () throws -> T) throws -> T {
    let original = FileManager.default.currentDirectoryPath
    guard FileManager.default.changeCurrentDirectoryPath(path.string) else {
      throw ValidationError("Failed to change current directory to \(path.string)")
    }
    defer { _ = FileManager.default.changeCurrentDirectoryPath(original) }
    return try operation()
  }

  private func concept(type: String, tags: [String] = []) -> String {
    let tagBlock: String
    if tags.isEmpty {
      tagBlock = ""
    } else {
      tagBlock = "tags:\n" + tags.map { "  - \($0)" }.joined(separator: "\n") + "\n"
    }
    return """
      ---
      type: \(type)
      \(tagBlock)---
      # Concept
      """
  }
}
