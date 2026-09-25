# Knap template rendering

`MarkdownUtilitiesTemplates` uses [SwiftKnap](https://github.com/DandyLyons/SwiftKnap)
for single-document Markdown generation. The CLI and server creation codec share
this implementation. SwiftKnap owns execution and platform support; md-utils uses
only its Swift API. Core/WASM does not depend on SwiftKnap.

```console
swift run md-utils template render --template ./examples/templates/report.knap --data ./examples/templates/report.json
swift run md-utils template render --template ./examples/templates/report.knap --data ./examples/templates/report.json --output ./tmp/report.md
```

See the [Knap guide](../Sources/MarkdownUtilitiesTemplates/Documentation.docc/RenderingMarkdownWithKnap.md).

## Document contract

Input is a JSON envelope with required `data` (any JSON value) and optional
`frontmatter` (an object). Both are template variables. Omission produces no
frontmatter block; `{}` produces an empty YAML block; explicit null frontmatter
is rejected. Nested null values are preserved. Optional `--schema` validates the
complete envelope before rendering and never supplies defaults.

Knap renders the body; Yams serializes frontmatter with sorted keys and typed
values. Templates and rendered bodies cannot start with YAML/TOML frontmatter
delimiters, including CRLF/BOM forms. Use `***` for a leading horizontal rule.
The assembled document is parsed and verified before output or persistence.

CLI output supports stdout or an explicit `.md`/`.markdown` file. Existing files
are replaced atomically only after successful validation; parent directories must
exist. Non-Markdown output remains unsupported (future host support is #134).

Server templates are administrator-owned; requests supply data, never template
source or host paths. Creation protects host metadata and the mutation service
validates the complete proposal before committing. Replace/patch never rerender
templates. See [resource mutations](resource-mutations.md).

## Knap behavior

- Knap is the only language. Rewrite old templates; no legacy engine, translation,
  or compatibility mode exists. Server `creation.template` strings use Knap in all
  supported server configuration versions.
- Standard SwiftKnap filters are available, including Markdown helpers. No custom
  filters, resolvers, DOM, filesystem, or network integrations are installed.
- Missing and null remain distinct in the SwiftKnap input. Knap controls all
  presentation semantics. Empty arrays are false; empty objects are true; `??`
  uses truthiness, including for zero/false. Null is never normalized to a string.
- Integer inputs outside ±9,007,199,254,740,991 are rejected; supply them as strings.
  Fractional numbers use JSONValue's Double representation; non-finite values fail.
- Arrays retain order. Objects use SwiftKnap's sorted dictionary conversion and
  upstream enumeration rules. Use arrays when order matters.
- Surrounding whitespace is preserved (`trimOutput: false`); internal whitespace
  follows Knap. Date/time/locale-dependent filters are not promised byte-deterministic.
- A shared lazy engine is reused. SwiftKnap handles concurrent execution; variables
  and limits are supplied per call.
- Errors preserve upstream codes/locations. Nonfatal warnings are returned by the
  library, printed to CLI stderr, and retained in creation validation and receipts.

## Limits

Default byte guardrails: 16 MiB template, 64 MiB JSON input, 64 MiB assembled output.
File reads are bounded; output checks happen after rendering/serialization and do
not bound peak allocation. SwiftKnap also applies finite default template/output/
value-length, operation, and nesting limits, which may reject input below byte
limits. Library callers can supply SwiftKnap `RenderLimits` through the renderer.
Cancellation does not interrupt running engine work. No wall-clock deadline or
execution sandbox is claimed.

## Build and deployment

Swift 6.3 is required. SwiftKnap is pinned to
`5972f60343683b3d5d7dd3ab0edf2b35085c542f`. Ubuntu 24.04 builds require
`libjavascriptcoregtk-4.1-dev` and `pkg-config`; deployments require
`libjavascriptcoregtk-4.1-0`. Preserve SwiftPM resource bundles beside installed
executables. The server Docker build verifies installed release rendering.

SwiftKnap and bundled Knap/Day.js are MIT; its JXKit dependency is LGPL-3.0. Follow
the upstream [distribution notices](https://github.com/DandyLyons/SwiftKnap/blob/main/ThirdParty/README.md).
SwiftPM does not bundle the Linux system runtime; this is not a standalone static
Linux executable. Upstream verified macOS and Ubuntu 24.04 arm64. Validate other
distributed architectures. Linux support does not imply WASM support; Workers
template creation remains separate work.

## Verification

```console
swift test --filter 'MarkdownUtilitiesTemplatesTests|TemplateTests|ResourceMutationPlannerTests|MarkdownMutationTests'
docker build --file Dockerfile.server-linux --tag md-utils-server-linux .
docker build --file Dockerfile.core-linux --tag md-utils-core-linux .
scripts/build-wasm.sh
```
