# Markdown Types

Assess complete Markdown records against reusable structural contracts.

## Records and Conformance

A `MarkdownRecord` contains canonical Markdown text and optional identity, revision, and external context. A `MarkdownDocument` is the parsed content view produced from valid text. Type assessment accepts the record so invalid YAML can be returned as a structured diagnostic instead of preventing the resource from being represented.

Conformance is structural and non-exclusive. One record can conform to `Book`, `Document`, and `Publishable` at the same time. Requirements produce errors and affect conformance. Recommendations produce advisories without making the record fail.

Types have three domains:

- `frontmatter` validates schema-visible YAML values against every listed JSON Schema;
- `body` evaluates Markdown AST predicates such as headings, hierarchy, and sections; and
- `context` evaluates external facts such as a normalized logical path.

`$md-utils` frontmatter is reserved for system metadata and is excluded from schema-visible user frontmatter.

## Define and Assess a Type

Type definitions use the same model whether decoded from YAML or JSON. Filesystem-backed definitions use the compound extensions `.mdtype.yaml`, `.mdtype.yml`, or `.mdtype.json`. A type contract version is an opaque nonempty string; Semantic Versioning is recommended but not enforced.

```swift
let definition = MarkdownTypeDefinition(
  name: MarkdownTypeName(rawValue: "Book"),
  version: "1.0.0",
  body: MarkdownConstraintGroup(requirements: [
    MarkdownConstraint(
      id: "book-heading",
      predicate: .heading(MarkdownHeadingPredicate(text: "Book", level: 1))
    )
  ]),
  context: MarkdownConstraintGroup(requirements: [
    MarkdownConstraint(
      id: "book-path",
      predicate: .path(MarkdownPathPredicate(glob: "books/**/*.md"))
    )
  ])
)

let registry = try MarkdownTypeRegistry(definitions: [definition])
let checker = MarkdownTypeChecker(registry: registry)
let record = MarkdownRecord(
  content: "# Book\n",
  context: MarkdownRecordContext(
    path: try MarkdownRecordPath("books/dune.md")
  )
)
let assessment = try await checker.assess(record, as: "Book")
```

The registry validates definitions and resolves schema resources before assessment. Multiple frontmatter schemas have `allOf` semantics. A nonempty schema list implies required frontmatter unless `presence: optional` is explicit. External resources are supplied through `MarkdownSchemaResourceProvider`; pure assessment never opens a file or fetches a URL.

## Type Hints

A record can claim likely types in reserved frontmatter:

```yaml
---
$md-utils:
  typeHints:
    - Book
    - name: Publishable
      version: "1.0.0"
title: Dune
---
```

Hints are optimizations and diagnostics, not proof. `verifyTypeHints(in:)` assesses each claim and reports it as confirmed, rejected, unknown, or unavailable at the requested version. Hosts can also provide hints through `MarkdownRecordContext` when the canonical text is stored elsewhere.

## Diagnostics and Fix-Its

`MarkdownTypeAssessment` contains errors and advisories with stable codes, constraint identifiers, locations, and structured `MarkdownFixIt` values. Automatic edits use known values such as JSON Schema `const`. Unknown values require explicit input. A schema `default` is only a suggestion and is never classified as automatic.

Use `MarkdownTypeFixer.apply(_:to:inputs:)` to apply selected edits to an in-memory record. This does not write to a filesystem. Reassess the returned record to determine its final conformance.
