//
//  UniqueTests.swift
//  md-utilsTests
//

import ArgumentParser
import Foundation
import JMESPath
import PathKit
import Rainbow
import Testing
import Yams

@testable import md_utils

@Suite("fm unique command")
struct UniqueTests {
  @Test
  func `command is registered and parses its public options`() throws {
    let parsed = try CLIEntry.parseAsRoot([
      "fm", "unique", "metadata.id", "notes/", "--reference", "foo.md",
      "--require-value", "--format", "yaml", "--no-recursive",
    ])
    let command = try #require(parsed as? CLIEntry.FrontMatterCommands.Unique)

    #expect(command.expression == "metadata.id")
    #expect(command.options.paths == [Path("notes/")])
    #expect(command.reference == Path("foo.md"))
    #expect(command.requireValue)
    #expect(command.format == .yaml)
    #expect(command.options.recursive == false)
  }

  @Test
  func `help documents quoting and scalar-only behavior`() {
    let help = CLIEntry.FrontMatterCommands.Unique.helpMessage()

    #expect(help.contains("single-quote the entire expression"))
    #expect(help.contains("Simple selectors such as id and metadata.id are safe unquoted"))
    #expect(help.contains("backticks as command substitution"))
    #expect(help.contains("authors[].id are unsupported"))
  }

  @Test
  func `collection analysis reports every collision deterministically`() throws {
    let directory = try makeDirectory()
    defer { try? directory.delete() }
    let alpha = try writeNote(directory, name: "alpha.md", frontmatter: "id: shared")
    let beta = try writeNote(directory, name: "beta.md", frontmatter: "id: shared")
    _ = try writeNote(directory, name: "gamma.md", frontmatter: "id: distinct")

    let report = try analyze("id", files: directory.children().sorted { $0.string < $1.string })

    #expect(report.mode == .collection)
    #expect(report.checkedFiles == 3)
    #expect(report.filesWithValue == 3)
    #expect(report.collisions.count == 1)
    #expect(report.collisions.first?.value == .string("shared"))
    #expect(report.collisions.first?.paths == [alpha.string, beta.string])
    #expect(report.hasFailure(requireValue: false))
  }

  @Test
  func `nested selector succeeds when all values are unique`() throws {
    let directory = try makeDirectory()
    defer { try? directory.delete() }
    _ = try writeNote(directory, name: "one.md", frontmatter: "metadata:\n  id: one")
    _ = try writeNote(directory, name: "two.md", frontmatter: "metadata:\n  id: two")

    let report = try analyze("metadata.id", files: directory.children())

    #expect(report.collisions.isEmpty)
    #expect(report.filesWithValue == 2)
    #expect(report.hasFailure(requireValue: false) == false)
  }

  @Test
  func `reference mode ignores unrelated collisions`() throws {
    let directory = try makeDirectory()
    defer { try? directory.delete() }
    let reference = try writeNote(directory, name: "reference.md", frontmatter: "id: reference")
    let match = try writeNote(directory, name: "match.md", frontmatter: "id: reference")
    _ = try writeNote(directory, name: "other-a.md", frontmatter: "id: unrelated")
    _ = try writeNote(directory, name: "other-b.md", frontmatter: "id: unrelated")

    let comparison = try directory.children().filter { $0 != reference }
    let report = try analyze("id", files: comparison, reference: reference)

    #expect(report.mode == .reference)
    #expect(report.collisions.count == 1)
    #expect(report.collisions.first?.paths == [match.string, reference.string].sorted())
  }

  @Test
  func `reference mode succeeds without a matching comparison value`() throws {
    let directory = try makeDirectory()
    defer { try? directory.delete() }
    let reference = try writeNote(directory, name: "reference.md", frontmatter: "id: reference")
    let comparison = try writeNote(directory, name: "other.md", frontmatter: "id: unrelated")

    let report = try analyze("id", files: [comparison], reference: reference)

    #expect(report.collisions.isEmpty)
    #expect(report.hasFailure(requireValue: false) == false)
  }

  @Test
  func `missing and null values are optional unless required`() throws {
    let directory = try makeDirectory()
    defer { try? directory.delete() }
    _ = try writeNote(directory, name: "missing.md", frontmatter: "title: Missing")
    _ = try writeNote(directory, name: "null.md", frontmatter: "id: null")

    let report = try analyze("id", files: directory.children())

    #expect(report.missingPaths.count == 2)
    #expect(report.filesWithValue == 0)
    #expect(report.hasFailure(requireValue: false) == false)
    #expect(report.hasFailure(requireValue: true))
  }

  @Test
  func `arrays objects and malformed YAML become diagnostics`() throws {
    let directory = try makeDirectory()
    defer { try? directory.delete() }
    _ = try writeNote(directory, name: "array.md", frontmatter: "id: [one, two]")
    _ = try writeNote(directory, name: "object.md", frontmatter: "id:\n  nested: value")
    let malformed = directory + "malformed.md"
    try malformed.write("---\nid: [unterminated\n---\n")

    let report = try analyze("id", files: directory.children())

    #expect(report.diagnostics.count == 3)
    #expect(report.diagnostics.contains { $0.message.contains("unsupported array") })
    #expect(report.diagnostics.contains { $0.message.contains("unsupported object") })
    #expect(report.hasFailure(requireValue: false))
  }

  @Test
  func `typed scalars preserve exact strings and numeric equality`() throws {
    #expect(try UniqueScalar.scalar(from: "1") == .string("1"))
    #expect(try UniqueScalar.scalar(from: true) == .boolean(true))
    #expect(try UniqueScalar.scalar(from: NSNumber(value: 1)) == UniqueScalar.scalar(from: NSNumber(value: 1.0)))
    #expect(
      try UniqueScalar.scalar(from: NSNumber(value: Int64.max))
        != UniqueScalar.scalar(from: NSNumber(value: Int64.max - 1))
    )
    #expect(throws: UniqueEvaluationError.self) {
      try UniqueScalar.scalar(from: NSNumber(value: Double.infinity))
    }
  }

  @Test
  func `canonical path resolution deduplicates overlaps and symlinks`() throws {
    let directory = try makeDirectory()
    defer { try? directory.delete() }
    let file = try writeNote(directory, name: "note.md", frontmatter: "id: one")
    let link = directory + "alias.md"
    try FileManager.default.createSymbolicLink(atPath: link.string, withDestinationPath: file.string)

    let resolved = UniquePathResolver.canonicalized([file, Path(file.string), link], sort: true)

    #expect(resolved.count == 1)
    #expect(resolved.first?.string == file.absolute().normalize().string)
  }

  @Test
  func `text renderer is styled while structured output is parseable and unstyled`() throws {
    let report = UniqueReport(
      expression: "id",
      mode: .collection,
      referencePath: nil,
      checkedFiles: 2,
      filesWithValue: 2,
      missingPaths: [],
      collisions: [UniqueCollision(value: .string("same"), paths: ["/a.md", "/b.md"])],
      diagnostics: []
    )

    let text = try UniqueRenderer.render(report, format: .text, requireValue: false)
    #expect(text.raw.contains("✗ id = \"same\" occurs in 2 files"))
    #expect(text.raw.contains("Checked 2 files"))

    let json = try UniqueRenderer.render(report, format: .json, requireValue: false)
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["expression"] as? String == "id")
    #expect(object["referencePath"] == nil)
    #expect(json.contains("\u{001B}[") == false)

    let yaml = try UniqueRenderer.render(report, format: .yaml, requireValue: false)
    #expect(try Yams.load(yaml: yaml) != nil)
    #expect(yaml.contains("\u{001B}[") == false)
  }

  @Test
  func `invalid expression produces validation error`() async throws {
    let directory = try makeDirectory()
    defer { try? directory.delete() }
    _ = try writeNote(directory, name: "note.md", frontmatter: "id: one")
    let parsed = try CLIEntry.FrontMatterCommands.Unique.parseAsRoot(["invalid {{{{ syntax", directory.string])
    var command = try #require(parsed as? CLIEntry.FrontMatterCommands.Unique)

    await #expect(throws: ValidationError.self) {
      try await command.run()
    }
  }

  @Test
  func `command exit behavior follows the uniqueness result`() async throws {
    let directory = try makeDirectory()
    defer { try? directory.delete() }
    _ = try writeNote(directory, name: "one.md", frontmatter: "id: shared")
    _ = try writeNote(directory, name: "two.md", frontmatter: "id: shared")

    let failingParsed = try CLIEntry.FrontMatterCommands.Unique.parseAsRoot(["id", directory.string])
    var failing = try #require(failingParsed as? CLIEntry.FrontMatterCommands.Unique)
    await #expect(throws: ExitCode.failure) {
      try await failing.run()
    }

    _ = try writeNote(directory, name: "two.md", frontmatter: "id: distinct")
    let passingParsed = try CLIEntry.FrontMatterCommands.Unique.parseAsRoot(["id", directory.string])
    var passing = try #require(passingParsed as? CLIEntry.FrontMatterCommands.Unique)
    try await passing.run()
  }

  private func analyze(_ expression: String, files: [Path], reference: Path? = nil) throws -> UniqueReport {
    let compiled = try JMESExpression.compile(expression)
    return UniqueAnalyzer.analyze(
      expression: expression,
      compiledExpression: compiled,
      files: files.sorted { $0.string < $1.string },
      reference: reference
    )
  }

  private func makeDirectory() throws -> Path {
    let root = Path.current + "tmp/"
    if root.exists == false {
      try root.mkdir()
    }
    let directory = root + "md-utils-unique-test-\(UUID().uuidString)/"
    try directory.mkdir()
    return directory
  }

  @discardableResult
  private func writeNote(_ directory: Path, name: String, frontmatter: String) throws -> Path {
    let path = directory + name
    try path.write("---\n\(frontmatter)\n---\n# Note\n")
    return path
  }
}
