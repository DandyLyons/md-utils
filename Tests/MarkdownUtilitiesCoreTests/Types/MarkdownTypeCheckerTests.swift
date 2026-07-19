import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("Markdown Type Checker Tests")
struct MarkdownTypeCheckerTests {
  @Test
  func `A record can structurally conform to multiple types`() async throws {
    let book = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(id: "book", predicate: .heading(MarkdownHeadingPredicate(text: "Book", level: 1)))
      ])
    )
    let document = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Document"),
      version: "1.0.0",
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(id: "title", predicate: .heading(MarkdownHeadingPredicate(text: "Book")))
      ])
    )
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [book, document]))

    let types = await checker.conformingTypes(for: MarkdownRecord(content: "# Book\n"))

    #expect(types == Set([
      MarkdownTypeName(rawValue: "Book"),
      MarkdownTypeName(rawValue: "Document")
    ]))
  }

  @Test
  func `All frontmatter schemas must pass`() async throws {
    let definition = try definitionWithSchemas([
      [
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "required": ["title"]
      ],
      [
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "required": ["author"]
      ]
    ])
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let record = MarkdownRecord(content: "---\ntitle: Dune\n---\n# Book\n")

    let assessment = try await checker.assess(record, as: "Book")

    #expect(assessment.conforms == false)
    #expect(assessment.errors.contains { $0.message.contains("author") })
  }

  @Test
  func `Optional frontmatter skips schemas when absent`() async throws {
    var definition = try definitionWithSchemas([[
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["title"]
    ]])
    definition.frontmatter.presence = .optional
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))

    let assessment = try await checker.assess(MarkdownRecord(content: "# Book\n"), as: "Book")

    #expect(assessment.conforms)
  }

  @Test
  func `Explicitly required frontmatter can be created without inventing values`() async throws {
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      frontmatter: MarkdownFrontmatterDefinition(presence: .required)
    )
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let record = MarkdownRecord(content: "# Book\n")
    let initial = try await checker.assess(record, as: "Book")

    let updated = try MarkdownTypeFixer.apply(initial.errors.flatMap(\.fixIts), to: record)

    #expect(updated.content == "---\n---\n# Book\n")
    #expect(try await checker.assess(updated, as: "Book").conforms)
  }

  @Test
  func `Nominal-like tag requirement remains structural`() async throws {
    let definition = try definitionWithSchemas([[
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["tags"],
      "properties": [
        "tags": [
          "type": "array",
          "contains": ["const": "books"]
        ]
      ]
    ]])
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let matching = MarkdownRecord(content: "---\ntags: [books, fiction]\n---\n# Book\n")
    let nonmatching = MarkdownRecord(content: "---\ntags: [fiction]\n---\n# Book\n")

    #expect(try await checker.assess(matching, as: "Book").conforms)
    #expect(try await checker.assess(nonmatching, as: "Book").conforms == false)
  }

  @Test
  func `Invalid YAML is an assessment diagnostic`() async throws {
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0"
    )
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let record = MarkdownRecord(content: "---\ntitle: [\n---\n# Book\n")

    let assessment = try await checker.assess(record, as: "Book")

    #expect(assessment.conforms == false)
    #expect(assessment.errors.contains { $0.code == "record.frontmatter.invalid-yaml" })
  }

  @Test
  func `Assess direct-child and descendant heading relationships`() async throws {
    let direct = MarkdownConstraint(
      id: "direct",
      predicate: .headingRelationship(MarkdownHeadingRelationshipPredicate(
        parent: MarkdownHeadingPredicate(text: "Book"),
        child: MarkdownHeadingPredicate(text: "Synopsis"),
        relationship: .directChild
      ))
    )
    let descendant = MarkdownConstraint(
      id: "descendant",
      predicate: .headingRelationship(MarkdownHeadingRelationshipPredicate(
        parent: MarkdownHeadingPredicate(text: "Book"),
        child: MarkdownHeadingPredicate(text: "Characters"),
        relationship: .descendant
      ))
    )
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      body: MarkdownConstraintGroup(requirements: [direct, descendant])
    )
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let record = MarkdownRecord(content: "# Book\n\n### Synopsis\n\n#### Characters\n")

    let assessment = try await checker.assess(record, as: "Book")

    #expect(assessment.conforms)
  }

  @Test
  func `Recommendations produce advisories without failing conformance`() async throws {
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      body: MarkdownConstraintGroup(recommendations: [
        MarkdownConstraint(
          id: "reviews",
          predicate: .section(MarkdownSectionPredicate(
            heading: MarkdownHeadingPredicate(text: "Reviews"),
            content: .any
          ))
        )
      ])
    )
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))

    let assessment = try await checker.assess(MarkdownRecord(content: "# Book\n"), as: "Book")

    #expect(assessment.conforms)
    #expect(assessment.advisories.count == 1)
    #expect(assessment.advisories[0].fixIts[0].safety == .advisoryOnly)
  }

  @Test
  func `Section presence and nonempty content are distinct constraints`() async throws {
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(
          id: "reviews-present",
          predicate: .section(MarkdownSectionPredicate(
            heading: MarkdownHeadingPredicate(text: "Reviews"),
            content: .any
          ))
        ),
        MarkdownConstraint(
          id: "reviews-content",
          predicate: .section(MarkdownSectionPredicate(
            heading: MarkdownHeadingPredicate(text: "Reviews"),
            content: .nonEmpty
          ))
        ),
      ])
    )
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))

    let assessment = try await checker.assess(
      MarkdownRecord(content: "# Book\n\n## Reviews\n"),
      as: "Book"
    )

    #expect(assessment.errors.map(\.constraintID) == ["reviews-content"])
    #expect(assessment.errors[0].fixIts.isEmpty)
  }

  @Test
  func `Required context path participates in conformance`() async throws {
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      context: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(id: "location", predicate: .path(MarkdownPathPredicate(glob: "books/**/*.md")))
      ])
    )
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let matching = MarkdownRecord(
      content: "# Book\n",
      context: MarkdownRecordContext(path: try MarkdownRecordPath("books/dune.md"))
    )
    let missing = MarkdownRecord(content: "# Book\n")

    #expect(try await checker.assess(matching, as: "Book").conforms)
    #expect(try await checker.assess(missing, as: "Book").errors.contains { $0.code == "context.path.unavailable" })
  }

  @Test
  func `System type hints are excluded from schema-visible frontmatter`() async throws {
    let definition = try definitionWithSchemas([[
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["title"],
      "properties": ["title": ["type": "string"]],
      "additionalProperties": false
    ]])
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let record = MarkdownRecord(content: """
    ---
    $md-utils:
      typeHints: [Book]
    title: Dune
    ---
    # Book
    """)

    let assessment = try await checker.assess(record, as: "Book")
    let hints = await checker.verifyTypeHints(in: record)

    #expect(assessment.conforms)
    #expect(hints.count == 1)
    #expect(hints[0].status == .confirmed)
  }

  @Test
  func `Apply deterministic and input-required frontmatter fixes`() async throws {
    let definition = try definitionWithSchemas([[
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["kind", "title"],
      "properties": [
        "kind": ["const": "book"],
        "title": ["type": "string"]
      ]
    ]])
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let record = MarkdownRecord(content: "---\nauthor: Frank Herbert\n---\n# Book\n")
    let initial = try await checker.assess(record, as: "Book")
    let fixIts = initial.errors.flatMap(\.fixIts)

    #expect(fixIts.contains { $0.safety == .automatic })
    #expect(fixIts.contains { $0.safety == .requiresInput })

    let updated = try MarkdownTypeFixer.apply(
      fixIts,
      to: record,
      inputs: ["title": .string("Dune")]
    )
    let final = try await checker.assess(updated, as: "Book")

    #expect(final.conforms)
    #expect(updated.content.contains("kind: book"))
    #expect(updated.content.contains("title: Dune"))
  }

  @Test
  func `Generated fixes preserve unaffected frontmatter and body text`() async throws {
    let definition = try definitionWithSchemas([[
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["kind"],
      "properties": ["kind": ["const": "book"]]
    ]])
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let content = """
    ---
    # Keep this comment and scalar style.
    description: >-
      A desert
      story
    ---
    # Dune *Novel*

    Keep this body byte-for-byte.
    """
    let record = MarkdownRecord(content: content)
    let assessment = try await checker.assess(record, as: "Book")

    let updated = try MarkdownTypeFixer.apply(assessment.errors.flatMap(\.fixIts), to: record)

    #expect(updated.content.contains("# Keep this comment and scalar style."))
    #expect(updated.content.contains("description: >-\n  A desert\n  story"))
    #expect(updated.content.hasSuffix("# Dune *Novel*\n\nKeep this body byte-for-byte."))
    #expect(updated.content.contains("kind: book\n---"))
  }

  @Test
  func `JSON Schema default is never an automatic fix`() async throws {
    let definition = try definitionWithSchemas([[
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["status"],
      "properties": ["status": ["type": "string", "default": "draft"]]
    ]])
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))

    let assessment = try await checker.assess(
      MarkdownRecord(content: "---\ntitle: Dune\n---\n"),
      as: "Book"
    )

    #expect(assessment.errors.flatMap(\.fixIts).map(\.safety) == [.requiresInput])
  }

  private func definitionWithSchemas(
    _ schemas: [[String: Any]]
  ) throws -> MarkdownTypeDefinition {
    MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      frontmatter: MarkdownFrontmatterDefinition(
        schemas: try schemas.map { .inline(try JSONValue(any: $0)) }
      )
    )
  }
}
