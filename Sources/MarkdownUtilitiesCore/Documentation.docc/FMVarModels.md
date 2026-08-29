# Modeling Frontmatter References

Represent `<fm-var>`, `<fm-list>`, and `<fm-format>` source without performing host I/O.

## Overview

The fm-var models are the portable vocabulary for RFC 001 Rev 2. They describe lossless source
syntax, normalized reference and formatting declarations, effective formatting provenance,
structured diagnostics, statuses, and proposed child-text replacements. They do not scan source,
resolve URI references or key paths, coerce or format values, escape cached text, or apply edits.

YAML frontmatter is authoritative under the v1 specification. TOML frontmatter support in other
parts of `MarkdownUtilitiesCore` does not extend the fm-var source model.

## Source Coordinates

``FMVarSourcePosition`` records a zero-based UTF-8 byte offset together with one-based line and
column values. Columns also count UTF-8 bytes, giving every byte offset one deterministic,
language-neutral coordinate. LF starts the next line; in CRLF input, CR remains on the preceding
line and the position after LF is column one of the next line.

``FMVarSourceRange`` is half-open. Its end position may equal the source snapshot's end-of-file
offset. ``FMVarSourceMap`` translates positions in both directions and rejects coordinates outside
the immutable source snapshot against which it was initialized.

Reference edits use ``FMVarTextEdit`` to replace only an element's cache range. Native host layers
remain responsible for checking the source revision and applying edits atomically.

## Structured Results

``FMVarReferenceStatus`` distinguishes valid, stale, fallback, unresolved, invalid, denied, and
unsupported results. ``FMVarDiagnosticCode`` is an extensible raw-value type; stable codes use the
`fm-var.` namespace while human-readable ``FMVarDiagnostic/message`` text may change.

Models use explicit kebab-case JSON keys and values. Diagnostics and edits implement deterministic
ordering for structured reports. Raw attributes remain in authored order and retain their exact
text and quote delimiter separately from normalized declarations.

## Conformance Fixtures

The language-neutral corpus is bundled at
`Tests/MarkdownUtilitiesCoreTests/Fixtures/FMVar/`. `schema.json` defines the manifest and expected
result contract. `manifest.json` records each case and pins its provenance to:

- Repository: `DandyLyons/fm-var-tag`
- Document: `PROPOSAL.md`
- Proposal commit: `e235f05f19c0c62cf288910bf6fe9952e3b5d18c`
- Proposal blob: `44fc7af58564eeaf94452644930c4fc01328aa7d`

The initial corpus is maintained in `md-utils` because the specification repository has no
conformance directory yet. Accepted portable cases may later be copied upstream. A downstream
synchronization must preserve accepted case bytes and update both provenance identifiers whenever
the authoritative proposal or upstream fixtures change.
