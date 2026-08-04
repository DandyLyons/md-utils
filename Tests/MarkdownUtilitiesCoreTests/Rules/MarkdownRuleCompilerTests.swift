import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("Markdown rule compilation")
struct MarkdownRuleCompilerTests {
  @Test
  func `Compiler reports deterministic duplicate capability and operand diagnostics`() throws {
    let timestamp = try #require(MarkdownRuleDateTimeLiteral("2026-01-01"))
    let definitions = [
      MarkdownRuleDefinition(
        name: "duplicate",
        applicability: MarkdownRuleApplicability(requirements: [
          MarkdownRuleRequirement(id: "same", predicate: .modifiedAfter(timestamp)),
          MarkdownRuleRequirement(id: "same", predicate: .pathRegularExpression("[")),
          MarkdownRuleRequirement(
            id: "count",
            predicate: .bodyLineCount(MarkdownRuleIntegerRange(minimum: 3, maximum: 1))
          ),
        ])
      ),
      MarkdownRuleDefinition(name: "duplicate"),
    ]

    let error = try #require(throws: MarkdownRuleCompilationError.self) {
      try MarkdownRuleCompiler().compile(definitions)
    }
    #expect(error.diagnostics == error.diagnostics.sorted {
      ($0.location, $0.code.rawValue, $0.message) < ($1.location, $1.code.rawValue, $1.message)
    })
    #expect(Set(error.diagnostics.map(\.code)) == [
      .duplicateName, .duplicateIdentifier, .missingCapability, .invalidOperand,
    ])
  }

  @Test
  func `JMESPath is accepted only through an explicit provider`() throws {
    let definition = MarkdownRuleDefinition(
      name: "query",
      applicability: MarkdownRuleApplicability(requirements: [
        MarkdownRuleRequirement(id: "query", predicate: .frontmatterJMESPath("ready"))
      ])
    )

    let missing = try #require(throws: MarkdownRuleCompilationError.self) {
      try MarkdownRuleCompiler().compile([definition])
    }
    #expect(missing.diagnostics.map(\.code) == [.missingCapability])

    let registry = try MarkdownRuleCompiler(queryProvider: QueryProvider()).compile([definition])
    #expect(registry.rule(named: "query")?.requiredCapabilities == [.frontmatterJMESPath])
  }

  @Test
  func `Missing modification context produces failed assessment evidence`() async throws {
    let timestamp = try #require(MarkdownRuleDateTimeLiteral("2026-01-01"))
    let definition = MarkdownRuleDefinition(
      name: "recent",
      applicability: MarkdownRuleApplicability(requirements: [
        MarkdownRuleRequirement(id: "modified", predicate: .modifiedAfter(timestamp))
      ])
    )
    let registry = try MarkdownRuleCompiler(capabilities: [.modificationDate]).compile([definition])

    let assessment = try await MarkdownRuleChecker(registry: registry).assess(
      MarkdownRecord(content: "# Record"),
      ruleNamed: "recent"
    )

    #expect(assessment.status == .failed)
    #expect(assessment.evidence.map(\.status) == [.matched, .unavailable])
    #expect(assessment.applicabilityDiagnostics.first?.location == "record.context")
  }

  @Test
  func `Compilation requests heading analysis only for structural predicates`() async throws {
    let frontmatterOnly = MarkdownRuleDefinition(
      name: "tagged",
      applicability: MarkdownRuleApplicability(requirements: [
        MarkdownRuleRequirement(
          id: "tag",
          predicate: .frontmatterField(key: "tags", operation: .includes(.string("sermonNotes")))
        )
      ]),
      checks: [
        MarkdownRuleCheck(
          id: "schema",
          predicate: .frontmatterSchema(source: .inline(.object([:])), presence: .required)
        )
      ]
    )
    let frontmatterRegistry = try MarkdownRuleCompiler().compile([frontmatterOnly])
    let compiledFrontmatter = try #require(frontmatterRegistry.rule(named: "tagged"))
    #expect(compiledFrontmatter.analysisRequirements.contains(.headings) == false)

    let lightweight = await MarkdownRecordAnalyzer.analyze(
      MarkdownRecord(content: "---\ntags: [sermonNotes]\n---\n# Sermon"),
      requirements: compiledFrontmatter.analysisRequirements
    )
    #expect(lightweight.headings.isEmpty)

    let headingCheck = MarkdownRuleDefinition(
      name: "structured",
      checks: [
        MarkdownRuleCheck(
          id: "summary",
          predicate: .markdown(.heading(MarkdownHeadingPredicate(text: "Summary")))
        )
      ]
    )
    let headingRegistry = try MarkdownRuleCompiler().compile([headingCheck])
    let compiledHeading = try #require(headingRegistry.rule(named: "structured"))
    #expect(compiledHeading.analysisRequirements.contains(.headings))

    let headingType = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "HeadingType"),
      version: "1",
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(
          id: "title",
          predicate: .heading(MarkdownHeadingPredicate(text: "Title"))
        )
      ])
    )
    let typeRegistry = try MarkdownTypeRegistry(definitions: [headingType])
    let typedRegistry = try MarkdownRuleCompiler(typeRegistry: typeRegistry).compile([
      MarkdownRuleDefinition(
        name: "typed",
        applicability: MarkdownRuleApplicability(anyTypes: [headingType.name])
      )
    ])
    let compiledTyped = try #require(typedRegistry.rule(named: "typed"))
    #expect(compiledTyped.analysisRequirements.contains(.headings))
  }
}

private struct QueryProvider: MarkdownRuleQueryCapabilityProvider {
  let capabilities: Set<MarkdownRuleRuntimeCapability> = [.frontmatterJMESPath]

  func validateJMESPath(_ expression: String) throws {
    if expression.isEmpty { throw QueryError.invalid }
  }

  func evaluateJMESPath(_ expression: String, frontmatter: JSONValue) throws -> JSONValue? {
    frontmatter.objectValue?[expression]
  }

  enum QueryError: Error { case invalid }
}
