# Resolving fm-var Sources

Resolve an RFC 3986 resource identifier, obtain one immutable byte snapshot, and project YAML into
an ``FMVarQueryArgument``.

## Overview

Source processing is deliberately split at a host boundary. ``FMVarURIResolver`` performs portable
RFC 3986 parsing and Section 5.2 resolution. A host supplies the containing document as an
``FMVarResource`` and implements ``FMVarResourceProvider`` to authorize and load other resolved
identifiers. `FMVarSourceResolver` in the `MarkdownUtilities` target coordinates those pieces;
it does not access a filesystem or network itself.

The containing resource identifier must be absolute and fragment-free. An omitted `src` means the
containing document. An empty `src` is the RFC 3986 empty reference and also resolves to the
containing identifier. The literal `self` is an ordinary relative path. Whenever the resolved
identifier equals the containing identifier, resolution reuses the authoritative containing
snapshot and does not call the provider. Every other identifier produces exactly one provider
request.

Resolution stops after one resource is decoded and projected. It does not follow or evaluate
fm-var elements found in the selected resource, synchronize documents, perform JSONPath evaluation,
or mutate a cache.

## Choose the Resource Representation

An explicit recognized media type is authoritative, after removing parameters and comparing
case-insensitively. A missing, blank, or generic media type falls back to the case-insensitive URI
path extension. The query component does not participate in extension recognition.

| Metadata | Selected representation |
| --- | --- |
| `text/markdown` | Markdown |
| `application/yaml`, `text/yaml`, `application/x-yaml`, `text/x-yaml` | YAML |
| Missing, blank, `application/octet-stream`, or `text/plain` | `.md`/`.markdown` or `.yaml`/`.yml` extension |
| Any other explicit type | Unsupported |

Resource bytes must be strict UTF-8. One leading UTF-8 BOM is accepted. A Markdown resource must
start with the package's LF-only `---` YAML frontmatter envelope. TOML, missing or incomplete
frontmatter, and a non-mapping frontmatter root are rejected. Empty YAML frontmatter represents an
empty mapping. Standalone YAML accepts a scalar, sequence, mapping, or null root, but not an empty
or multi-document stream.

## Project YAML with Yams

``FMVarYAMLProjector`` keeps Yams as the only YAML syntax parser and representation composer. It
starts from Yams' basic resolver, adds the YAML 1.2.2 Core Schema resolution expressions, calls
`Yams.compose`, then walks the resulting node graph. This package does not implement a YAML lexer,
parser, block-scalar decoder, quote decoder, alias expander, or merge engine.

The Core resolver recognizes `true` and `false` spellings, Core nulls, decimal integers, `0o`
octal, `0x` hexadecimal, and Core floats. Timestamps, `yes`/`no`, `on`/`off`, sexagesimal values,
and `<<` remain strings. A leading-zero decimal such as `012` is decimal 12, not YAML 1.1 octal.

| YAML node | Portable query value | Additional constraint |
| --- | --- | --- |
| Mapping | Object | Keys are unique strings |
| Sequence | Array | Order is retained |
| String | String | Core string tag only |
| Null | Null | Core null spelling |
| Boolean | Boolean | Core Boolean spelling |
| Integer | Integer | Inclusive range `-9007199254740991...9007199254740991` |
| Float | Number | Finite IEEE 754 binary64 without overflow |

All other tags are rejected. Yams expands valid acyclic aliases while composing. Yams failures for
undefined, forward, self-referential, or cyclic aliases become structured invalid-alias failures.

Every projected node receives a deterministic JSON-location identity such as `$['items'][0]`.
Scalar nodes also retain Yams' `Node.Scalar.string` as ``FMVarSourceScalar/content``. Numeric content
therefore keeps spelling such as `1.2300` or `1e+03`; this association is decoded scalar content,
not a reconstruction of the complete YAML token including quote style or comments.

## Handle Failures

``FMVarSourceFailure`` records the resolved identifier when one exists and nests an
``FMVarQueryArgumentFailure`` for YAML failures. A YAML failure includes a deterministic node
location when available and Yams' one-based line and Unicode-scalar column when available.
Consumers should branch on ``FMVarDiagnosticCode`` rather than human-readable messages.

Source codes include `fm-var.source.invalid-base-uri`, `fm-var.source.invalid-reference`,
`fm-var.source.access-denied`, `fm-var.source.unsupported`, `fm-var.source.unreadable`,
`fm-var.source.unsupported-kind`, `fm-var.source.missing-frontmatter`,
`fm-var.source.unsupported-frontmatter-format`, and `fm-var.source.malformed-frontmatter`.

Query-argument codes include `fm-var.query-argument.malformed-yaml`,
`fm-var.query-argument.empty-document`, `fm-var.query-argument.duplicate-key`,
`fm-var.query-argument.non-string-key`, `fm-var.query-argument.invalid-alias`,
`fm-var.query-argument.unsupported-tag`, `fm-var.query-argument.invalid-scalar`,
`fm-var.query-argument.non-finite-float`, `fm-var.query-argument.integer-out-of-range`,
`fm-var.query-argument.float-overflow`, and `fm-var.query-argument.invalid-frontmatter-root`.

Authorization remains a host responsibility. The native `MarkdownUtilities` target supplies an
explicit local-only `FMVarHostPolicy` and `FileFMVarResourceProvider`; other hosts can implement the
provider protocol with different policies. Redirects, network providers, coercion, formatting,
escaping, cache mutation, and CLI workflows remain later-pipeline responsibilities.
