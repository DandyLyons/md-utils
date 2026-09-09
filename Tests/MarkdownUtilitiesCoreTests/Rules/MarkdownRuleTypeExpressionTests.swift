import Testing
@testable import MarkdownUtilitiesCore

@Suite("Recursive rule type enforcement")
struct MarkdownRuleTypeExpressionTests {
  @Test
  func `Composition preserves outcomes and negative branch evidence`() async throws {
    let types = try MarkdownTypeRegistry(definitions: [
      .init(name: .init(rawValue: "Pass"), version: "1"),
      .init(name: .init(rawValue: "Fail"), version: "1", frontmatter: .init(presence: .required)),
      .init(name: .init(rawValue: "Error"), version: "1", context: .init(requirements: [
        .init(id: "path", predicate: .path(.init(glob: "Books/**"))),
      ])),
    ])
    let pass = MarkdownRuleTypeExpression.reference("pass.mdtype.json")
    let fail = MarkdownRuleTypeExpression.reference("fail.mdtype.json")
    let error = MarkdownRuleTypeExpression.reference("error.mdtype.json")
    let cases: [(MarkdownRuleTypeExpression, MarkdownRuleAssessmentStatus)] = [
      (.allOf([pass, fail]), .failed), (.anyOf([pass, fail]), .passed),
      (.oneOf([pass, fail]), .passed), (.oneOf([pass, .not(fail)]), .failed),
      (.not(fail), .passed), (.not(pass), .failed),
      (.allOf([pass, .anyOf([fail, .not(fail)])]), .passed),
      (.anyOf([pass, error]), .passed), (.allOf([fail, error]), .failed),
      (.oneOf([pass, error]), .failed), (.oneOf([pass, .not(fail), error]), .failed),
      (.not(error), .failed),
    ]
    for (expression, expected) in cases {
      let definition = MarkdownRuleDefinition(name: "policy", typeExpression: expression,
        typeBindings: ["pass.mdtype.json": .init(rawValue: "Pass"), "fail.mdtype.json": .init(rawValue: "Fail"), "error.mdtype.json": .init(rawValue: "Error")])
      let checker = MarkdownRuleChecker(registry: try MarkdownRuleCompiler(typeRegistry: types).compile([definition]))
      let result = try await checker.assess(.init(content: "# Document"), ruleNamed: "policy")
      #expect(result.status == expected)
      #expect(result.typeExpressionAssessment != nil)
      if expected == .passed { #expect(result.diagnostics.contains { $0.severity == .error } == false) }
      let malformed = try await checker.assess(.init(content: "---\n$md-utils:\n  typeHints: invalid\n---\n"), ruleNamed: "policy")
      #expect(malformed.status == .failed)
      #expect(malformed.typeExpressionAssessment?.status == .unavailable)
    }
  }

  @Test
  func `Unused type branches and malformed programmatic expressions fail compilation`() throws {
    let types = try MarkdownTypeRegistry(definitions: [.init(name: .init(rawValue: "Pass"), version: "1")])
    for expression in [MarkdownRuleTypeExpression.anyOf([.reference("pass.mdtype.json"), .reference("missing.mdtype.json")]), .allOf([])] {
      #expect(throws: MarkdownRuleCompilationError.self) {
        try MarkdownRuleCompiler(typeRegistry: types).compile([
          .init(name: "policy", source: "rules/policy.mdrule.json", typeExpression: expression,
            typeBindings: ["pass.mdtype.json": .init(rawValue: "Pass")]),
        ])
      }
    }
  }
}
