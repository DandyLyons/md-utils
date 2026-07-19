import Testing
@testable import MarkdownUtilitiesCore

@Suite("Markdown Rule Checker Tests")
struct MarkdownRuleCheckerTests {
  @Test
  func `Rule applicability is distinct from checks`() async throws {
    let rule = MarkdownRuleDefinition(
      name: "published-books",
      applicability: MarkdownRuleApplicability(predicates: [
        MarkdownConstraint(
          id: "books-path",
          predicate: .path(MarkdownPathPredicate(glob: "books/**/*.md"))
        )
      ]),
      requirements: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(
          id: "synopsis",
          predicate: .heading(MarkdownHeadingPredicate(text: "Synopsis"))
        )
      ])
    )
    let checker = MarkdownRuleChecker()
    let selected = MarkdownRecord(
      content: "# Book\n",
      context: MarkdownRecordContext(path: try MarkdownRecordPath("books/dune.md"))
    )
    let skipped = MarkdownRecord(
      content: "# Book\n",
      context: MarkdownRecordContext(path: try MarkdownRecordPath("notes/dune.md"))
    )

    let selectedAssessment = try await checker.assess(selected, against: rule)
    let skippedAssessment = try await checker.assess(skipped, against: rule)

    #expect(selectedAssessment.applicable)
    #expect(selectedAssessment.passes == false)
    #expect(selectedAssessment.diagnostics.contains { $0.constraintID == "synopsis" })
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
    let registry = try MarkdownTypeRegistry(definitions: [book])
    let rule = MarkdownRuleDefinition(
      name: "book-policy",
      applicability: MarkdownRuleApplicability(anyTypes: [MarkdownTypeName(rawValue: "Book")])
    )
    let checker = MarkdownRuleChecker(typeRegistry: registry)

    #expect(try await checker.isApplicable(MarkdownRecord(content: "# Book\n"), to: rule))
    #expect(try await checker.isApplicable(MarkdownRecord(content: "# Note\n"), to: rule) == false)
  }

  @Test
  func `Rule recommendations do not fail a passing policy`() async throws {
    let rule = MarkdownRuleDefinition(
      name: "book-quality",
      requirements: MarkdownConstraintGroup(recommendations: [
        MarkdownConstraint(id: "reviews", predicate: .heading(MarkdownHeadingPredicate(text: "Reviews")))
      ])
    )

    let assessment = try await MarkdownRuleChecker().assess(
      MarkdownRecord(content: "# Book\n"),
      against: rule
    )

    #expect(assessment.applicable)
    #expect(assessment.passes)
    #expect(assessment.diagnostics.count == 1)
    #expect(assessment.diagnostics[0].severity == .advisory)
  }
}
