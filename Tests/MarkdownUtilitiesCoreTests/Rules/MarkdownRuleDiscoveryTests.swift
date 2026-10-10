import Testing
@testable import MarkdownUtilitiesCore

struct MarkdownRuleDiscoveryTests {
  @Test(arguments: [
    (["PROBLEMS/**/*.md"], ["PROBLEMS/"]),
    (["books/*/notes/*.md", "articles/**/*.md"], ["articles/", "books/"]),
    (["books/deep/*.md", "books/**/*.md"], ["books/"]),
    (["books/one.md"], ["books/"]),
    (["**/*.md"], [""]),
    (["book?/*.md"], [""]),
    (["books/*.md", "*.md"], [""]),
    ([".hidden/*.md"], [""]),
    (["../outside/*.md"], [""]),
    ([String](), [""]),
  ])
  func `positive path prefixes narrow conservatively`(value: ([String], [String])) throws {
    let definition = MarkdownRuleDefinition(name: "rule", applicability: MarkdownRuleApplicability(paths: value.0))
    let registry = try MarkdownRuleCompiler().compile([definition])
    let rule = try #require(registry.rule(named: "rule"))
    #expect(MarkdownRuleChecker(registry: registry).discoveryDirectories(for: rule) == value.1)
  }

  @Test func `simple match leaves narrow but recursive expressions retain complete discovery`() throws {
    let leaf = MarkdownRuleMatchExpression.leaf(MarkdownRuleApplicability(paths: ["notes/**"]))
    let definitions = [
      MarkdownRuleDefinition(name: "leaf", matchExpression: leaf),
      MarkdownRuleDefinition(name: "group", matchExpression: .not(leaf)),
    ]
    let registry = try MarkdownRuleCompiler().compile(definitions)
    let checker = MarkdownRuleChecker(registry: registry)
    #expect(checker.discoveryDirectories(for: try #require(registry.rule(named: "leaf"))) == ["notes/"])
    #expect(checker.discoveryDirectories(for: try #require(registry.rule(named: "group"))) == [""])
  }
}
