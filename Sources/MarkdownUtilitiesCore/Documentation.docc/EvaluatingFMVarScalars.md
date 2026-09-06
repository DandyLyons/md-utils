# Evaluating fm-var Scalar Caches

Resolve scalar references atomically while preserving the source snapshot's unrelated bytes.

## Evaluate an element

``FMVarScalarEvaluator`` consumes the lossless parser output and the host's
``FMVarSourceResolution``. The host resolves and projects the source before calling Core;
Core never reads files or fetches resources. Use `FMVarSourceResolver` from
`MarkdownUtilities` for that host step, including source authorization.

```swift
let snapshot = try FMVarParser().parse(markdown)
let evaluator = FMVarScalarEvaluator()
let result = evaluator.evaluate(
  snapshot,
  elementOrdinal: 0,
  sourceResolution: resolvedSource
)
if let edit = result.edit {
  let preview = try snapshot.replacingCache(
    ofElementOrdinal: edit.elementOrdinal,
    with: edit.replacement
  )
  // The host owns revision checking and any explicit filesystem write.
}
```

The source resolution must belong to the requested element. Tests and other query providers can
also inject `queryEvaluation`, which must correspond to the decoded declaration and source.
Injected query results cannot bypass syntax or source failures. Query attribute entities are
already decoded by the parser; the evaluator does not decode them a second time.

## First-node selection and split fallbacks

An empty nodelist uses only `default-zero`. A null first node uses only `default-null`.
Absent applicable fallbacks produce distinct unresolved statuses and no edit. Fallbacks are
literal presentation: they bypass coercion and formatting, but still undergo security checks
and escaping. For example:

```html
<fm-var query="$.title" default-zero="Missing" default-null="Unset">old</fm-var>
```

An empty authoritative string replaces `old` with an empty cache. Numeric `0` and Boolean
`false` are ordinary values; `type="boolean"` renders `false` as `FALSE` by default.

For multiple selected nodes, only the first is coerced and formatted. The complete nodelist,
including duplicates and source associations, remains in the result. Later nodes cannot cause
a scalar shape or coercion failure. The evaluator warns about ignored nodes without sorting.

`queryEvaluation.mayEnumerateObjectMembers` conservatively flags wildcard, filter, or descendant
queries when the argument contains an object. This can warn even if that particular object is
not visited. It is not a claim that output changed or that array order is unstable. `nil` means
an injected provider did not assess ordering. When multiple results may involve object-member
enumeration, the first value can depend on the implementation's enumeration order.

## Formatting and atomic failures

``FMVarDefaultScalarFormatter`` uses the existing coercer's specification defaults: strings retain
content, Booleans use `TRUE`/`FALSE`, integers use decimal notation, numbers preserve decimal
spelling, and temporal types retain the default ISO-style representation.

Explicit `format` overrides report `fm-var.format.unsupported` unless a host injects an
``FMVarScalarFormatter`` that handles them. A locale alone does not change default serialization.
Document-wide `<fm-format>` cascade and locale formatting are deferred. Formatter implementations
return plain text or a ``FMVarScalarFormattingFailure``; they cannot bypass mandatory escaping.

Parsing, source access, projection, query syntax/capability/resource, shape, coercion, format,
and security failures preserve the complete cache. Source and query failure details remain in
the result, and stable diagnostics distinguish the failure stage. Invalid provider inputs fail
with `fm-var.evaluation.invalid-input`. Errors in a different reference do not block a valid
reference's proposed edit.

## Literal serialization and freshness

``FMVarLiteralCacheSerializer`` escapes `&`, `<`, and `>` as named references, and backslash,
backtick, `*`, `_`, `~`, `[`, `]`, and `|` as decimal numeric references. It processes input once,
so literal `&lt;` becomes `&amp;lt;`; value text never becomes markup or a nested reference.
For example, `</fm-var>*text*` becomes `&lt;/fm-var&gt;&#42;text&#42;`.

Embedded CR/LF and XML 1.0-forbidden characters fail without an edit. Tabs and other supported
Unicode are preserved. The same checks apply to fallbacks and injected formatter output.

`cachedText` is raw source text, while `expectedCache` is canonical escaped text. Freshness uses
UTF-8 byte equality, including entity spelling and Unicode normalization differences. Successful
resolved values report `valid` or `stale`; fallback statuses remain zero/null-specific, with
`isFresh` reporting freshness independently. Failures have no expected cache, freshness, or edit.

Only stale successful results propose an ``FMVarTextEdit`` over the parsed child range. Opening
and closing tags, attributes, surrounding whitespace, frontmatter, and LF/CRLF bytes remain
untouched. Apply edits only against their original snapshot; hosts must check source revisions
before writing and account for offset changes when applying multiple edits.

## Topics

### Evaluation

- ``FMVarScalarEvaluator``
- ``FMVarScalarEvaluation``

### Formatting Extension

- ``FMVarScalarFormatter``
- ``FMVarDefaultScalarFormatter``
- ``FMVarScalarFormattingFailure``

### Literal Cache Text

- ``FMVarLiteralCacheSerializer``
- ``FMVarLiteralCacheError``
