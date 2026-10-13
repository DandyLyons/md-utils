# RFC 0003: Declared Semantic String Formats

- Status: Specified; implementation tracked separately in #173/#174
- Date: 2026-10-12
- Tracking: [#171](https://github.com/DandyLyons/md-utils/issues/171), [#169](https://github.com/DandyLyons/md-utils/issues/169)
- Version coordination: [#135](https://github.com/DandyLyons/md-utils/issues/135), [#184](https://github.com/DandyLyons/md-utils/issues/184)
- Definition version: `md-utils-type-schema: "2"`; reserved by this RFC, not yet implemented

## Purpose and compatibility boundary

Extend mdtype with explicit semantic string contracts while preserving native
YAML/JSON/TOML value types. A declaration identifies what a string represents and
how it is represented. Values are never classified by guessing their contents:
`garden-notes` is not implicitly a Slug. One string may satisfy multiple contracts.

This RFC records the completed specification. It does not enable new
runtime behavior, publish schemas, or alter [mdtype v1](0001-mdtype.md). Normative
requirements below describe the future implementation. API mechanics and platform
verification belong to the implementation issues, not to an alternative contract.

## Declaration model

`type` describes the stored native value kind. A semantic string declaration MUST
use `type: string`; its `format` is `Subject/RawFormat`, or a subject alone to select
the definition version's default raw format. There is no separate `scalars` key,
custom YAML tag, or `type: Date` syntax.

```yaml
type: object
required: [id]
properties:
  id:
    type: string
    format: UUID/RFC9562
  published:
    anyOf:
      - type: string
        format: Date/ISO8601
      - type: "null"
  related:
    type: array
    items:
      type: string
      format: Wikilink/Obsidian
```

Property selection, nested objects, arrays, presence, cardinality, and composition
use JSON Schema constructs. Every array item is assessed; malformed values MUST NOT
disappear through filtering. Diagnostics retain array indices.

Subjects and raw format identifiers are case-sensitive. Unsupported semantic
subjects/combinations and malformed declarations are configuration errors, even in
recommended checks. Defaults are fixed by the definition-language version and MUST
NOT change with the OS, locale, timezone, or package upgrade. `Date` is shorthand
for `Date/ISO8601`, not automatic recognition.

## Initial registry

| Subject | Raw format and default | Contract |
| --- | --- | --- |
| `Date` | `ISO8601` | Extended calendar date, `YYYY-MM-DD` |
| `LocalTime` | `ISO8601` | Local wall time, `HH:mm:ss`, optionally 1–9 fractional digits; no offset |
| `DateTime` | `RFC3339` | Complete calendar date and time with required `Z` or numeric offset, optionally 1–9 fractional digits |
| `UUID` | `RFC9562` | Standard hyphenated hexadecimal UUID representation; multiple standardized UUID versions |
| `Wikilink` | `Obsidian` | Exactly one complete wikilink under the documented Obsidian grammar |

These are supported profiles of existing standards, not promises to accept every
representation described by those standards. There is no broad `DateTime/ISO8601`
alias, ambiguous `Time` alias, Unix timestamp subject, or Unix timestamp raw format.
Human readability is a requirement for authored temporal values.

## Presence, nullability, and native values

Use **key presence** and **value nullability**, not “optional” as a synonym for
either. `required` controls key presence. `anyOf` combines a string-format branch
with a `type: "null"` branch when null is allowed. `format` appears only in a branch
whose declared `type` is `string`.

| Key presence | Value nullability | Behavior |
| --- | --- | --- |
| Required | Non-nullable | Key must exist with a valid value |
| Required | Nullable | Key must exist; explicit null is accepted |
| Non-required | Non-nullable | Key may be absent; present null fails |
| Non-required | Nullable | Absence and explicit null are both accepted |

An empty string is neither absence nor null and fails these initial formats.
TOML has no native null representation; an absent key remains available for a
non-required value. This RFC introduces no TOML null sentinel.

Native YAML/TOML temporal values MUST NOT be silently coerced to strings to pass a
semantic string contract. Report the native-kind mismatch and explain quoting.
The implementation must retain enough native-kind information before any existing
JSON projection to enforce this; it must not redefine legacy decoding behavior.

## Requirements and recommendations

Severity belongs to the containing schema check, not individual property formats.
Existing `frontmatter.schemas` checks remain requirements. Add
`frontmatter.recommendedSchemas` with the same inline/reference envelope for
advisory checks in the future definition version:

```yaml
frontmatter:
  presence: required
  schemas:
    - inline:
        type: object
        properties:
          published: { type: string }
  recommendedSchemas:
    - inline:
        type: object
        properties:
          published: { type: string, format: Date }
```

Both check groups enforce formats identically. Failed requirements prevent
conformance; failed recommendations produce advisories. Invalid configuration is
never downgraded to an advisory. Missing properties are governed by `required`, not
implicitly required by `format`. Existing explicit frontmatter presence behavior
remains independent of recommendation severity.

## Assertion semantics and JSON Schema integration

The new mdtype evaluator MUST explicitly assert registered formats. Merely passing
these declarations to a JSON Schema engine that treats `format` as annotation is
insufficient. A generic JSON Schema consumer may not enforce md-utils formats;
documentation and exported schemas must disclose that distinction.

Format assertions participate in schema composition, including `anyOf`, `oneOf`,
and `not`; a disconnected post-validation walk is not equivalent. An unsuccessful
date branch must not make a successful nullable `anyOf` fail, and it must not make
an invalid date satisfy a string branch whose format was ignored.

mdtype v2 supplies an explicit evaluation profile over its loaded JSON Schema graph,
not a claim that a generic JSON Schema engine implements these formats. Reserve
`https://dandylyons.github.io/md-utils/schemas/mdtype/2/semantic-formats.json` as
the immutable machine-readable registry/profile identifier. This is a publication
target, not an already available URL. The definition version selects the profile;
no new `$schema` override is required inside embedded schemas.

Recognize semantic subjects by an uppercase ASCII initial or a slash in `format`.
Such names MUST match the registry exactly and MUST occur with sibling
`type: string`; unknown names/combinations are configuration errors. This reserves
that namespace in v2. Lowercase slash-free standard/custom format names retain the
existing selected schema engine's behavior; they are not aliases for these subjects.
For example `date` and `Date` are distinct. Apply the profile consistently through
all explicitly loaded references in a v2 assessment, even where a resource declares
a standard JSON Schema dialect. Compilation is keyed by profile and resource, so a
shared schema assessed by v1 retains v1 behavior. No implicit network loading is added.

Implement format assertions within the schema evaluator's branch evaluation using
a format hook or validator adapter. If an engine cannot support the profile for a
schema/dialect, reject compilation with a capability error before assessment;
never silently ignore a format or substitute a post-validation walk. This is an
implementation requirement for #173/#174, not permission to weaken composition.

## Parsing, validation, and preservation

Use Foundation for supported expected string formats. Use the existing Parsing
infrastructure for project text grammars such as wikilinks. All scalar validation
MUST consume the entire string, reject surrounding whitespace/trailing text, and
perform no network access, file resolution, or mutation.

Foundation parse success alone does not establish conformance. Validate the
declared textual profile and calendar/range constraints without silently accepting
Foundation's normalization of invalid input. Preserve the original string; parsed
values are typed views, not replacement storage.

Normalization is explicit and separate from assessment. It MUST NOT silently
truncate precision, change a represented value, or rewrite a record. Foundation
handles valid-date calculations and serialization after validation. A calendar
date and local time should be represented by components, not implicitly assigned
the host timezone. A timestamp can use `Foundation.Date` while retaining source
text/offset/precision separately.

### Temporal profiles

- Require zero-padded date and time components and seconds in time values.
- Fractional seconds, when present, have 1–9 digits. This is the supported precision
  limit, not a claim that ISO 8601/RFC 3339 themselves impose that exact limit.
- DateTime accepts UTC `Z` and numeric offsets. Preserve the original spelling.
- Reject impossible calendar dates, including February 30; do not accept the
  normalized March date as evidence of conformance.
- LocalTime has no offset and cannot absorb an offset as ignored trailing input.
- Unsupported leap-second/end-of-day representations must be explicitly diagnosed;
  they must not silently normalize to another day.

The precise supported profile is:

| Component | Accepted values |
| --- | --- |
| Year | Four ASCII digits, 0001–9999; year zero and expanded/signed years unsupported |
| Calendar | Proleptic Gregorian; month 01–12 and actual day count, including leap-year rules |
| Time | Hour 00–23, minute/second 00–59; seconds mandatory |
| Fraction | ASCII period followed by 1–9 ASCII digits; no decimal comma |
| DateTime separator | `T` or `t`; space unsupported |
| UTC designator | `Z` or `z` |
| Numeric offset | Sign and `HH:mm`, hour 00–23 and minute 00–59 per RFC 3339 grammar |
| Unknown local offset | `-00:00` accepted and retained as unknown-local-offset metadata, distinct from known zero offset |
| Leap seconds / end of day | `:60` and `24:00:00` explicitly unsupported; never normalize them |

These documented restrictions, notably year zero and leap seconds, mean the profile
is a subset of the referenced standards. A temporary uppercase copy may be passed
to Foundation for case-insensitive `t`/`z`; retain original text. Keep the declared
local date and offset even if the corresponding UTC instant crosses the year bounds.
Normalization may uppercase `t`/`z` but MUST NOT erase unknown-offset information.

### UUID

Parse and serialize through Foundation UUID. Accept multiple standardized UUID
versions, including v4 and v7; v4-only applies to **generation**, not input.
Version/variant checks are distinct from the common text representation and must
not be inferred from successful `UUID(uuidString:)` parsing alone.

Offer v4 generation through `UUID()`. Generation is explicit, does not occur during
validation, and does not allocate document identity or promise collection uniqueness.
Do not offer v7 generation in this scope. Generation entry-point/CLI syntax remains
an implementation design task, coordinated with existing creation/identity APIs.

Accept the RFC 9562 variant with versions 1, 3, 4, 5, 6, 7, and 8. Also accept the
explicit Nil (all zero bits) and Max (all one bits) special forms; they are values,
not JSON null. Reject version 2 (reserved DCE security), unassigned version numbers,
and other variants except those two special forms. Acceptance checks representation
and layout bits, not proof of the generator, randomness, timestamp truth, or uniqueness.
The text is exactly 36 ASCII characters with hyphens in the 8-4-4-4-12 layout;
hexadecimal letters are case-insensitive. Braces, URN prefixes, compact hexadecimal,
and surrounding whitespace are not part of this raw format.

### Wikilink

Follow Obsidian's documented links, aliases, and embeds. Reuse and audit the existing
Wikilink model/parser rather than introducing a second grammar. Preserve target,
alias, heading/block fragment, embed flag, and source text. `[[Bob]]` is a scalar;
`See [[Bob]]` and `[[Bob]] plus [[Alice]]` are not.

Syntax validity does not require a destination to exist. Name/path style and extension
constraints belong to #176; resolution and relationship policies remain separate.
Cycles are valid data by default and outside this scalar RFC.

The pinned SwiftKnap `wikilink` filter generates links; it is not a whole-value
validator. Reuse Knap infrastructure only where its actual APIs and grammar fit,
without adding the native template runtime to portable Core.

## Diagnostics

Stable diagnostics must carry definition/schema provenance, schema location,
instance property path, array index where applicable, subject/raw format, severity,
and a reason. Preserve source locations when available. Use the new diagnostic
code `frontmatter.format.invalid` with stable reason identifiers `native-kind`,
`syntax`, `trailing-input`, `calendar-range`, `precision`, and `uuid-layout`.
Schema composition retains branch diagnostics as causes without promoting failures
from a successful alternative into top-level errors. Configuration failures use
`type.format.unsupported`, `type.format.declaration`, or `type.format.capability`.
Existing RFC 0001 shape/presence diagnostics retain their codes.

For example: `/related/2`: expected one complete Wikilink; found trailing text.
Configuration errors must point to the offending declaration. A parsing failure
must never be reported as a missing destination or network failure.

## Foundation audit evidence and platform requirements

Local probes on 2026-10-12 compiled with Swift 6.4 and Swift 6.3.1 and ran against
the same installed macOS Foundation, producing identical baseline results. This
does not establish behavior on older macOS runtimes, Linux, or WASM.

| Probe | Observed result |
| --- | --- |
| Date `2026-02-30` | Accepted and normalized to March 2 |
| Date `2026-1-2` | Accepted without required padding |
| Date `2026-10-12junk` | Accepted with ignored suffix |
| LocalTime `25:00:00` | Accepted and normalized |
| Timestamp without offset | Rejected by the tested style |
| Fractional timestamps | Accepted tested 1–9 digit precision; rejected tested 10 digits |
| UUID v4/v7 strings | Both parsed and serialized |
| UUID with version 15 bits | Parsed; semantic validation is additional |
| `UUID()` | Generated version 4 and round-tripped |
| `UUID.version7()` | Unavailable in installed SDK |

Installed SDK declarations make `Date.ISO8601FormatStyle` available from macOS 12 /
iOS 15, but `DateComponents.ISO8601FormatStyle` from macOS/iOS 26. Current project
minimums include macOS 13/iOS 16. Upstream v7 generation is marked FoundationPreview
6.5; it is not a baseline capability. Components parsing also accepted impossible
components and trailing text. A naive `isValidDate(in:)` probe returned false even
for a valid date-only value, so that call is not yet a verified validation solution.

Implementation must establish a Foundation-backed strategy for current deployment
minimums, exact full-input validation, and portable behavior. Linux verification
runs in CI only. Include WASM coverage before advertising portable support; do not
raise deployment minimums or substitute a parser implicitly.

## Versioning, publication, and migration

Reserve mdtype definition version `"2"` for this contract. This is the specific
compatibility decision for #135; #184 will incorporate it into the broader matrix.
Product releases, project config, mdtype language, authored contract versions,
server formats, and cache/evaluator versions are distinct. No project config or
mdrule version changes are required solely to reference a v2 definition through
existing type references; the reader must support v2 explicitly.

| Reader / writer | v1 | v2 |
| --- | --- | --- |
| Current implementation | Existing behavior | Reject unsupported version |
| Implementation of this RFC | Preserve existing behavior | Assert this profile; reject unsupported declared capabilities |
| Authoring defaults | Remain v1 until deliberate release activation | Explicit opt-in during implementation |

Publish the v2 definition schema at
`https://dandylyons.github.io/md-utils/schemas/mdtype/2/mdtype.schema.json` alongside
the semantic registry/profile. These reserved URLs are not live-publication claims.

Before activation, publish immutable versioned schemas from canonical bundled
sources, synchronize public copies, document reader/writer support and defaults,
and update CLI help, DocC, and the distributed skill. Publishing a package does not
automatically advance schema aliases or initialization defaults.

Migration is explicit and previewable. Preserve v1 definitions and meanings; never
infer new format declarations from values, property names, or existing `format`
annotations. Unsupported semantics must be rejected with guidance, not coerced.
Existing readers must reject unsupported definition versions. Invalidate indexed
assessments when evaluator semantics change. A v1-to-v2 preview must compile the
whole reference graph and flag formats entering the reserved semantic namespace;
do not automatically reinterpret them. A definition with no affected declarations
may explicitly change its version while preserving all other members. Added semantic
constraints are deliberate user edits, not inferred migration. Downgrading a v2
definition containing semantic formats or recommended schemas must be refused unless
the user explicitly removes those features; do not silently discard constraints.
The specification reserves versions but implements no migration or runtime support.

## Extension path and delivery

Future Duration, URL, EmailAddress, VaultPath, and Slug subjects require separate
proposals identifying an existing standard where applicable, Foundation/API support,
raw formats, defaults, typed representations, diagnostics, and compatibility.
No automatic type inference or Unix timestamp support is implied.

Delivery sequence: implement shared v2 schema assertion integration and Wikilink in
#173, then temporal/UUID behavior in #174; verify
schema assertion composition and required/advisory parity; publish documentation
and compatibility evidence. #172 owns relationships; #176 owns link style constraints.

Incremental builds may support only the implemented subjects, but must report
`type.format.capability` for known, unimplemented subjects. They must not advertise
the complete v2 registry as implemented until #173/#174 and platform checks pass.
Public parser API names, validator adapter mechanics, generation command syntax,
and CI implementation are delivery tasks; they cannot change this contract silently.

## Acceptance examples and implementation checks

| Declaration/input | Required result |
| --- | --- |
| Date: `2024-02-29` / `2023-02-29` | Pass / calendar-range failure |
| Date: `2026-1-2` / `2026-10-12junk` | Reject padding / trailing input |
| LocalTime: `09:30:00.123` / `09:30:00Z` | Pass / reject offset |
| DateTime: `2026-10-12t09:30:00z` | Pass, preserve case |
| DateTime: `2026-10-12T09:30:00-00:00` | Pass, retain unknown-offset status |
| UUID: v4 / v7 / version 15 | Pass / pass / uuid-layout failure |
| Nullable Date: null / empty string | Pass / reject |
| Wikilink: `[[Bob]]` / `See [[Bob]]` | Pass / reject |

Implementation tests must cover nested properties/arrays and escaped property paths,
schema references and boolean composition, native temporal kinds, missing/null
distinctions, recommendations versus requirements, unknown format configuration
errors, original text preservation, and unchanged v1 outcomes. Validate direct and
indexed evaluation parity and invalidation. Platform verification is a release
requirement, not work claimed complete by this specification issue.

## References

- [ISO 8601 overview](https://www.iso.org/iso-8601-date-and-time-format.html)
- [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339)
- [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562)
- [JSON Schema validation](https://json-schema.org/draft/2020-12/json-schema-validation)
- [Foundation ISO date parser](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/Formatting/Date%2BISO8601FormatStyle.swift)
- [Foundation UUID](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/UUID.swift)
- [Obsidian links](https://obsidian.md/help/links), [aliases](https://obsidian.md/help/aliases), [embeds](https://obsidian.md/help/embeds)
