# Markdown Rules

Apply reusable policies while keeping applicability separate from validation.

## Types and Rules

A type asks whether a record conforms to a named structural contract. A rule first asks whether a policy applies and then evaluates its checks. Matching a rule is not the same as passing it.

`MarkdownRuleDefinition` and `MarkdownTypeDefinition` remain separate public models. They share record analysis, normalized Markdown predicates, diagnostics, and type assessment without giving them the same semantics.

## Portable Rule Assessment

`MarkdownRuleApplicability` can select records with body or context predicates and can require conformance to any or all named Markdown types. Supply a `MarkdownTypeRegistry` to `MarkdownRuleChecker` when applicability references types.

```swift
let rule = MarkdownRuleDefinition(
  name: "published-books",
  applicability: MarkdownRuleApplicability(
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
