# Markdown Rules

Apply reusable policies while keeping applicability separate from validation.

## Types and Rules

A type asks whether a record conforms to a named structural contract. A rule first asks whether a policy applies and then evaluates its checks. Matching a rule is not the same as passing it.

`MarkdownRuleDefinition` and `MarkdownTypeDefinition` remain separate public models. They share record analysis, normalized Markdown predicates, diagnostics, and type assessment without giving them the same semantics.

## Portable Rule Assessment

`MarkdownRuleApplicability` can narrow records by logical-path globs, select records with body or context predicates, and require conformance to any or all named Markdown types. Supply a `MarkdownTypeRegistry` to `MarkdownRuleChecker` when applicability references types.

Path includes and exclusions intentionally match the `paths` and `excludePaths` fields in the md-utils rules configuration. Includes use any-of semantics. An empty `paths` array imposes no inclusion restriction, while a nonempty array requires a logical path matching at least one glob. Exclusions use none-of semantics and take precedence over includes. A pathless record therefore cannot match a nonempty include list, but it remains eligible for an exclusion-only rule.

Path filtering is conjunctive with `predicates`, `anyTypes`, and `allTypes`. Hosts such as ``MarkdownRuleChecker`` and the server read-snapshot builder can apply the explicit path filters before parsing YAML or Markdown. A path predicate in `predicates` remains a required portable constraint and must also pass.

```swift
let rule = MarkdownRuleDefinition(
  name: "published-books",
  applicability: MarkdownRuleApplicability(
    paths: ["books/**/*.md"],
    excludePaths: ["books/drafts/**"],
    allTypes: [MarkdownTypeName(rawValue: "Book")]
  ),
  requirements: MarkdownConstraintGroup(requirements: [
    MarkdownConstraint(
      id: "reviews",
      predicate: .section(MarkdownSectionPredicate(
        heading: MarkdownHeadingPredicate(text: "Reviews")
      ))
    )
  ])
)

let checker = MarkdownRuleChecker(typeRegistry: registry)
let result = try await checker.assess(record, against: rule)
```

Portable APIs do not scan directories, load configuration, or print terminal output. Native and command-line adapters supply records and present `MarkdownRuleAssessment` results.
