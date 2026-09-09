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

## Enforcing a Markdown type

Programmatic rules can use `.typeConformance(MarkdownTypeName(rawValue: "Book"))`
as a check predicate. Supply the corresponding type registry to `MarkdownRuleCompiler`.
Unknown types fail compilation. A selected nonconforming record fails the rule;
it does not become inapplicable. Assessment reuses analyzed content and retains the
type's requirements, advisories, diagnostic identifiers, and fix-its. The enclosing
check's severity does not override type-contract severities.

`MarkdownRuleAssessment.typeAssessments` associates each original type assessment
with its rule check ID, while `diagnostics` also exposes the diagnostics for existing
consumers. This foundation is a Core API capability: legacy 0.1.0 and 0.2.0 config
formats do not encode type-conformance checks. Config 0.3.0 serialization and recursive
type expressions are separate work described in RFC 0002.

## Recursive selection

`MarkdownRuleMatchExpression` parses and evaluates the RFC 0002 `allOf`, `anyOf`,
`oneOf`, and `not` matcher vocabulary. Obtain it with `MarkdownRuleFile.decodedMatch()`
and set `MarkdownRuleDefinition.matchExpression` when compiling programmatic rules.
Use an expression or flat `applicability`, not both. Empty objects select all host
candidates; multiple fields in a leaf remain conjunctive. Legacy versioned decoders
continue rejecting grouped syntax and preserve their historical semantics.

Compilation checks all branches, including regular expressions, referenced types,
and runtime capabilities. Evaluation retains nested evidence paths for explanation.
`anyOf` succeeds when any branch succeeds; `allOf` fails when any branch fails;
`oneOf` fails when two branches succeed. Otherwise an evaluation error prevents a
definitive result. `not` preserves errors. Errors in irrelevant branches remain
explanation evidence without failing a decisive result; cancellation propagates.

Path prefiltering is conservative under alternatives and negation. The compiler
collects body-analysis requirements across every leaf so grouping cannot suppress
required AST analysis.

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
