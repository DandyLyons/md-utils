# Declared semantic string formats

Explicit `md-utils-type-schema: "2"` definitions support RFC 0003's `Date/ISO8601`,
`LocalTime/ISO8601`, `DateTime/RFC3339`, `UUID/RFC9562`, and `Wikilink/Obsidian`.
The subject alone selects the listed default. Names are case-sensitive; `Time`
and `DateTime/ISO8601` are unsupported. Initialization remains v1. Existing v1
definitions retain their selected schema engine's format behavior.

```yaml
md-utils-type-schema: "2"
name: Event
version: "1"
frontmatter:
  schemas:
    - inline:
        type: object
        required: [id]
        properties:
          id: {type: string, format: UUID}
          date:
            anyOf:
              - {type: string, format: Date}
              - {type: "null"}
          related:
            type: array
            items: {type: string, format: Wikilink}
  recommendedSchemas:
    - inline:
        properties:
          published: {type: string, format: DateTime}
body: {requirements: [], recommendations: []}
context: {requirements: [], recommendations: []}
```

Use existing `types doctor`, `types check`, and `rules validate` commands.
`types schema --schema-version 2` prints the v2 definition schema; omission still
prints v1.
Every array item is assessed, including malformed links. Format validation does
not require destinations, a filesystem, or a network connection. Recommendations
use the same assertions at advisory severity; configuration errors always fail
loading. Presence still follows `presence` and required schemas. Recommendations
alone do not require frontmatter. JSON Schema `required` controls key presence;
nullable `anyOf` controls whether a present value can be null.

Quote dates and times in YAML/TOML. Native temporal values retain kind evidence
before the legacy JSON projection and fail string contracts with `native-kind`.
The evaluator never normalizes or edits stored text. Empty strings fail all five
profiles; null is not an empty string. TOML has no null value.

## Exact profiles and typed views

`MarkdownSemanticScalar.parse(_:format:)` returns the original source, canonical
format name, and a typed view. Dates and local times use `DateComponents` without
a host timezone. Timestamps retain components, nanoseconds, numeric offset and
unknown-offset metadata alongside a Foundation instant. Original text preserves
precision beyond a floating-point instant's precision.

- Dates require four-digit years 0001–9999, two-digit month/day, and a real date in
  the proleptic Gregorian calendar. `2024-02-29` passes; `1900-02-29` fails.
- Local times require `HH:mm:ss`, hours 00–23 and minutes/seconds 00–59. An optional
  period has 1–9 ASCII fractional digits. Offsets, leap seconds and 24:00:00 fail.
- Timestamps require `T`/`t` and `Z`/`z` or signed `HH:mm` offsets up to 23:59.
  `-00:00` is accepted and retained as an unknown local offset. UTC instants may
  cross the authored year bounds. Foundation parses the validated local value as
  UTC before the offset is applied, avoiding Foundation's narrower offset parser.
- UUIDs require the 36-character hyphenated hexadecimal spelling, case-insensitive.
  RFC variant versions 1, 3, 4, 5, 6, 7 and 8 pass, as do Nil and Max. Version 2,
  other variants/versions, braces, URNs and compact spelling fail.
  `MarkdownSemanticScalar.generateUUID()` explicitly uses Foundation `UUID()` for
  v4 generation; it neither allocates identity nor promises collection uniqueness.

## Whole-value wikilinks

`Wikilink.parse(_:context:)` reuses the existing Parsing-based parser and consumes exactly
one complete link. It preserves target, display text, heading/block fragment,
embed flag and source. `[[Bob]]` passes; `See [[Bob]]`, adjacent links, surrounding
whitespace, trailing text, empty/whitespace-only destinations without an anchor,
newlines, NUL, nested open brackets, missing closing brackets and empty anchors fail.
Spaces within names and display text are retained, not trimmed. Empty display
text is permitted. Heading-only links are permitted. Block identifiers contain
ASCII letters, digits and dashes. The first alias separator wins; subsequent pipes
remain display text.

Obsidian's [table syntax](https://obsidian.md/help/advanced-syntax) escapes alias
separators as `[[Note\|Alias]]`. Select `.markdownTable` explicitly to interpret
that spelling as an alias, preserving the backslash in `rawValue`. Both
`Wikilink.parse` and `WikilinkScanner.scan` default to `.standard`, which interprets
the escaped pipe as a literal target pipe. Declared frontmatter scalars explicitly
use `.standard`; table escaping is never inferred from their contents.

Discovery and whole-value parsing share syntax validity and interpretation within
each context. Document discovery defaults to `.legacy` to retain historical
permissive behavior, and accepts an explicit context override. Reparse occurrences
with the same context used for discovery. Context does not detect tables or exclude
code spans/fences. Semantic parsers can be reused for body occurrences without
asserting frontmatter contracts or named relationships. Backslashes before other
characters retain existing parser behavior and are not a general unescaping operation.

`Wikilink.suggestion(canonicalTarget:alias:)` generates `[[Canonical|Alias]]` using
the host-supplied destination, following [Obsidian aliases](https://obsidian.md/help/aliases).
Aliases never substitute for destination identity. It rejects inputs that would
change the supplied target through syntax injection. Link style, extensions,
resolution, relationships and cycle policies remain separately scoped.

## Schema assertions, diagnostics and compatibility

The pinned JSONSchema.swift engine has no public custom-format hook. The adapter
specializes each semantic format to an enum of the current record's matching
strings, including property names. Existing enums are intersected. This is an exact
predicate over the finite values the engine can encounter; the engine still
evaluates branches, negation and loaded references. No post-validation property
walk determines conformance. A separate explanation pass retains failed-branch
causes without reporting failures from successful alternatives.

`frontmatter.format.invalid` carries an escaped JSON Pointer, schema location,
definition source when supplied, declared format, severity and stable reason:
`native-kind`, `syntax`, `trailing-input`, `calendar-range`, `precision`, or
`uuid-layout`. Shape/presence diagnostics retain their existing codes. Definition
errors identify `type.format.unsupported`, `.declaration`, or `.capability`.

The v2 adapter supports Draft 2020-12 resources and explicitly rejects unsupported
dialects and engine capabilities: dynamic/recursive references, unevaluated
properties/items, prefixItems, min/maxContains, and legacy dependencies/additionalItems. It does not silently substitute
partial semantics. Recursive references and schema expansions beyond 128 levels or
10,000 nodes are rejected during compilation. Uppercase-initial or slash-containing formats reserve the
semantic namespace. Lowercase slash-free formats retain engine behavior.
References must select object schemas at standard schema locations via resource
identifiers or JSON Pointers; anchor references and pointers into literal data or
extension keywords are rejected with a capability error by this adapter.

Bundled v2 definition and registry/profile JSON files have matching versioned
copies under `site/schemas/mdtype/2/`. These are publication inputs, not evidence
that the URLs are deployed. Generic JSON Schema consumers may treat `format` as
annotation and do not thereby implement this profile. Authoring defaults and
schema aliases remain unchanged. No automatic migration or downgrade is added:
review all loaded schemas for reserved names before explicitly adopting v2, and
remove v2 features deliberately before reverting to v1.

Native/direct/indexed consumers share Core evaluation. The evaluator fingerprint
advances to invalidate old cached assessments, and includes recommended schemas
and their resolved resources. Tests: `swift test --filter
'MarkdownSemanticScalarTests|RulesIndexedValidationTests'`. WASM smoke exercises
all profiles and nullable composition; Linux validation runs in CI only.
