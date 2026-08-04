# Compiling Markdown Rules

Validate every definition and resolve its dependencies before processing records.

## Compilation Flow

``MarkdownRuleCompiler`` accepts normalized ``MarkdownRuleDefinition`` values and produces an immutable ``MarkdownRuleRegistry``. Compilation validates rule names, stable identifiers, regular expressions, count and date operands, Markdown type references, JSON Schema resources, and runtime capabilities.

Compilation is all-or-nothing. ``MarkdownRuleCompilationError`` contains deterministically ordered ``MarkdownRuleCompilationDiagnostic`` values, allowing CLIs and servers to report all discoverable startup problems without evaluating a record.

```swift
let compiler = MarkdownRuleCompiler(
  capabilities: [.modificationDate],
  typeRegistry: typeRegistry,
  schemaProvider: schemaProvider
)
let registry = try compiler.compile(definitions)
let checker = MarkdownRuleChecker(registry: registry)
```

Compile once per configuration generation and share that registry with every consumer. Do not execute raw definitions or resolve schemas while traversing records.

Compiled rules also retain the derived record analysis they require. Hosts can reject include/exclude path mismatches before reading content, then combine the requirements of the remaining candidate rules. Frontmatter-only rules do not build a Markdown syntax tree; heading and section predicates request that structural analysis explicitly.

## Assessment

Select a rule by name with ``MarkdownRuleChecker/assess(_:ruleNamed:)``. A result is `notApplicable` when selection predicates do not match, `skipped` when every optional check lacks input, `passed` when no required check fails, and `failed` when checks fail or required runtime context is unavailable. The `applicable` and `passes` properties are computed compatibility views of that explicit status.
