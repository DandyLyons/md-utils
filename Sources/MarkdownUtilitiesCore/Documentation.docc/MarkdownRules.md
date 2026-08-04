# Markdown Rules

Apply reusable policies with one normalized, compiled rule model.

## Overview

A Markdown type asks whether a record conforms to a named structural contract. A rule first selects records through ``MarkdownRuleApplicability`` and then evaluates its ``MarkdownRuleCheck`` values. Applicability, successful policy validation, and unavailable runtime context remain distinct outcomes in ``MarkdownRuleAssessmentStatus``.

``MarkdownRuleDefinition`` is the sole executable rule definition. Decode configurations into definitions, compile all definitions before processing records, and give the resulting ``MarkdownRuleRegistry`` to ``MarkdownRuleChecker``. This prevents configuration validation and runtime evaluation from drifting between hosts.

```swift
let definition = MarkdownRuleDefinition(
  name: "published-books",
  applicability: MarkdownRuleApplicability(
    paths: ["books/**/*.md"],
    excludePaths: ["books/drafts/**"],
    requirements: [
      MarkdownRuleRequirement(
        id: "published",
        predicate: .frontmatterField(
          key: "published",
          operation: .equals(.boolean(true))
        )
      )
    ]
  ),
  checks: [
    MarkdownRuleCheck(
      id: "summary",
      predicate: .markdown(.heading(MarkdownHeadingPredicate(text: "Summary")))
    )
  ]
)

let registry = try MarkdownRuleCompiler().compile([definition])
let assessment = try await MarkdownRuleChecker(registry: registry).assess(
  record,
  ruleNamed: "published-books"
)
```

Includes use any-of semantics, exclusions take precedence, and applicability requirements use all-of semantics. ``MarkdownRulePredicateEvidence`` retains their deterministic evaluation order for explanation output.

## Topics

### Lifecycle

- <doc:CompilingMarkdownRules>
- <doc:RuleRuntimeCapabilities>
- <doc:RuleConfigurationVersions>

### Definitions and results

- ``MarkdownRuleDefinition``
- ``MarkdownRuleApplicability``
- ``MarkdownRulePredicate``
- ``MarkdownRuleCheck``
- ``MarkdownRuleAssessment``
- ``MarkdownRuleAssessmentStatus``
