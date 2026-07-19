import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import md_utils

@Suite("types commands", .serialized)
struct TypesCommandsTests {
  @Test
  func `directory output has exactly one trailing slash`() async throws {
    #expect(directoryDisplayPath(Path("/tmp/md-utils-types//")) == "/tmp/md-utils-types/")
    #expect(directoryDisplayPath(Path("/")) == "/")
  }

  @Test
  func `types init is inert after the types directory exists`() async throws {
    let project = Path(NSTemporaryDirectory()) + "types-init-command-\(UUID().uuidString)"
    defer { try? project.delete() }

    let first = try TypesProject.initialize(root: project)
    let second = try TypesProject.initialize(root: project)

    #expect(first.created)
    #expect(second.created == false)
    #expect(first.directory == second.directory)
    #expect(TypesProject.initializationMessage(first).hasPrefix("Initialized Markdown types directory: "))
    #expect(TypesProject.initializationMessage(second) == ".md-utils/types/ has already been initialized.")
  }

  @Test
  func `types command group registers complete surface`() async throws {
    let configuration = CLIEntry.TypesCommands.configuration

    #expect(configuration.commandName == "types")
    #expect(configuration.subcommands.count == 11)
    #expect(configuration.subcommands[0] is CLIEntry.TypesCommands.Init.Type)
    #expect(configuration.subcommands[4] is CLIEntry.TypesCommands.Doctor.Type)
    #expect(configuration.subcommands[5] is CLIEntry.TypesCommands.Check.Type)
    #expect(configuration.subcommands[6] is CLIEntry.TypesCommands.Verify.Type)
    #expect(configuration.subcommands[9] is CLIEntry.TypesCommands.Fix.Type)
    #expect(configuration.subcommands[10] is CLIEntry.TypesCommands.Schema.Type)
  }

  @Test
  func `types create parses definition options`() async throws {
    let parsed = try CLIEntry.parseAsRoot([
      "types", "create", "Book", "--version", "draft-3", "--format", "json"
    ])
    let command = try #require(parsed as? CLIEntry.TypesCommands.Create)

    #expect(command.name == "Book")
    #expect(command.version == "draft-3")
    #expect(command.format == .json)
  }

  @Test
  func `types check parses conformance options`() async throws {
    let parsed = try CLIEntry.parseAsRoot([
      "types", "check", "Book", "books/", "--include-ok", "--no-advisories"
    ])
    let command = try #require(parsed as? CLIEntry.TypesCommands.Check)

    #expect(command.name == "Book")
    #expect(command.options.paths.map(\.string) == ["books/"])
    #expect(command.includeOK)
    #expect(command.noAdvisories)
  }

  @Test
  func `types fix parses safety options`() async throws {
    let parsed = try CLIEntry.parseAsRoot([
      "types", "fix", "Book", "books/dune.md", "--dry-run", "--yes",
      "--constraint", "book-title", "--set", "title=Dune"
    ])
    let command = try #require(parsed as? CLIEntry.TypesCommands.Fix)

    #expect(command.name == "Book")
    #expect(command.dryRun)
    #expect(command.yes)
    #expect(command.constraint == "book-title")
    #expect(command.suppliedValues == ["title=Dune"])
  }

  @Test
  func `types project scaffolds and loads a YAML definition`() async throws {
    let project = Path(NSTemporaryDirectory()) + "types-command-\(UUID().uuidString)"
    defer { try? project.delete() }

    let destination = try TypesProject.createDefinition(
      name: "Book",
      version: "1.0.0",
      format: .yaml,
      root: project,
      output: nil
    )
    let registry = try TypesProject.load(root: project)

    #expect(destination.string.hasSuffix(".md-utils/types/book.mdtype.yaml"))
    let definition = try #require(registry.definition(named: "Book"))
    #expect(definition.version == "1.0.0")
  }

  @Test
  func `types project rejects an output filename without the mdtype suffix`() throws {
    let project = Path(NSTemporaryDirectory()) + "types-command-output-\(UUID().uuidString)"
    defer { try? project.delete() }

    #expect(throws: ValidationError.self) {
      try TypesProject.createDefinition(
        name: "Book",
        version: "1.0.0",
        format: .yaml,
        root: project,
        output: project + "book.yaml"
      )
    }
  }

  @Test
  func `types schema resource is valid JSON`() async throws {
    let content = try TypesProject.schemaContent()
    let data = try #require(content.data(using: .utf8))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
  }

  @Test
  func `types fix dry run does not write and accepted fixes are reassessed`() async throws {
    let project = Path(NSTemporaryDirectory()) + "types-fix-command-\(UUID().uuidString)"
    defer { try? project.delete() }
    let typesDirectory = project + ".md-utils/types/"
    try typesDirectory.mkpath()
    try (typesDirectory + "book.mdtype.yaml").write("""
    md-utils-type-schema: "1"
    name: Book
    version: "1.0.0"
    frontmatter:
      schemas:
        - inline:
            $schema: https://json-schema.org/draft/2020-12/schema
            type: object
            required: [kind, title]
            properties:
              kind: { const: book }
              title: { type: string }
    body:
      requirements:
        - id: book-heading
          heading: { text: Book, level: 1 }
      recommendations: []
    context:
      requirements: []
      recommendations: []
    """)
    let record = project + "book.md"
    let original = "# Notes\n"
    try record.write(original)

    var dryRun = try #require(try CLIEntry.parseAsRoot([
      "types", "fix", "Book", record.string,
      "--root", project.string, "--dry-run", "--yes", "--set", "title=Dune"
    ]) as? CLIEntry.TypesCommands.Fix)
    do {
      try await dryRun.run()
      Issue.record("A dry run with unresolved conformance should fail")
    } catch let code as ExitCode {
      #expect(code == .failure)
    }
    #expect(try record.read(.utf8) == original)

    var fix = try #require(try CLIEntry.parseAsRoot([
      "types", "fix", "Book", record.string,
      "--root", project.string, "--yes", "--set", "title=Dune"
    ]) as? CLIEntry.TypesCommands.Fix)
    try await fix.run()

    let updated = try record.read(.utf8)
    #expect(updated.contains("kind: book"))
    #expect(updated.contains("title: Dune"))
    #expect(updated.contains("# Book"))
    let registry = try TypesProject.load(root: project)
    let assessment = try await MarkdownTypeChecker(registry: registry).assess(
      try MarkdownRecordFileAdapter.read(record, projectRoot: project),
      as: "Book"
    )
    #expect(assessment.conforms)
  }
}
