---
title: fm-var Markdown synchronization fixtures
description: Index and usage conventions for before-and-after Markdown fixtures covering
  the fm-var specification from https://github.com/DandyLyons/fm-var-tag in `/fixtures/`.
---

# Markdown synchronization fixtures

These language-neutral fixtures illustrate RFC 001 Rev 3 in [PROPOSAL.md](../PROPOSAL.md). They are hand-authored expected results, not output from a reference implementation or an exhaustive conformance suite.

Each directory contains:

- `before.md`: a complete Markdown document with authoritative YAML and existing caches.
- `after.md`: the document after one synchronization pass.
- `README.md`: operation, expected outcomes in document order, relevant specification sections, and any host assumptions.
- `sources/`, where needed: immutable supporting resources.

The operation synchronizes all reference elements in `before.md`; `after.md` is the expected output of that operation, not a change to the authoritative data. Error cases intentionally retain their caches. Fallback statuses are distinct from successful value resolution. Diagnostic wording and process exit codes are host-defined.

For these examples, preserve frontmatter, attributes, configuration declarations, unrelated Markdown, and spacing outside cache bodies. Files are UTF-8 with LF line endings and a trailing newline. The particular entity spelling and HTML list indentation shown are fixture serialization conventions; equivalent safe encodings are not necessarily specification violations. These fixtures do not prescribe an implementation API or a command-line interface.

Cases 06 and 07 contain illustrative localized output. They require comparison with the effective formatter, or a pinned runtime and locale-data version before using byte snapshots. Other cases avoid locale-dependent presentation and unspecified object-member traversal order. Source access is local to each case unless its README states an explicit denial policy. No remote resources need to be fetched.

| Case                                                           | Scenario                                   |
| -------------------------------------------------------------- | ------------------------------------------ |
| [01-inline-contexts](01-inline-contexts/README.md)             | Inline Markdown contexts                   |
| [02-scalar-types](02-scalar-types/README.md)                   | Scalar types and source spelling           |
| [03-scalar-fallbacks](03-scalar-fallbacks/README.md)           | Missing, null, and falsy scalars           |
| [04-block-lists](04-block-lists/README.md)                     | Ordered and unordered lists                |
| [05-list-fallbacks](05-list-fallbacks/README.md)               | List empty states                          |
| [06-inline-lists](06-inline-lists/README.md)                   | Localized inline lists                     |
| [07-format-precedence](07-format-precedence/README.md)         | Document, scoped, and local formatting     |
| [08-literal-escaping](08-literal-escaping/README.md)           | Literal text and markup injection          |
| [09-list-escaping](09-list-escaping/README.md)                 | Block list member escaping                 |
| [10-jsonpath-selection](10-jsonpath-selection/README.md)       | JSONPath selection and attribute decoding  |
| [11-relative-sources](11-relative-sources/README.md)           | Relative Markdown and YAML sources         |
| [12-partial-failure](12-partial-failure/README.md)             | Per-element atomic failure                 |
| [13-list-shape-errors](13-list-shape-errors/README.md)         | Unsupported list shapes                    |
| [14-unresolved-values](14-unresolved-values/README.md)         | Missing and null without fallback          |
| [15-query-errors](15-query-errors/README.md)                   | Malformed query versus structural mismatch |
| [16-source-access-error](16-source-access-error/README.md)     | Host-denied source                         |
| [17-duplicate-keys](17-duplicate-keys/README.md)               | Duplicate YAML keys                        |
| [18-nonfinite-number](18-nonfinite-number/README.md)           | Non-finite YAML number                     |
| [19-nonstring-key](19-nonstring-key/README.md)                 | Non-string YAML key                        |
| [20-cyclic-alias](20-cyclic-alias/README.md)                   | Cyclic YAML alias                          |
| [21-aliases-and-merge-key](21-aliases-and-merge-key/README.md) | Expanded aliases and literal merge key     |
| [22-value-error](22-value-error/README.md)                     | Embedded line break                        |
| [23-idempotent-sync](23-idempotent-sync/README.md)             | Already synchronized document              |
