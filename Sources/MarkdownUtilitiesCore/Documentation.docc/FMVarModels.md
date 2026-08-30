# Modeling Frontmatter References

Represent `<fm-var>`, `<fm-list>`, and `<fm-format>` source without performing host I/O.

## Overview

The fm-var models are the portable vocabulary for RFC 001 Rev 3. They describe lossless source
syntax, normalized reference and formatting declarations, effective formatting provenance,
structured diagnostics, query arguments and nodelists, statuses, result metadata, and proposed
child-text replacements. Use ``FMVarParser`` to scan source and <doc:ParsingFMVarElements> for its
placement and recovery rules. The feature does not load URI references, project YAML, evaluate
JSONPath, coerce or format values, or escape cached text at this stage.

YAML frontmatter is authoritative under the v1 specification. TOML frontmatter support in other
parts of `MarkdownUtilitiesCore` does not extend the fm-var source model.

Use ``FMVarElement`` and ``FMVarRawAttribute`` for lossless scanner output. After syntax validation,
represent normalized attributes with ``FMVarScalarDeclaration``, ``FMVarListDeclaration``, or
``FMVarFormatDeclaration``. ``FMVarEffectiveConfiguration`` records both the flattened formatting
values and the precedence layer that supplied each populated option.

``FMVarQueryArgument`` represents the validated I-JSON-compatible projection consumed by a later
RFC 9535 evaluator. Each ``FMVarQueryNode`` retains an opaque identity and optional
``FMVarSourceScalar`` so selected values can recover original YAML scalar spelling. Objects retain
ordered ``FMVarQueryObjectMember`` values for source association, but that order does not create a
portable JSONPath ordering guarantee. ``FMVarNodelist`` preserves evaluator order and duplicate
nodes exactly.

## Source Coordinates

``FMVarSourcePosition`` records a zero-based UTF-8 byte offset together with one-based line and
column values. Columns also count UTF-8 bytes, giving every byte offset one deterministic,
language-neutral coordinate. LF starts the next line; in CRLF input, CR remains on the preceding
line and the position after LF is column one of the next line.

``FMVarSourceRange`` is half-open. Its end position may equal the source snapshot's end-of-file
offset. ``FMVarSourceMap`` translates positions in both directions and rejects coordinates outside
the immutable source snapshot against which it was initialized.

```swift
let source = "é\r\n<fm-var query=\"$.title\">Old</fm-var>"
let sourceMap = FMVarSourceMap(source: source)
let cacheRange = try sourceMap.range(fromUTF8Offset: 28, toUTF8Offset: 31)

cacheRange.start.line    // 2
cacheRange.start.column  // 25
```

Reference edits use ``FMVarTextEdit`` to replace only an element's cache range. Native host layers
remain responsible for checking the source revision and applying edits atomically.

``FMVarParseResult/replacingCache(ofElementOrdinal:with:)`` provides an in-memory cache-only
replacement for preview and preservation checks. It never writes a file.

## Structured Results

``FMVarReferenceStatus`` distinguishes zero-result and null-result fallback/unresolved outcomes,
query-argument, query validity, capability, and resource failures, wrong shapes, and the existing
cache/source outcomes. ``FMVarReferenceResultMetadata`` separately records query-argument status,
evaluation status, selected nodelist count/cardinality, and selected value shape.
``FMVarDiagnosticCode`` is an extensible raw-value type; stable codes use the `fm-var.` namespace
while human-readable ``FMVarDiagnostic/message`` text may change.

Models use explicit kebab-case JSON keys and values. Diagnostics and edits implement deterministic
ordering for structured reports. Raw attributes remain in authored order and retain their exact
text and quote delimiter separately from normalized declarations.

## Conformance Fixtures

The language-neutral corpus is bundled at
`Tests/MarkdownUtilitiesCoreTests/Fixtures/FMVar/`. `schema.json` defines the manifest and expected
result contract. `manifest.json` records each case and pins its provenance to:

- Repository: `DandyLyons/fm-var-tag`
- Document: `PROPOSAL.md`
- Proposal commit: `18604853843d6edf22aba927c98697f5c956a0f3`
- Proposal blob: `c612cb01262ac527236dd6dc60b9db5fb46622f5`

`parser-cases.json` adds language-neutral syntax, placement, exclusion-context, recovery, Unicode,
and CRLF cases for ``FMVarParser``.

The initial corpus is maintained in `md-utils` because the specification repository has no
conformance directory yet. Accepted portable cases may later be copied upstream. A downstream
synchronization must preserve accepted case bytes and update both provenance identifiers whenever
the authoritative proposal or upstream fixtures change.
