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

  /// Creates a canonical record with a portable logical path.
  private func record(path: String) throws -> MarkdownRecord {
    MarkdownRecord(
      content: "# Record",
      context: MarkdownRecordContext(path: try MarkdownRecordPath(path))
    )
  }
}
