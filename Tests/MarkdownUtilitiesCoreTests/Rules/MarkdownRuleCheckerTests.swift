import Testing
@testable import MarkdownUtilitiesCore

@Suite("Markdown Rule Checker Tests")
struct MarkdownRuleCheckerTests {
  @Test
  func `Path includes use any-of semantics and exclusions take precedence`() async throws {
    let checker = try checker(for: MarkdownRuleDefinition(
      name: "published",
      applicability: MarkdownRuleApplicability(
        paths: ["books/**/*.md", "articles/**/*.md"],
        excludePaths: ["**/drafts/**"]
      )
    ))

    #expect(try await checker.isApplicable(record(path: "books/dune.md"), toRuleNamed: "published"))
    #expect(try await checker.isApplicable(record(path: "articles/news.md"), toRuleNamed: "published"))
    #expect(try await checker.isApplicable(record(path: "books/drafts/dune.md"), toRuleNamed: "published") == false)
    #expect(try await checker.isApplicable(record(path: "notes/dune.md"), toRuleNamed: "published") == false)
    #expect(try await checker.isApplicable(MarkdownRecord(content: "# Pathless"), toRuleNamed: "published") == false)
  }

  @Test
  func `Exclusion-only applicability admits pathless and nonexcluded records`() async throws {
    let checker = try checker(for: MarkdownRuleDefinition(
      name: "not-archive",
      applicability: MarkdownRuleApplicability(excludePaths: ["archive/**"])
    ))

    #expect(try await checker.isApplicable(record(path: "notes/current.md"), toRuleNamed: "not-archive"))
    #expect(try await checker.isApplicable(record(path: "archive/old.md"), toRuleNamed: "not-archive") == false)
    #expect(try await checker.isApplicable(MarkdownRecord(content: "# Pathless"), toRuleNamed: "not-archive"))
  }

  @Test
  func `Path globs remain conjunctive with applicability predicates`() async throws {
    let checker = try checker(for: MarkdownRuleDefinition(
      name: "book-notes",
      applicability: MarkdownRuleApplicability(
        paths: ["books/**"],
        requirements: [
          MarkdownRuleRequirement(
            id: "notes",
            predicate: .markdown(.path(MarkdownPathPredicate(glob: "**/notes/*.md")))
          )
        ]
      )
    ))

    #expect(try await checker.isApplicable(record(path: "books/notes/dune.md"), toRuleNamed: "book-notes"))
    #expect(try await checker.isApplicable(record(path: "books/dune.md"), toRuleNamed: "book-notes") == false)
  }

  @Test
  func `Rule applicability is distinct from checks`() async throws {
    let checker = try checker(for: MarkdownRuleDefinition(
      name: "published-books",
      applicability: MarkdownRuleApplicability(requirements: [
        MarkdownRuleRequirement(
          id: "books-path",
          predicate: .markdown(.path(MarkdownPathPredicate(glob: "books/**/*.md")))
        )
      ]),
      checks: [
        MarkdownRuleCheck(
          id: "synopsis",
          predicate: .markdown(.heading(MarkdownHeadingPredicate(text: "Synopsis")))
        )
      ]
    ))
    let selected = MarkdownRecord(
      content: "# Book\n",
      context: MarkdownRecordContext(path: try MarkdownRecordPath("books/dune.md"))
    )
    let skipped = MarkdownRecord(
      content: "# Book\n",
      context: MarkdownRecordContext(path: try MarkdownRecordPath("notes/dune.md"))
    )

    let selectedAssessment = try await checker.assess(selected, ruleNamed: "published-books")
    let skippedAssessment = try await checker.assess(skipped, ruleNamed: "published-books")

    #expect(selectedAssessment.status == .failed)
    #expect(selectedAssessment.applicable)
    #expect(selectedAssessment.passes == false)
    #expect(selectedAssessment.diagnostics.contains { $0.constraintID == "synopsis" })
    #expect(skippedAssessment.status == .notApplicable)
    #expect(skippedAssessment.applicable == false)
    #expect(skippedAssessment.diagnostics.isEmpty)
  }

  @Test
  func `Rule applicability can reference confirmed Markdown types`() async throws {
    let book = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(id: "book-heading", predicate: .heading(MarkdownHeadingPredicate(text: "Book")))
      ])
    )
    let typeRegistry = try MarkdownTypeRegistry(definitions: [book])
    let checker = try checker(
      for: MarkdownRuleDefinition(
        name: "book-policy",
        applicability: MarkdownRuleApplicability(anyTypes: [MarkdownTypeName(rawValue: "Book")])
      ),
      typeRegistry: typeRegistry
    )

    #expect(try await checker.isApplicable(MarkdownRecord(content: "# Book\n"), toRuleNamed: "book-policy"))
    #expect(try await checker.isApplicable(MarkdownRecord(content: "# Note\n"), toRuleNamed: "book-policy") == false)
  }

  @Test
  func `Rule recommendations do not fail a passing policy`() async throws {
    let checker = try checker(for: MarkdownRuleDefinition(
      name: "book-quality",
      checks: [
        MarkdownRuleCheck(
          id: "reviews",
          severity: .advisory,
          predicate: .markdown(.heading(MarkdownHeadingPredicate(text: "Reviews")))
        )
      ]
    ))

    let assessment = try await checker.assess(
      MarkdownRecord(content: "# Book\n"),
      ruleNamed: "book-quality"
    )

    #expect(assessment.status == .passed)
    #expect(assessment.applicable)
    #expect(assessment.passes)
    #expect(assessment.diagnostics.count == 1)
    #expect(assessment.diagnostics[0].severity == .advisory)
  }

  private func checker(
    for rule: MarkdownRuleDefinition,
    typeRegistry: MarkdownTypeRegistry? = nil
  ) throws -> MarkdownRuleChecker {
    MarkdownRuleChecker(registry: try MarkdownRuleCompiler(typeRegistry: typeRegistry).compile([rule]))
  }

  @Test
  func `Type enforcement fails selected nonconforming records and preserves diagnostics`() async throws {
    let name = MarkdownTypeName(rawValue: "Book")
    let types = try MarkdownTypeRegistry(definitions: [MarkdownTypeDefinition(
      name: name,
      version: "1",
      body: MarkdownConstraintGroup(
        requirements: [.init(id: "title", predicate: .heading(.init(text: "Book")))],
        recommendations: [.init(id: "reviews", predicate: .heading(.init(text: "Reviews")))]
      )
    )])
    let rules = try checker(for: MarkdownRuleDefinition(
      name: "books",
      applicability: .init(paths: ["books/**"]),
      checks: [.init(id: "contract", predicate: .typeConformance(name))]
    ), typeRegistry: types)

    for content in ["# Book\n", "# Missing\n", "---\ninvalid: [\n---\n# Book\n"] {
      let input = MarkdownRecord(content: content, context: .init(path: try MarkdownRecordPath("books/a.md")))
      let expected = try await MarkdownTypeChecker(registry: types).assess(input, as: name)
      let actual = try await rules.assess(input, ruleNamed: "books")
      #expect(actual.applicable)
      #expect(actual.passes == expected.conforms)
      #expect(actual.diagnostics == expected.diagnostics)
      #expect(actual.typeAssessments["contract"] == expected)
    }
    let outside = try await rules.assess(record(path: "notes/a.md"), ruleNamed: "books")
    #expect(outside.status == .notApplicable)
  }

  @Test
  func `Unknown enforced type fails compilation at check source`() throws {
    let rule = MarkdownRuleDefinition(
      name: "books",
      checks: [.init(id: "contract", predicate: .typeConformance(.init(rawValue: "Missing")))],
      source: "rules/books.mdrule.json"
    )
    let error = try #require(throws: MarkdownRuleCompilationError.self) {
      try MarkdownRuleCompiler().compile([rule])
    }
    #expect(error.diagnostics.map(\.code) == [.missingType])
    #expect(error.diagnostics.first?.location == "rules[0].checks[0]")
    #expect(error.diagnostics.first?.message.contains("rules/books.mdrule.json") == true)
    #expect(error.diagnostics.first?.message.contains("Missing") == true)
  }

  @Test
  func `Multiple rules enforce shared schema types with original fix its`() async throws {
    let name = MarkdownTypeName(rawValue: "Book")
    let types = try MarkdownTypeRegistry(definitions: [.init(
      name: name,
      version: "1",
      frontmatter: .init(schemas: [.inline(.object([
        "type": .string("object"),
        "required": .array([.string("kind")]),
        "properties": .object(["kind": .object(["const": .string("book")])]),
      ]))])
    )])
    let definitions = ["first", "second"].map { ruleName in
      MarkdownRuleDefinition(
        name: ruleName,
        applicability: .init(paths: ["books/**"]),
        checks: [.init(id: "contract", predicate: .typeConformance(name))]
      )
    }
    let rules = MarkdownRuleChecker(registry: try MarkdownRuleCompiler(typeRegistry: types).compile(definitions))
    let input = MarkdownRecord(content: "---\ntitle: Dune\n---\n# Book", context: .init(path: try MarkdownRecordPath("books/dune.md")))
    let expected = try await MarkdownTypeChecker(registry: types).assess(input, as: name)
    #expect(expected.conforms == false)
    #expect(expected.diagnostics.flatMap(\.fixIts).isEmpty == false)
    for definition in definitions {
      let actual = try await rules.assess(input, ruleNamed: definition.name)
      #expect(actual.status == .failed)
      #expect(actual.typeAssessments["contract"] == expected)
      #expect(actual.diagnostics == expected.diagnostics)
    }
  }

  @Test
  func `Required schema migration changes malformed type hint outcomes`() async throws {
    let schema = MarkdownJSONSchemaSource.inline(.object(["type": .string("object")]))
    let name = MarkdownTypeName(rawValue: "Book")
    let types = try MarkdownTypeRegistry(definitions: [.init(
      name: name, version: "1",
      frontmatter: .init(presence: .required, schemas: [schema])
    )])
    let rules = MarkdownRuleChecker(registry: try MarkdownRuleCompiler(typeRegistry: types).compile([
      .init(name: "legacy", checks: [
        .init(id: "schema", predicate: .frontmatterSchema(source: schema, presence: .required))
      ]),
      .init(name: "converted", checks: [
        .init(id: "contract", predicate: .typeConformance(name))
      ]),
    ]))
    let input = MarkdownRecord(content: "---\ntitle: Dune\n$md-utils:\n  typeHints: invalid\n---\n# Book")
    let legacy = try await rules.assess(input, ruleNamed: "legacy")
    let converted = try await rules.assess(input, ruleNamed: "converted")
    #expect(legacy.status == .passed)
    #expect(converted.status == .failed)
    #expect(converted.diagnostics.contains { $0.code == "type.hint.malformed" })
  }

  /// Creates a canonical record with a portable logical path.
  private func record(path: String) throws -> MarkdownRecord {
    MarkdownRecord(
      content: "# Record",
      context: MarkdownRecordContext(path: try MarkdownRecordPath(path))
    )
  }
}
