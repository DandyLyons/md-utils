import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("Recursive rule matching")
struct MarkdownRuleMatchExpressionTests {
  @Test
  func `Nested groups evaluate selectors before checks and retain explanation paths`() async throws {
    let expression = try decode("""
      {"allOf":[{"paths":["Books/**"]},{"anyOf":[
        {"frontmatter":{"status":{"equals":"published"}}},
        {"allOf":[{"document":{"hasHeading":"Preview"}},{"not":{"paths":["Books/Archive/**"]}}]}
      ]}]}
      """)
    let definition = MarkdownRuleDefinition(name: "books", checks: [
      .init(id: "title", predicate: .markdown(.heading(.init(text: "Book"))))
    ], matchExpression: expression)
    let registry = try MarkdownRuleCompiler().compile([definition])
    let checker = MarkdownRuleChecker(registry: registry)
    let selected = try await checker.assess(record("Books/a.md", "# Preview"), ruleNamed: "books")
    #expect(selected.status == .failed)
    #expect(selected.applicable)
    #expect(selected.evidence.contains { $0.id == "match.allOf[1].anyOf" && $0.status == .matched })
    let excluded = try await checker.assess(record("Books/Archive/a.md", "# Preview"), ruleNamed: "books")
    #expect(excluded.status == .notApplicable)
    let published = try await checker.assess(record("Books/Archive/a.md", "---\nstatus: published\n---\n# Book"), ruleNamed: "books")
    #expect(published.status == .passed)
  }

  @Test
  func `Outcome errors are order independent and negation never turns them into success`() async throws {
    let error = MarkdownRuleMatchExpression.leaf(.init(requirements: [.init(
      id: "modified", predicate: .modifiedAfter(try #require(MarkdownRuleDateTimeLiteral("2026-01-01"))))
    ]))
    let yes = MarkdownRuleMatchExpression.leaf(.init())
    let no = MarkdownRuleMatchExpression.not(yes)
    let cases: [(MarkdownRuleMatchExpression, MarkdownRuleAssessmentStatus)] = [
      (.anyOf([yes, error]), .passed), (.anyOf([error, yes]), .passed),
      (.allOf([no, error]), .notApplicable), (.allOf([error, no]), .notApplicable),
      (.not(error), .failed), (.oneOf([yes, error]), .failed),
      (.oneOf([yes, yes, error]), .notApplicable), (.oneOf([yes, no]), .passed),
      (.anyOf([no, error]), .failed), (.allOf([yes, error]), .failed)
    ]
    for (expression, expected) in cases {
      let registry = try MarkdownRuleCompiler(capabilities: [.modificationDate]).compile([
        .init(name: "rule", matchExpression: expression)
      ])
      let assessment = try await MarkdownRuleChecker(registry: registry).assess(MarkdownRecord(content: "# Book"), ruleNamed: "rule")
      #expect(assessment.status == expected)
      if expected == .passed || expected == .notApplicable {
        #expect(assessment.applicabilityDiagnostics.isEmpty)
      }
    }
  }

  @Test
  func `Path prefilter retains candidates selected through negated content predicates`() async throws {
    let expression = try decode("{\"not\":{\"allOf\":[{\"paths\":[\"Books/**\"]},{\"frontmatter\":{\"draft\":{\"equals\":true}}}]}}")
    let registry = try MarkdownRuleCompiler().compile([.init(name: "rule", matchExpression: expression)])
    let compiled = try #require(registry.rule(named: "rule"))
    let checker = MarkdownRuleChecker(registry: registry)
    for path in ["Books/a.md", "Notes/a.md"] {
      #expect(checker.isPathCandidate(try MarkdownRecordPath(path), for: compiled))
      #expect(try await checker.assess(record(path, "# Book"), ruleNamed: "rule").applicable)
    }
  }

  @Test
  func `Compiler validates unused branches and rejects empty groups and legacy encoding`() throws {
    let invalid = try decode("{\"anyOf\":[{}, {\"file\":{\"pathRegex\":\"[\"}}]}")
    for expression in [invalid, .anyOf([])] {
      #expect(throws: MarkdownRuleCompilationError.self) {
        try MarkdownRuleCompiler().compile([.init(name: "rule", matchExpression: expression)])
      }
    }
    for version in ["0.1.0", "0.2.0"] {
      #expect(throws: MarkdownRuleConfigurationError.self) {
        try MarkdownRuleConfigurationEncoder.encode(.init(configVersion: version, rules: [
          .init(name: "rule", matchExpression: .leaf(.init()))
        ]))
      }
    }
  }

  private func decode(_ json: String) throws -> MarkdownRuleMatchExpression {
    try .decode(JSONValue(any: JSONSerialization.jsonObject(with: Data(json.utf8))), source: "rules/test.mdrule.json")
  }

  @Test
  func `Thrown query errors participate in composition while legacy behavior is unchanged`() async throws {
    let query = MarkdownRuleApplicability(requirements: [.init(id: "query", predicate: .frontmatterJMESPath("ready"))])
    let expression = MarkdownRuleMatchExpression.anyOf([.leaf(query), .leaf(.init())])
    let compiler = MarkdownRuleCompiler(queryProvider: FailingQuery())
    let registry = try compiler.compile([.init(name: "grouped", matchExpression: expression), .init(name: "legacy", applicability: query)])
    let checker = MarkdownRuleChecker(registry: registry)
    let input = MarkdownRecord(content: "---\nready: true\n---\n# Book")
    let grouped = try await checker.assess(input, ruleNamed: "grouped")
    #expect(grouped.status == .passed)
    #expect(grouped.evidence.contains { $0.status == .unavailable })
    await #expect(throws: QueryFailure.self) { try await checker.assess(input, ruleNamed: "legacy") }
  }

  private enum QueryFailure: Error { case failed }
  private struct FailingQuery: MarkdownRuleQueryCapabilityProvider {
    var capabilities: Set<MarkdownRuleRuntimeCapability> { [.frontmatterJMESPath] }
    func validateJMESPath(_ expression: String) throws {}
    func evaluateJMESPath(_ expression: String, frontmatter: JSONValue) throws -> JSONValue? { throw QueryFailure.failed }
  }

  private func record(_ path: String, _ content: String) throws -> MarkdownRecord {
    MarkdownRecord(content: content, context: .init(path: try MarkdownRecordPath(path)))
  }
}
