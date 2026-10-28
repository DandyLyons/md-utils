# Document query design (#203)

Status: v1 implementation and native verification, 2026-10-28. This document
records the approved behavior. The runtime uses shared frontmatter evidence,
requirements-driven SQLite projection, survey discovery budgets, and delayed
progress. Snapshot-only type/rule conditions remain explicitly deferred.
Issue: [#203](https://github.com/DandyLyons/md-utils/issues/203).

## Purpose and boundaries

Find documents matching common conditions without requiring a filtering language
or an external tool. A nested selector determines which documents match; it does
not project nested values into standalone results. Return each document once.

```sh
# Find matching document paths.
md-utils query notes/ --key Status --equals 'Read'

# Inspect complete frontmatter for matching documents.
md-utils query notes/ --key Status --equals 'Read' \
  --output frontmatter --oformat json
```

Output selection is `--output paths|frontmatter|count`, defaulting to paths.
There is no full-document output: users can retrieve a matching document or a
section using its path and existing commands. Serialization is independently
`--output-format text|json|json-pretty`, with alias `--oformat`, defaulting to text.
The proposed query spelling `--format` is superseded. Existing commands retain
their own output flags.

## Conditions and selection

- Literal, case-sensitive property selection uses `--key`; dots in keys are
  literal. `--key` and `--json-path` are mutually exclusive.
- Equality, inequality, presence, absence, explicit null, and immediate array
  membership are intended conditions. Missing is distinct from null; array
  membership is not substring matching. Explicit null testing uses `--is-null`.
- String value comparison supports case-sensitive and case-insensitive modes,
  defaulting to insensitive. Use mutually exclusive
  `--case-sensitive` / `--case-insensitive`, consistent with the existing array
  commands' case-insensitive option. This applies to compared string values,
  including container/member comparisons, not property keys, JSONPath member
  names, paths, or mdtype/mdrule identities. Use deterministic case folding without
  accent folding; fixtures cover case folding and preservation of accents.
- Numeric bounds include `--greater-than`, `--greater-than-or-equal`,
  `--less-than`, and `--less-than-or-equal`.
- `--is-type NAME` means conformance to that mdtype's required contracts, not
  declared intent. `--in-rule NAME` means selection by that mdrule independently
  of validation success.
- Do not combine independent conditions in v1, including type/rule conditions
  with property predicates. General AND/OR composition is deferred. The already
  approved lower/upper pair is one range condition on one selected value.
- Reject an impossible range before discovery or cache work. Examples include
  reversed bounds, equal bounds with an exclusive endpoint, and integer
  `> 3` / `< 4`. Validate the actual comparison domain, not argument spelling.
- `--jmespath` is deferred. Existing `fm search`, `fm dump`, and `index query`
  retain their independent interfaces.

### JSONPath

Use DynamicJSON's parser and evaluator. Enforce the supported subset by inspecting
its parsed representation; do not implement a second JSONPath parser.

The v1 subset is member access, quoted member names, array indices, and array/object
wildcards. Descendants, slices, unions, filters, and functions are deferred.
Unsupported features produce a usage error before file discovery.

| Selector | Meaning |
| --- | --- |
| `$.publication.year` | One nested member |
| `$.authors[0].name` | First author's name |
| `$.authors[*].name` | All existing author-name nodes |
| `$.contributors.*.name` | Name nodes under each contributor member |
| `$["publication.year"]` | One literal key containing a period |

`--match any|all` defaults to any. Any requires at least one selected value to
satisfy the complete condition; all requires a nonempty selection and every
selected value to satisfy it. Both endpoints of a range must hold for the same
node. Prices 2 and 20 do not jointly satisfy a range from 5 to 10.

Zero selected nodes is a known nonmatch for equality and ordering under either
mode. Missing properties do not create null nodes. All selected author-name nodes
matching does not establish that every author had a name.

Selector-based `--exists` / `--missing` are approved for JSONPath. Exists means at
least one selected node, including a null node; missing means no selected nodes.
For `$.authors[*].name`, one author with a name makes exists true even if another
author lacks that property. These do not establish per-element completeness.
Literal `--has-key NAME` / `--missing-key NAME` remain convenient forms, normalized
to `--key NAME --exists` / `--key NAME --missing`. Reject an explicit `--match`
with these selection-level predicates; any/all still applies to value predicates
such as `--is-null`.

## Types and formats

`--value-type` has alias `--vtype`. Base types follow mdtype/JSON Schema
terminology: string, boolean, integer, number, null, array, and object. Number
includes integer and floating-point numeric comparison; it does not mean
floating-point storage exclusively. Existing `FrontMatterValue` separately stores
`integer(Int64)` and `number(Double)`.

`--value-format` has alias `--vformat`. Accept existing semantic format names and
their existing short forms:

| Short form | Full format |
| --- | --- |
| Date | Date/ISO8601 |
| LocalTime | LocalTime/ISO8601 |
| DateTime | DateTime/RFC3339 |
| UUID | UUID/RFC9562 |
| Wikilink | Wikilink/Obsidian |

These formats describe strings in mdtype. Native temporal values retain their
stored kinds; permitting a comparison does not make them conform to a string
schema. The native evidence kinds are local-date, local-time, local-date-time,
offset-date-time, and yaml-timestamp. Inspect the actual YAML temporal form before
choosing date versus timestamp comparisons.

The owner delegated final value-matching choices. Use the following comparison
contract. Without a format, string is the default; do not automatically coerce
decoded strings to numbers or booleans.

| Domain | Operand encoding and eligible stored values |
| --- | --- |
| string | Literal CLI text; decoded strings, compared under the selected case mode |
| boolean | Canonical true/false CLI operand; decoded boolean values |
| integer | Optional sign and base-10 digits within signed 64-bit range; stored numeric values with an exact integral value in that range |
| number | JSON numeric syntax; preserve 64-bit integer tokens exactly and use finite binary64 for fraction/exponent operands; stored finite numeric values |
| null | `--is-null`, optionally with `--vtype null`; reject other operators with this domain in v1 |
| array | JSON array operand; stored arrays, recursively compared in order |
| object | JSON object operand; stored mappings, recursively compared by exact key identity, ignoring property order |

Numeric 3 and 3.0 compare equal; neither equals the string "3". Integral numeric
values such as 3.0 are eligible in the integer domain, consistent with schema
integer semantics. Integer operands themselves use integer spelling; `3.0` is not
an integer CLI operand. Integer tokens outside signed 64-bit range and numeric
overflow fail preflight. Compare large integer/mixed numeric values without
rounding all integers through Double; nonintegral numbers cannot satisfy integer
domain conditions. Preserve actual stored kinds separately from comparison value.

Containers use the same numeric, boolean, null, and selected string case rules
recursively. Exact object keys remain case-sensitive. Missing differs from null.
Native temporal values nested in containers retain their own kind and do not
equal an ordinary JSON string merely because its spelling resembles a date.
JSON operand examples: `--equals '["swift","cli"]' --vtype array` and
`--equals '{"enabled":true}' --vtype object`.

Inequality requires a present selected value eligible for the comparison domain.
Missing, incompatible kinds, and strings failing a requested semantic format are
known nonmatches, not automatic inequality matches.

`--vtype` and `--vformat` together select a comparison domain, not a declaration
that a stored value conforms to an mdtype schema. A format implies string operand
encoding when vtype is omitted; explicitly combining a format with a non-string
vtype is invalid. Formats parse selected strings using the existing semantic
parser. Temporal predicates also accept equivalent native temporal values in the
shared temporal comparison model, retaining native provenance; no string-schema
conformance is inferred. Calendar predicates have a date reference operand even
when selected values use DateTime format, as specified in the temporal matrix.

Date and LocalTime equality compare validated components; DateTime equality
compares instants with source precision preserved. UUID equality compares UUID
identity, independent of hexadecimal case. Wikilink equality validates whole-value
syntax and compares authored text under the selected case mode, without resolving
destinations or inferring equivalence from different spellings. Ordering applies
to numeric/temporal domains, not arbitrary strings, UUIDs, wikilinks, or containers.

Boolean identity comes from the existing YAML/TOML decoder, not a query-specific
raw-text spelling check. If the selected format decodes a source scalar as true,
compare it as true regardless of its authored spelling. Do not reinterpret a
decoded string or number as boolean. Canonical true/false CLI operands provide an
unambiguous input vocabulary for mixed YAML/TOML populations.

Reject incompatible option combinations, such as `--vtype boolean --vformat Date`,
before scanning. Non-finite numeric operands are usage errors; stored NaN/infinity
are known nonmatches for finite numeric predicates. If a matching document has a
non-finite value elsewhere, preserve it in JSON using explicitly tagged evidence
instead of emitting invalid JSON or silently changing it to null. The exact tagged
representation is specified with the approved JSON entry metadata below.

Reuse existing semantic parsers and preserve source evidence rather than inventing
a new scalar grammar. See [semantic string formats](semantic-string-formats.md).

## Temporal comparison contract

The owner accepted the following matrix. The later direction to use one timezone
flag supersedes the earlier separate source-timezone requirement.

| Selected value | Operation/reference | Behavior |
| --- | --- | --- |
| Calendar date | Before/after another date | Compare calendar dates |
| Calendar date | Same day/week/month/year | Compare calendar periods |
| Offset timestamp | Before/after another timestamp | Compare instants with offsets accounted for |
| Offset timestamp | Before/after a date | Compare its calendar date under the selected date mode |
| Offset timestamp | Same day/week/month/year | Extract calendar components under the selected date mode |
| Local datetime | Another local datetime | Compare local date/time components |
| Local datetime | Calendar-period predicate | Use its local calendar components |
| Local datetime | Instant comparison | Interpret in the effective `--timezone`; retain that assumption in provenance |
| Local time | Another local time | Compare clock times |
| Local time | Calendar date or timestamp | Incompatible: do not invent a missing date |

Date-only values remain dates. A date operand to before/after chooses calendar
date ordering; a timestamp operand chooses instant ordering. Before/after are
strict. A timestamp on the reference calendar date satisfies neither before nor
after that date. A calendar date cannot supply an instant by implicitly assigning
midnight. Calendar-period predicates take a reference date in the examples below;
support for additional reference forms needs an explicit contract.

```sh
# Selected strings are timestamps; the reference operand is a calendar date.
md-utils query notes/ --key Created --vformat DateTime \
  --same-day '2026-10-28' --timezone America/Chicago

# Use the calendar date written in each timestamp.
md-utils query notes/ --key Created --vformat DateTime \
  --same-day '2026-10-28' --date-mode written

# Compare against an instant.
md-utils query notes/ --key Created --vformat DateTime \
  --before '2026-10-28T12:00:00Z'
```

### Date modes and one timezone setting

`--date-mode timezone|written` defaults to timezone:

- Timezone mode converts offset timestamps into the effective timezone before
  calendar grouping.
- Written mode uses the validated calendar components authored in each timestamp,
  without converting the authored offset. It does not change instant ordering.

`--timezone local` is the default; resolve the system timezone once per invocation.
Accept explicit UTC and named zones such as America/Chicago. The same setting
supplies the zone for interpreting local datetimes when an instant comparison
requires one. There is no `--assume-timezone` flag. The documented local default
also applies to that interpretation; report requested and resolved settings so
the assumption is visible. Written calendar grouping does not convert offsets,
but timezone can still matter for local-datetime-to-instant interpretation.

Report requested timezone, resolved identifier, date mode, and week start when
relevant. `--week-start sunday|monday` defaults to Sunday. Weeks can span year
boundaries. Use Gregorian calendar periods and actual timezone boundaries rather
than assuming every calendar day has 24 hours.

The owner delegated selection of a sensible daylight-saving policy. Adopt the
conservative policy: a local datetime that is ambiguous or nonexistent in the
effective timezone is unknown for an instant comparison, with a per-file reason.
Do not silently choose an occurrence or shift a nonexistent time. An ambiguous or
nonexistent query operand requiring instant interpretation fails preflight. Values
with explicit offsets are already unambiguous instants; local calendar-only
comparisons need no instant conversion. No DST-resolution flags are added in v1.
Fixture verification is required implementation work, not an open policy choice.

Native YAML timestamp spellings (including spaces and short offsets) follow the
Yams codec's component conventions; an omitted YAML timestamp zone means UTC.
TOML local datetimes remain local and use `--timezone` when an instant is needed.
The shared TOML evidence adapter consumes the existing dependency's C parse tree
because its Swift `Date` bridge discards authored components and offsets. No new
dependency or independent TOML grammar is introduced.

Preserve original timestamp components/offsets in shared parsing evidence for
written mode. Existing TOML offset datetime decoding stores a Foundation Date and
cannot recover the original offset from that value alone. Extend the shared
evidence model; do not reconstruct authored components from normalized JSON.

### Shell quoting

In ordinary POSIX-style shells, a literal such as `2026-10-28` or
`2026-10-28T12:00:00Z` is safe as an unquoted argument: its hyphens and colons do
not trigger shell expansion, and the argument does not begin with a hyphen.
Nevertheless, quote date/time literals consistently in documentation. Spaces,
wildcards, dollar signs, and other shell syntax in more general values need
appropriate quoting. Quoting does not make an unsupported date format valid.

Always single-quote JSONPath examples so the shell passes `$`, brackets, and `*`
to md-utils literally. For example:

```sh
# JSONPath quoting protects shell metacharacters; date quoting is conventional.
md-utils query notes/ --json-path '$.events[*].created' --vformat DateTime \
  --same-day '2026-10-28'
```

## Scope, execution, and outcomes

Reuse survey scope conventions: a deduplicated union of files/recursive folders,
working-directory-relative CLI paths, project-root-relative file-list entries,
exclusions, project confinement, supported Markdown/other UTF-8 text hosts, and
explicit hidden/symlink coverage notes. Exact file-list and resource budgets need
verification. Non-text attachments are skipped and counted, not failed queries.
Preserve existing encoding, LF-only processing, and host-envelope contracts.

| Situation | Outcome |
| --- | --- |
| Invalid operand, impossible range, unsupported selector feature, conflicting options | Usage error before discovery/cache work |
| Valid stored value of an incompatible kind, or string failing the requested format | Known nonmatch |
| No matching documents after complete execution | Success, including zero count |
| Unreadable/malformed source, required evidence unavailable, or exhausted execution budget | Preserve confirmed matches, report incomplete status, exit nonzero |
| Expected non-text attachment skip | Count the skip without making results incomplete |

Do not categorize malformed/unreadable sources as absent or empty frontmatter.
Preserve cancellation rather than starting a fallback scan. For type/rule queries,
distinguish inability to decide membership from inability to serialize a known
match's frontmatter. Summary counts distinguish membership-unknown files from
confirmed matches whose requested output is unavailable.

Follow [shared cache policy](index-cache-policy.md): no implicit index creation,
refresh/reuse only relevant supported evidence, direct fallback on cache failure,
and semantic equivalence between supported direct/cache paths. A successful direct
fallback is a performance advisory. Query snapshot-only support requires the
versioned evidence described below; legacy evidence never implies compatibility.
Queries with exclusions use direct, pruned discovery rather than refreshing a
directory cache that cannot represent those exclusions.

## Results and context

Use a versioned report with query, scope, execution, summary, results, and
diagnostics. Pin remaining wire-field names with behavioral fixtures during
implementation; the information contract below is selected.
Results are nested under `results`; frontmatter output preserves dump's three
categories: frontMatter, noFrontMatter, and emptyFrontMatter, containing matches
only. Always use collection output, including zero or one match.

Missing-key queries can match absent/empty frontmatter. Path-selected rules and
types without frontmatter requirements can also match these documents. Ordinary
property equality does not match them.

Dump currently inserts provenance as `$path` inside each mapping, overwriting a
user-authored `$path`. In dump's generated JSON, `$path` is reserved output metadata
derived from the actual file path. That does not globally reserve the name in a
YAML/TOML source mapping; the codec currently permits that literal property. The
earlier example of a user-authored `$path` illustrated this distinction, not a
change to dump's metadata contract. The owner approved query entries wrapping
`path` and `frontmatter` separately, with per-property typed evidence. Changes to
existing dump JSON are a separate compatibility decision. Reuse collection
assembly without invoking dump or reparsing matched files.

Use `results.paths` for a path array and `results.count` for the matched document
count. Frontmatter entries have path, frontmatter, and optional valueMetadata.
The metadata object is keyed by escaped JSON Pointer location and supplies kind
plus source components/spelling where needed to retain information absent from
ordinary JSON. Preserve numeric stored-kind distinctions and native temporal
kind/authored-offset evidence. A non-finite number projects to the canonical
string NaN, Infinity, or -Infinity, with metadata `{kind: number, special: nan}`,
`{kind: number, special: positive-infinity}`, or
`{kind: number, special: negative-infinity}` respectively. Thus authored strings
remain distinguishable from projected numeric special values. Concrete encoder
field tests must preserve this approved information contract.

`results.unavailable` is approved for confirmed matches whose frontmatter cannot
be rendered. Preserve each path and reason code, mark the report incomplete, and
do not misclassify these files as absent/empty. Their membership is known even
though requested output is unavailable; membership-unknown files stay diagnostics.

Include captured argv, working directory, and a shell-quoted display command.
Structured supplied options should mirror CLI names; distinguish them from
effective defaults/resolved settings. An argv array is authoritative for received
arguments; the original shell spelling, quoting, expansions, or aliases cannot
be recovered. Implement reusable invocation capture/formatting at the CLI layer,
independent of query/survey, reusing their existing compatible quoting helpers.

Scope records supplied files/folders/lists, root, recursion, exclusions, and file
inclusion policies. Execution records CLI/report versions, UTC start/end times,
duration, completion, and actual evidence provenance. Identify used configuration
and type/rule dependencies and their available revisions. Distinguish snapshot
generation/publication time from query execution time; do not claim an atomic
filesystem snapshot merely from recording a start time.

Summary distinguishes matches, nonmatches, unknowns, and skips. Report bounded
diagnostic omissions explicitly. Preserve context for JSON count output.

The owner directed reuse of survey budgets. Use 100,000 selected text files,
64 MiB per source file, 256 MiB aggregate source bytes, and the existing separate
metadata traversal guard of max(100,000, 4 * maxFiles), with checked arithmetic.
Attachments/filtered host kinds do not consume selected-text budgets. Snapshot
evidence reads retain the existing 256 MiB aggregate evidence budget. File-list
inputs retain the existing bounded 64 MiB UTF-8 input handling.

Reuse survey's default `--limit 20`; `--limit 0` requests all. This supersedes the
earlier proposed query default of all matches. Limits only bound returned match
lists while evaluation continues for full counts; count output is unaffected.
Report matched, returned, and omitted counts separately. Sort case-sensitively by
project-relative path and return absolute paths. Disclose omitted matches in JSON
and on stderr for plain/NUL path output; a display cap alone is not incompleteness
and never makes the command fail. Execution budget exhaustion retains its separate
incomplete-result behavior. Query must reuse shared budget definitions rather than
introduce drifting copies of survey constants.

`--diagnostic-limit 100` means at most 100 diagnostic entries in the
JSON diagnostics list, not 100 files, matches, or inspected values. A file may
produce several distinct entries. Keep full aggregate diagnostic counts and
unique affected-file counts separately; disclose omitted entries. It does not
limit evaluation or change completion/exit status. Zero requests all entries
within execution budgets. The owner accepted this display cap: exceeding it only
truncates the list and never fails the command or makes a complete query incomplete.

`--print0` is approved only with path output in text mode. Emit exact paths
separated by NUL, without a stdout summary. Ordinary text path output visibly
escapes newlines/control characters; JSON/NUL output preserves actual path data.
Incompatible output/format combinations fail preflight.

Human output uses a dedicated renderer. Keep JSON stdout parseable; send progress
and human diagnostics to stderr. Help leads with purpose and exact-value filtering,
then wildcard/date examples, and links to focused detailed documentation. Resolve
invalid flags/operands before expensive work; do not require interactive prompts.

### Delayed progress

Query filtering must share survey's progress infrastructure and behavior. Extract
the reusable phase-feedback component from `SurveyProgress` rather than duplicate
it. After a one-second delay, report changed phases on stderr using the same
`Please be patient.` prefix; quick commands produce no progress. Support
`--no-progress`. Use discovered/processed counts already available to execution,
never another discovery/read/analysis pass or an invented percentage.

Examples of phases are discovering files, refreshing/reading cached evidence,
evaluating the requested condition against discovered files, and preparing
results. Phase/count changes are rate-limited, without repeating unchanged
messages. Keep stdout valid in JSON/NUL modes. The progress worker is a structured
child task: stop/cancel and join it before final rendering, including failure and
cancellation, so feedback cannot appear after completion. No automatic log file
or telemetry is introduced. Relationship aliases retain their existing behavior.

## Relationships and reuse

`query relationships` / `query rel` should expose the existing group with its
outgoing/out, incoming/in, and both children. Reuse the same implementations,
flags, output, scope, and exit semantics. Discoverability is the only difference;
do not silently wrap relationship results in a new report or alter their flags.

Reuse record analysis requirements, typed observations derived from an existing
analysis, rule applicability, type assessment, and DynamicJSON selection. Plan
requirements before processing records; share one required analysis per file
between predicates/output, avoiding a separate survey observation parse. Reuse or
extract compatible scope traversal rather than duplicating it. Discovery must not
perform an analysis that evaluation immediately repeats.

Outgoing relationships provide lazy dependency loading/memoization and consumed
evidence checks. Preserve those optimizations and legitimate freshness rereads.
The existing YAML native-temporal evidence pass composes a second YAML tree;
sharing one analysis is not yet a guarantee of one underlying YAML parse. Improve
that shared path instead of introducing an incompatible query-only parser.

### Shared snapshots with requested evidence

Extract the survey-specific snapshot infrastructure into a shared native
snapshot reader/service used by query and survey. Each caller declares only the
evidence its operation requires. Keep portable evidence/requirement models separate
from native SQLite access and CLI options; exact Swift type names remain an
implementation choice.

Requirements may include coverage/status, source identity/revision and format,
frontmatter key inventory, selected typed values, full frontmatter for output,
lossless temporal components, or supported published type/rule assessment evidence.
Plan the union once for all requested metrics or predicate/output needs. A query
counting one key should not load bodies, headings, unrelated contract assessments,
or full frontmatter solely to discard it. A frontmatter-output query requests
the complete mappings it needs. Survey keys/values/coverage similarly request
only their own evidence. Wildcard projections retain required ancestor/container
and source-location evidence.

Make projection effective at the storage/read/decode boundary, not just by
discarding fields after decoding full observations. Preserve one committed
generation and matching revisions across incremental projected reads. Version
published capabilities, expose missing requested evidence explicitly, and never
fill a snapshot-only gap with filesystem reads. Preserve shared refresh/direct
fallback and cancellation rules; requirements do not authorize hidden refresh.

The current whole-observation `detail` JSON layout may require a shared publication
layout/projection change to realize these savings. Test actual requested reads,
decodes, and analysis counts, with full-versus-projected outcome equivalence and
survey regressions; do not claim reduced runtime work from a renamed wrapper.

The owner approved the following v1 snapshot-only coverage:

| Predicate family | Approved v1 snapshot-only coverage |
| --- | --- |
| Presence/null, typed equality/inequality, array membership, numeric bounds/ranges | Supported with query-compatible published typed frontmatter evidence |
| Supported literal/JSONPath selectors and any/all | Supported over the same evidence |
| Semantic string formats, including UUID and wikilink text comparisons | Supported from published original strings; no link resolution |
| Calendar/temporal comparisons on strings or native values | Supported when versioned evidence includes the required precise components, native kinds, and authored offsets |
| `--is-type`, `--in-rule` | Defer snapshot-only support in v1; ordinary queries still support them |

This supports all frontmatter-only condition families and defers type/rule
assessment conditions. Published capability/version checks determine whether a
particular index has sufficient evidence; legacy lossy temporal projections are
not silently treated as compatible. Relationship aliases retain existing support.
The coverage inventory and shared projection requirements are settled.

## Verification and remaining work

Human-readable paths, counts, frontmatter labels, empty states, warnings, and
shared progress use the existing `CLIStyle`/Rainbow infrastructure. JSON and
NUL-delimited paths bypass styling. Existing terminal detection and color
environment conventions remain unchanged.

Red-green behavioral tests live in `MarkdownQueryTests` and `QueryCommandsTests`.
The native suite verifies shared parser/index regressions. Coverage includes typed matching,
wildcard empty/any/all behavior, same-node ranges, shell argument preservation,
invalid preflight, temporal modes/defaults/DST, malformed/unreadable inputs,
category/result completeness, source/cache equivalence, projected snapshot
equivalence, boolean codec identity, case modes, tagged non-finite values, NUL path
output, delayed progress/opt-out/cancellation, and read/decode/analysis budgets.

No product-design approval decisions remain for v1. Value matching was delegated
and selected above; the entry/typed-evidence model and snapshot-only inventory are
approved, and execution/display budgets follow the owner's survey-reuse direction.
Wire-field fixtures, Unicode/numeric precision, DST cases, parser checks, and
projection/read measurements are covered by the query suites. Linux verification
remains CI-only; WASM verification remains deferred under the project policy.

Executable/parent help and canonical/bundled Agent Skill references include query.
Survey value hints now use native query commands, preserving case and scope.
No user-installed skill directory is changed; export the bundled skill through
`md-utils agents skill` when updating an installation.

## Future enhancements (outside v1)

- Native date/value sorting and top-N results, including deterministic ties,
  missing/invalid dates, and explicit calendar-versus-instant ordering. The
  latest-sermon investigation demonstrates this need; `--limit` remains a display
  cap in path order until an ordering contract is designed.
- General AND/OR composition, for example a sermon tag plus a date interval.
  Preserve the current single-condition contract until composition is explicit.
- Expanded JSONPath features and an optional JMESPath selector, with bounded
  evaluation and clearly documented missing/unknown semantics.
- Snapshot-only type/rule assessment once published evidence carries the required
  definitions, revisions, and applicability/conformance capabilities.
- Additional temporal coercion/reference policies, including explicit conversion
  from a date to an instant; never infer midnight silently.

These are follow-up opportunities, not required completion criteria for #203.
Future report changes should version capabilities/schema deliberately and preserve
argv provenance, partial-result semantics, machine output, and bounded execution.
