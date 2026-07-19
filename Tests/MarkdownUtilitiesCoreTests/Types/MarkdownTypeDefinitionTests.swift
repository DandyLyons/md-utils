import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("Markdown Type Definition Tests")
struct MarkdownTypeDefinitionTests {
  @Test
  func `Decode equivalent YAML and JSON definitions`() async throws {
    let yaml = """
    md-utils-type-schema: "1"
    name: Book
    version: draft-3
    frontmatter:
      schemas: []
    body:
      requirements:
        - id: title-heading
          heading:
            text: Book
            level: 1
      recommendations: []
    context:
      requirements: []
      recommendations: []
    """
    let json = """
    {
      "md-utils-type-schema": "1",
      "name": "Book",
      "version": "draft-3",
      "frontmatter": { "schemas": [] },
      "body": {
        "requirements": [
          { "id": "title-heading", "heading": { "text": "Book", "level": 1 } }
        ],
        "recommendations": []
      },
      "context": { "requirements": [], "recommendations": [] }
    }
    """

    let yamlDefinition = try MarkdownTypeDefinitionDecoder.decode(yaml, format: .yaml)
    let jsonDefinition = try MarkdownTypeDefinitionDecoder.decode(json, format: .json)

    #expect(yamlDefinition == jsonDefinition)
    #expect(yamlDefinition.version == "draft-3")
  }

  @Test
  func `Infer required frontmatter when schemas are present`() async throws {
    let definition = MarkdownFrontmatterDefinition(schemas: [
      .inline(.object(["type": .string("object")]))
    ])

    #expect(definition.effectivePresence == .required)
  }

  @Test
  func `Explicit optional frontmatter overrides inferred presence`() async throws {
    let definition = MarkdownFrontmatterDefinition(
      presence: .optional,
      schemas: [.inline(.object(["type": .string("object")]))]
    )

    #expect(definition.effectivePresence == .optional)
  }

  @Test
  func `Reject duplicate constraint identifiers across domains`() async throws {
    let duplicate = MarkdownConstraint(
      id: "location",
      predicate: .path(MarkdownPathPredicate(glob: "books/**/*.md"))
    )
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(
          id: "location",
          predicate: .heading(MarkdownHeadingPredicate(text: "Book"))
        )
      ]),
      context: MarkdownConstraintGroup(requirements: [duplicate])
    )

    #expect(throws: MarkdownTypeDefinitionError.self) {
      try MarkdownTypeRegistry(definitions: [definition])
    }
  }

  @Test
  func `Logical path glob supports recursive zero-segment match`() async throws {
    let direct = try MarkdownRecordPath("books/dune.md")
    let nested = try MarkdownRecordPath("books/classics/dune.md")

    #expect(direct.matches(glob: "books/**/*.md"))
    #expect(nested.matches(glob: "books/**/*.md"))
    #expect(direct.matches(glob: "notes/**/*.md") == false)
  }

  @Test
  func `Reject missing domains and silently ignored collection shapes`() async throws {
    let missingContext = """
    md-utils-type-schema: "1"
    name: Book
    version: "1.0.0"
    frontmatter: { schemas: [] }
    body: { requirements: [], recommendations: [] }
    """
    let malformedSchemas = """
    md-utils-type-schema: "1"
    name: Book
    version: "1.0.0"
    frontmatter: { schemas: not-an-array }
    body: { requirements: [], recommendations: [] }
    context: { requirements: [], recommendations: [] }
    """

    #expect(throws: MarkdownTypeDefinitionError.self) {
      try MarkdownTypeDefinitionDecoder.decode(missingContext, format: .yaml)
    }
    #expect(throws: MarkdownTypeDefinitionError.self) {
      try MarkdownTypeDefinitionDecoder.decode(malformedSchemas, format: .yaml)
    }
  }

  @Test
  func `Reject conflicting schema identifiers across one type contract`() async throws {
    let identifier = "https://example.com/schemas/book"
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      frontmatter: MarkdownFrontmatterDefinition(schemas: [
        .inline(.object([
          "$id": .string(identifier),
          "type": .string("object"),
          "required": .array([.string("title")]),
        ])),
        .inline(.object([
          "$id": .string(identifier),
          "type": .string("object"),
          "required": .array([.string("author")]),
        ])),
      ])
    )

    #expect(throws: MarkdownTypeDefinitionError.self) {
      try MarkdownTypeRegistry(definitions: [definition])
    }
  }
}
