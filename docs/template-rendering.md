# Template rendering prototype (#31)

For a task-oriented introduction, read the [Stencil user guide](../Sources/MarkdownUtilitiesTemplates/Documentation.docc/RenderingMarkdownWithStencil.md).
It is also the User guide topic in the `MarkdownUtilitiesTemplates` DocC catalog.

`MarkdownUtilitiesTemplates` supplies single-document rendering for the CLI and
future #90 resource codecs. Stencil renders the body; Yams serializes an explicit
frontmatter object. No template is responsible for YAML quoting or delimiters.

```console
swift run md-utils template render --template ./examples/templates/report.stencil --data ./examples/templates/report.json
swift run md-utils template render --template ./examples/templates/report.stencil --data ./examples/templates/report.json --output ./tmp/report.md
```

Input is a JSON envelope with required `data` (any JSON value) and optional
`frontmatter` (an object). Omission produces no block, `{}` produces an empty YAML
block, and explicit `null` for the frontmatter object is rejected. Null values
inside the object are supported. Both variables are available in the body template.
An optional `--schema` JSON Schema validates the entire envelope before rendering.
Schemas validate supplied values; they do not populate defaults or map fields.

The library accepts `MarkdownTemplateInput` containing existing Core `JSONValue`
values. `MarkdownTemplateRenderer.render(template:input:schema:)` returns exact
assembled source and a parsed `MarkdownDocument`; it also parses the body AST.
The library has no filesystem, HTTP, or SQLite operations. A private adapter is
the only place that imports Stencil. Stencil is outside Core and its WASM graph;
WebAssembly support is deferred, not assumed. Native platform validation remains
necessary before treating this prototype as the completed #31 foundation.

CLI callers choose their own templates. Server administrators must choose templates;
request data must never select template source or host paths. No template loader
is installed: executed includes or inheritance requiring another template fail.

## Rendering behavior and limits

- Frontmatter keys are serialized in sorted order with Yams' Codable encoder.
  Values retain their structured types; callers do not pre-escape frontmatter strings.
- Stencil receives literal body text with its default whitespace behavior. Callers
  prepare body values for Markdown tables, links, or other special contexts. There
  are no md-utils formatting filters.
- Body source and rendered output must not begin with `---` or `+++` delimiter
  lines, including CRLF forms. This deliberately also reserves a leading Markdown
  horizontal rule written as `---`; use `***` instead. Unterminated opening
  delimiters are rejected rather than interpreted as a second frontmatter source.
- Missing and null values interpolate as empty text; null is false in conditions.
  Only the Stencil presentation copy recursively maps null to empty strings,
  retaining dictionary keys and array positions. Schema validation and YAML
  serialization retain actual null values. Empty strings/arrays are false in
  conditions. Use a schema with required fields when missing data must fail;
  strict mode is deferred. Stencil's existing filters operate on the presentation
  values, so null behaves like an empty string in filters as well.
- For repeatable reports, iterate ordered arrays and avoid time-dependent features
  such as Stencil's `now` tag. General byte determinism across all Stencil features
  is not yet promised.
- Defaults: 16 MiB template source, 64 MiB JSON input, 64 MiB assembled output.
  CLI file reads are bounded. Library input size is measured by encoding the envelope
  as JSON. Body/output checks happen after rendering and serialization. These checks
  do not bound peak memory, iterations, recursion, or execution time; users are
  responsible for their workloads. No execution sandbox is claimed.
- Output is validated before stdout emission or atomic file replacement. An explicit
  existing output file is replaced on success. Parent directories must already exist.
  Explicit output filenames must end in `.md` or `.markdown` (case-insensitive).
  Other extensions and extensionless paths fail before input reads or writes.
  Stdout always contains Markdown. Non-Markdown generation is explicitly unsupported;
  future host detection, wrapping, and placement depend on issue #134.
- Failures carry an input/schema/template/frontmatter/output stage. Stencil's own
  diagnostic detail is retained as text without leaking engine types into the API.

TOML, includes tooling, formatting helpers, frontmatter mappings, batch rendering,
additional input formats, and REST persistence are outside this prototype.

## Verification

```console
swift test --filter MarkdownTemplateRendererTests
swift test --filter TemplateTests
docker build --file Dockerfile.server-linux --tag md-utils-server-linux .
```

Fixtures cover typed YAML values, loops/empty states, schema rejection before
rendering, reserved delimiters, missing includes, size checks, and preservation
of an existing output on failure. See #93 for the later resource-creation boundary.

Prototype verification: native macOS build, sample CLI rendering to stdout/file,
and all 1,444 tests passed. Linux Docker verification with Swift 6.2 on Ubuntu Noble
also passed: the rendering target built and all 14 focused template/CLI tests
passed. Earlier dependency-fetch DNS failures were resolved on retry. This was
focused Linux verification, not a run of the entire Linux test suite. SwiftPM
generated the Stencil 0.15.1 lockfile entry.

The Native Server Linux workflow and `Dockerfile.server-linux` include the focused
template tests, so future renderer changes retain Linux coverage.
