import Foundation
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import MarkdownUtilities

@Suite("Markdown Type File Registry Loader Tests")
struct MarkdownTypeFileRegistryLoaderTests {
  @Test
  func `Load YAML and JSON definitions with referenced schemas`() async throws {
    let project = try makeProject()
    defer { try? project.delete() }
    try (project + ".md-utils/schemas/").mkpath()
    try (project + ".md-utils/schemas/book.schema.json").write("""
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["title"]
    }
    """)
    try (project + ".md-utils/types/book.mdtype.yaml").write("""
    md-utils-type-schema: "1"
    name: Book
    version: "1.0.0"
    frontmatter:
      schemas:
        - ref: ../schemas/book.schema.json
    body:
      requirements: []
      recommendations: []
    context:
      requirements: []
      recommendations: []
    """)
    try (project + ".md-utils/types/document.mdtype.json").write("""
    {
      "md-utils-type-schema": "1",
      "name": "Document",
      "version": "draft-1",
      "frontmatter": { "schemas": [] },
      "body": { "requirements": [], "recommendations": [] },
      "context": { "requirements": [], "recommendations": [] }
    }
    """)

    let registry = try MarkdownTypeFileRegistryLoader.load(projectRoot: project)

    #expect(registry.definitions.map(\.name.rawValue) == ["Book", "Document"])
    let checker = MarkdownTypeChecker(registry: registry)
    let assessment = try await checker.assess(
      MarkdownRecord(content: "---\ntitle: Dune\n---\n"),
      as: "Book"
    )
    #expect(assessment.conforms)
  }

  @Test
  func `Load only mdtype definition files recursively`() throws {
    let project = try makeProject()
    defer { try? project.delete() }
    let types = project + ".md-utils/types/"
    let nested = types + "nested/"
    try nested.mkpath()

    try (types + "book.mdtype.yaml").write("""
    md-utils-type-schema: "1"
    name: Book
    version: "1.0.0"
    frontmatter: { schemas: [] }
    body: { requirements: [], recommendations: [] }
    context: { requirements: [], recommendations: [] }
    """)
    try (types + "article.mdtype.yml").write("""
    md-utils-type-schema: "1"
    name: Article
    version: "1.0.0"
    frontmatter: { schemas: [] }
    body: { requirements: [], recommendations: [] }
    context: { requirements: [], recommendations: [] }
    """)
    try (nested + "document.mdtype.json").write("""
    {
      "md-utils-type-schema": "1",
      "name": "Document",
      "version": "1.0.0",
      "frontmatter": { "schemas": [] },
      "body": { "requirements": [], "recommendations": [] },
      "context": { "requirements": [], "recommendations": [] }
    }
    """)

    try (types + "legacy.type.yaml").write("""
    md-utils-type-schema: "1"
    name: Legacy
    version: "1.0.0"
    frontmatter: { schemas: [] }
    body: { requirements: [], recommendations: [] }
    context: { requirements: [], recommendations: [] }
    """)
    try (types + "notes.yaml").write("not: a type definition")
    try (types + "schema.json").write("{}")

    let files = try MarkdownTypeFileRegistryLoader.definitionFiles(projectRoot: project)
    #expect(files.map(\.lastComponent) == [
      "article.mdtype.yml",
      "book.mdtype.yaml",
      "document.mdtype.json",
    ])

    let registry = try MarkdownTypeFileRegistryLoader.load(projectRoot: project)
    #expect(registry.definitions.map(\.name.rawValue) == ["Article", "Book", "Document"])
  }

  @Test
  func `Reject schema references outside project root`() async throws {
    let project = try makeProject()
    defer { try? project.delete() }
    let outside = Path(NSTemporaryDirectory()) + "outside-schema-\(UUID().uuidString).json"
    defer { try? outside.delete() }
    try outside.write("{}")
    try (project + ".md-utils/types/book.mdtype.yaml").write("""
    md-utils-type-schema: "1"
    name: Book
    version: "1.0.0"
    frontmatter:
      schemas:
        - ref: ../../../\(outside.lastComponent)
    body:
      requirements: []
      recommendations: []
    context:
      requirements: []
      recommendations: []
    """)

    #expect(throws: MarkdownTypeFileLoaderError.self) {
      try MarkdownTypeFileRegistryLoader.load(projectRoot: project)
    }
  }

  @Test
  func `Reject schema symlinks that escape the project root`() async throws {
    let project = try makeProject()
    defer { try? project.delete() }
    let outside = Path(NSTemporaryDirectory()) + "outside-schema-\(UUID().uuidString).json"
    defer { try? outside.delete() }
    try outside.write("{}")
    let schemas = project + ".md-utils/schemas/"
    try schemas.mkpath()
    let link = schemas + "escaped.schema.json"
    try FileManager.default.createSymbolicLink(
      atPath: link.string,
      withDestinationPath: outside.string
    )
    try writeBookDefinition(in: project, schemaReference: "../schemas/escaped.schema.json")

    #expect(throws: MarkdownTypeFileLoaderError.self) {
      try MarkdownTypeFileRegistryLoader.load(projectRoot: project)
    }
  }

  @Test
  func `Resolve and cache nested external schema references`() async throws {
    let project = try makeProject()
    defer { try? project.delete() }
    let schemas = project + ".md-utils/schemas/"
    try schemas.mkpath()
    try (schemas + "book.schema.json").write("""
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "properties": {
        "kind": { "const": "book" },
        "author": { "$ref": "person.schema.json" }
      },
      "required": ["kind", "author"]
    }
    """)
    try (schemas + "person.schema.json").write("""
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "properties": { "name": { "type": "string" } },
      "required": ["name"]
    }
    """)
    try writeBookDefinition(in: project, schemaReference: "../schemas/book.schema.json")

    let checker = MarkdownTypeChecker(
      registry: try MarkdownTypeFileRegistryLoader.load(projectRoot: project)
    )
    let valid = MarkdownRecord(content: "---\nkind: book\nauthor:\n  name: Frank Herbert\n---\n")
    let invalid = MarkdownRecord(content: "---\nkind: book\nauthor: {}\n---\n")
    let missingRootProperty = MarkdownRecord(content: "---\nauthor:\n  name: Frank Herbert\n---\n")

    #expect(try await checker.assess(valid, as: "Book").conforms)
    let invalidAssessment = try await checker.assess(invalid, as: "Book")
    #expect(invalidAssessment.conforms == false)
    #expect(invalidAssessment.errors.flatMap(\.fixIts).contains { fixIt in
      fixIt.edits.contains(.requestFrontmatterValue(path: ["author", "name"]))
    })
    let missingAssessment = try await checker.assess(missingRootProperty, as: "Book")
    #expect(missingAssessment.errors.flatMap(\.fixIts).contains { $0.safety == .automatic })
  }

  @Test
  func `Reject external schema reference cycles while loading registry`() async throws {
    let project = try makeProject()
    defer { try? project.delete() }
    let schemas = project + ".md-utils/schemas/"
    try schemas.mkpath()
    try (schemas + "a.schema.json").write("""
    { "$schema": "https://json-schema.org/draft/2020-12/schema", "$ref": "b.schema.json" }
    """)
    try (schemas + "b.schema.json").write("""
    { "$schema": "https://json-schema.org/draft/2020-12/schema", "$ref": "a.schema.json" }
    """)
    try writeBookDefinition(in: project, schemaReference: "../schemas/a.schema.json")

    do {
      _ = try MarkdownTypeFileRegistryLoader.load(projectRoot: project)
      Issue.record("Expected a schema reference cycle error")
    } catch let error as MarkdownTypeDefinitionError {
      guard case .schemaReferenceCycle(let type, let resources) = error else {
        Issue.record("Expected schemaReferenceCycle, received \(error)")
        return
      }
      #expect(type == "Book")
      #expect(resources.count == 3)
    }
  }

  @Test
  func `Read a filesystem record with project-relative logical context`() async throws {
    let project = try makeProject()
    defer { try? project.delete() }
    let file = project + "books/dune.md"
    try file.parent().mkpath()
    try file.write("# Dune\n")

    let record = try MarkdownRecordFileAdapter.read(file, projectRoot: project)

    #expect(record.content == "# Dune\n")
    let path = try #require(record.context.path)
    let identity = try #require(record.identity)
    #expect(path.rawValue == "books/dune.md")
    #expect(identity.rawValue == "books/dune.md")
  }

  @Test
  func `Reject a filesystem record outside its project context`() async throws {
    let project = try makeProject()
    defer { try? project.delete() }
    let outside = Path(NSTemporaryDirectory()) + "outside-record-\(UUID().uuidString).md"
    defer { try? outside.delete() }
    try outside.write("# Outside\n")

    #expect(throws: MarkdownTypeFileLoaderError.self) {
      try MarkdownRecordFileAdapter.read(outside, projectRoot: project)
    }
  }

  private func makeProject() throws -> Path {
    let project = Path(NSTemporaryDirectory()) + "md-utils-types-\(UUID().uuidString)"
    try (project + ".md-utils/types/").mkpath()
    return project
  }

  private func writeBookDefinition(in project: Path, schemaReference: String) throws {
    try (project + ".md-utils/types/book.mdtype.yaml").write("""
    md-utils-type-schema: "1"
    name: Book
    version: "1.0.0"
    frontmatter:
      schemas:
        - ref: \(schemaReference)
    body:
      requirements: []
      recommendations: []
    context:
      requirements: []
      recommendations: []
    """)
  }
}
