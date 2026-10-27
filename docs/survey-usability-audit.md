# Survey usability audit — 2026-10-27

Implementation follow-up: the owner approved the first pass covering delayed
counted progress, compact text overview, relevance ordering, and hint limits.
Those changes are implemented; detailed evidence is in
`survey-test-requirements.md`. Subsequent approved work adds compact rule coverage,
structured per-file uncertainty, discovery hints, and missing-input failure before
evaluation. Summary-first types/type-matches/relationships/uncovered/overlaps and
the standalone standards fast return are also implemented. The observations below
retain the original audit results. Shared bounded file issues and same-scope
investigation hints, key prevalence, and evidence-based relationship hint selection
are now implemented. Shared record analysis improves the measured contract-survey
bottleneck about 6× with equivalent results (see `survey-performance.md`). Further
performance work remains possible follow-up work. Compact JSON is now available
through --format json, with --format json-pretty for indented reports. Historical
command transcripts below use the former --json flag.

The original audit below is a proposal and execution record. The owner
requested concise orientation for people and agents, testing both text and JSON
on the real Notes collection. Applied the local `better-cli` skill's help,
output/automation, and performance review guidance. Networking, telemetry,
installation, and mutation design were outside scope. No full test suite was run.

## Dataset and method

- Root: `~/Sites/Notes/`. A separate filename inventory found **26,465 visible
  regular files**, including **26,019 Markdown files**. Hidden entries and
  symlinks were excluded; this inventory did not classify file contents.
- A completed full-root `survey coverage --no-index --json` reported **26,241
  text files**, **224 non-text skips**, **25,281 parsed frontmatter blocks**,
  **760 files without frontmatter**, **200 unsupported frontmatter hosts**,
  zero malformed frontmatter, and zero unreadable files. The counts reconcile.
- Tried the default invocation plus all thirteen subcommands in both formats.
  Whole-root responsiveness probes use `--no-index` and a 12-second bound;
  timeouts are **not** classified as command failures or completed surveys.
- Earlier default text/JSON runs, both with ordinary indexing and direct reads,
  were each interrupted at 45 seconds with **zero stdout and zero stderr**.
- Longer full-root `keys` and `values` runs completed in both formats. Whole-root
  coverage also completed when allowed longer than the short probe limit.
- For result inspection, ran the complete matrix on `Topics/Inputs/`, with 522
  text files and four non-text skips. Unrestricted type matching exceeded the
  30-second bound in both formats; `--type books` completed in both formats.
- Captured stdout, stderr, return status, output size, and first-output latency.
  Some direct runs overlapped: timings are rough usability evidence, not controlled
  benchmarks. JSON was parsed for each completed matrix JSON run. Cached-read
  probes may refresh the existing disposable index; no source documents were edited.

## Observations by command

The following timings and output lengths use the Inputs subfolder unless noted.
“Incomplete” means a report was returned with exit 1, not that it timed out.

| Command | Text / JSON seconds | Text / JSON lines | Assessment |
| --- | ---: | ---: | --- |
| default / overview | 10–11 / 10.4 | 309 / 781 | Four default metrics complete; rules incomplete for one file. Too long for orientation. |
| coverage | 0.47 / 0.47 | 13 / 95 | Text is concise; JSON duplicates coverage and includes irrelevant parameters. |
| malformed-fm | 0.46 / 0.47 | 17 / 84 | Correct successful empty result; should lead with “No malformed frontmatter found.” |
| keys | 0.47 / 0.46 | 56 / 365 | Ten useful key rows followed by ten repetitive hints. |
| key Status | 0.46 / 0.47 | 25 / 108 | Useful counts; missing prevalence percentages and a reason/path for the unassessable file. |
| values Status | 0.48 / 0.46 | 31 / 200 | Good distribution table and single investigation example; verbose headers and awkward count labels remain. |
| rules | 10.64 / 10.72 | 156 / 321 | Reports 42 rules, limits to alphabetically first 20, including many zero-selection rules. |
| types | 10.46 / 10.40 | 137 / 292 | Inventory triggers rule-selection work and six rule-validation hints. |
| standards | 0.47 / 0.47 | 14 / 78 | Scans sources before returning the known unsupported result; whole-root short probes time out. |
| uncovered | 10.34 / 10.33 | 81 / 190 | Preserves unknown selection, but a long path list and unrelated validation hints obscure the headline. |
| overlaps | 10.39 / 10.35 | 36 / 161 | No confirmed overlaps, one unknown file; six validation hints dominate the empty finding. |
| type-matches | >30 / >30 | no output | Silent until interruption; targeted `books` reports 177 pass, 344 fail, one unavailable. |
| relationships | 12.26 / 12.15 | 152 / 263 | Incomplete interpretation evidence; headline counts appear after lengthy edge details. |

Whole-root `keys` completed in **18.45 s text / 18.44 s JSON**; `values Status`
completed in **18.07 s text / 17.85 s JSON**. Both returned successful reports.
The latter found Status present in 1,131 files, missing in 24,910, with 200
unassessable files; eleven distinct values, ten shown, one omitted.

## Recommended changes, in priority order

### 1. Give slow commands immediate, truthful feedback

**Evidence:** ordinary and direct default runs remained silent for 45 seconds;
even successful simple root queries waited roughly 18 seconds before output.

Proposed stderr flow, after a short delay (approximately 0.5–1 second):

```text
Please be patient. Discovering files…
Please be patient. Analyzing 26,465 selected files…
```

Use the **actual selected count** after recursion/exclusions/deduplication and
scope filtering. Do not call this a text-file count until content classification
has happened. Once known, a later phase can say:

```text
Analyzing metadata in 26,241 text files; 224 non-text files skipped.
Checking 42 rules against 26,241 text files…
```

Count during the same discovery pass and reuse the discovered inputs. Avoid an
extra recursive scan solely for progress. Until discovery finishes, report a
running “files found” count or omit a denominator. Snapshot-only commands must
derive progress from stored evidence, never scan sources to obtain a count.

Keep quick runs quiet. Use one concise line per slow phase for redirected stderr;
an interactive terminal may update a single line. Keep stdout completely clean
for JSON. Consider an explicit progress-suppression option, with its spelling and
default settled before implementation. Do not add repeated “still working” lines.

**Verification:** delayed discovery, known-count analysis, text/JSON redirection,
non-text exclusion, cancellation, and snapshot-only execution. Confirm that
feedback precedes completion and that reported counts reconcile with final scope.

### 2. Make the default overview a summary, not concatenated detailed reports

**Evidence:** the Inputs overview is 309 text lines / 21,544 JSON bytes; 17 hints.
It prints rules and types before the common metadata keys.

Target roughly one screen: collection size/coverage, five-to-ten common keys,
relevant contract counts, important limitations, and at most two or three next
steps. Order information by usefulness for orientation. Keep detailed inventories
in their dedicated subcommands. Offer an explicit detail expansion if needed;
do not silently truncate evidence without a total and a way to inspect it.

For agents, retain a stable result shape and completion information. Do not change
JSON meanings merely to match a more compact human overview.

### 3. Rank rules by relevance and separate type inventory from applicability

**Evidence:** rules includes all 42 configured rules, ordered by name; the first
20 contain many with Selected: 0. Types spends roughly ten seconds on 522 files
and offers six rule-validation hints because inventory also computes rule coverage.

Default rule presentation should prioritize selected and indeterminate rules;
report the number of other configured rules separately. Use compact columns for
rule, selected count, unknown count, and referenced types. Types should distinguish
referenced definitions, definitions found in scope, and other configured types.
Keep all categories discoverable without implying unused definitions are errors.

Cache or reuse applicability evidence, and analyze each record once for compatible
requirements instead of repeatedly for each rule. Inspect
`SurveyContracts.populate` before promising a speedup; observed timings alone do
not isolate the cost of parsing versus rule evaluation. The slow default path
should not block already-computed basic metrics from being useful.

### 4. Limit hints by relevance, not by the detailed-row limit

**Evidence:** keys emits ten nearly identical follow-ups; overlaps emits six
validation hints despite zero confirmed overlaps; types emits unrelated validation
hints. Several suggestions are more expensive than the query that produced them.

Use one representative key/value example, plus a short instruction to substitute
another name. Prioritize structural differences such as array-versus-string over
routine null-versus-string mixtures, without assuming null is always allowed.
Give overlap/uncovered commands hints about their own findings. Keep a small,
separate hint budget. Retain structured `argv`, `pipeTo`, working directory, and
scope cautions in JSON; do not generate every possible command.

Carry applicable execution flags such as `--no-index` into follow-up survey
commands. Observed hints currently omit it and may return users to the slow cache
path. Do not copy flags to commands that do not support them.

### 5. Explain incomplete metrics at the top, with actionable evidence

**Evidence:** overview JSON correctly reports coverage/keys/types/malformed-fm
complete and rules incomplete. Human output ends with “Rule applicability is
unavailable for 1 file(s).” Uncovered identifies `Topics/Inputs/Inputs.base`;
coverage only reports an unsupported count. Whole-root coverage reports 200
unsupported files without a route to inspect them.

Add a short headline such as “Metadata survey complete; rule coverage incomplete
for one unsupported file.” Include bounded example paths, reason codes, affected
metrics, and an actionable inspection command. Distinguish unsupported host syntax
from malformed frontmatter and I/O failure. Provide a dedicated discovery route
for unsupported/unassessable inputs if existing commands cannot supply one.

Preserve honest per-metric status and existing exit semantics pending an explicit
design decision. Do not silently treat unknown applicability as non-selection.
For agents, use structured limitations with paths/metric/code alongside readable
messages rather than requiring them to parse English strings.

### 6. Give relationships a relationship summary before edge evidence

**Evidence:** Inputs prints 152 text lines. Useful totals appear near the bottom:
903 distinct ordinary links, 1,101 resolved occurrences, 323 unresolved
occurrences, 100 resolved occurrences targeting inside the selection and 1,001
outside. Twenty detailed edges appear first. Zero named groups is shown while
interpretation evidence is incomplete.

Lead with those counts and label their units explicitly: unique edges versus
occurrences, source scope versus resolution namespace. Group named relationships
by type/relation in a compact table. Show only a few representative edge examples
by default. Label zero named groups as **observed under incomplete evidence**, not
proof that none exist.

Fix embedded notices that say “Use --detail explain.” Reproducing that option on
`survey relationships` yields “Unknown option '--detail'.” Supply a full valid
`md-utils relationships ... --detail explain` hint using a source that actually
demonstrates the unresolved/limited evidence, not simply the alphabetically first
file. Preserve structured notice codes for agents.

### 7. Make type matching navigable and visibly opt-in at large scale

**Evidence:** unrestricted Inputs matching exceeded 30 seconds without feedback;
targeted `--type books` completed with pass/fail/unavailable results. Its expanded
file lists place the type name after the outcome block in generic sorted rendering.

Lead with a table of type, assessed files, passing, failing, and unavailable counts.
Put type identity first. Provide a short file sample and a concrete refinement
hint; leave full lists to explicit detail. Report actual number of selected types
and files during analysis. Do not invent a required runtime estimate, classify
structural matches as declared usage, or silently sample.

### 8. Fail fast for unsupported standards

**Evidence:** `standards` is unconditionally unsupported, but performs discovery
and parsing first. Whole-root text and JSON probes spent their entire 12-second
budget without reaching that known result.

After validating the request, return an immediate explicit unsupported result and
the #202 follow-up. For mixed overview metrics, mark standards unavailable while
continuing supported metrics. Do not report fabricated coverage for unscanned
files. Verify that the standalone placeholder performs no content reads.

### 9. Reduce JSON redundancy without breaking current consumers

**Evidence:** coverage is repeated under both `coverage` and `metrics.coverage`;
keys repeats outlier thresholds and empty arrays on each row even without outlier
analysis. Every metric includes parameters for unrelated modes. Empty maps/arrays
are spread across multiple lines. The compatibility alias `skippedBinary` is
intentional and currently duplicates `skippedNonText`.

Offer compact JSON serialization for token-sensitive agents without changing its
data shape. Plan a versioned schema cleanup separately: shared coverage once,
metric-specific parameters, typed limitations, explicit denominator/units, and
consistent result truncation. Preserve complete/no-match/unsupported distinctions
and structured hints. Do not remove existing fields or aliases without a
compatibility decision.

### 10. Add prevalence and improve small presentation details

**Evidence:** whole-root keys has 465 distinct keys but shows counts without
prevalence. `Status` covers only a small fraction of the full collection, which is
useful orientation. Text currently includes “Could not assess: 1 files” and
“omitted: 0 (0 counts).” Generic tables put item numbers on their own lines and
show false/true for facts that could be expressed more naturally.

Show key prevalence with an explicit assessable-file denominator. Group null
separately from non-null kind variation. Use metric-specific empty-result messages,
compact path lists, singular/plural grammar, and “one additional value omitted”
with a recovery command. Avoid suggesting that display limits reduced the scan.

## Suggested implementation order

1. Counted progress, fast unsupported response, and valid relationship follow-ups.
2. Compact overview, relevance ordering, and a small independent hint budget.
3. Actionable per-metric limitations and summary-first relationships/type matching.
4. Shared extraction/applicability work and reusable non-text cache observations.
5. JSON compact serialization now; schema cleanup only through an explicit
   compatibility/versioning decision.

Changes to defaults, new flags, result shape, or exit contracts remain proposals
requiring the owner's review under the project's Better CLI policy.

## Evidence and limits

Raw collection-derived output is kept in ignored project `tmp/`, not embedded in
this document. Local evidence:

- `tmp/survey-notes-audit/`: 45-second ordinary default probes.
- `tmp/survey-notes-audit-direct/`: 45-second direct default probes.
- `tmp/survey-notes-audit-probes/`: bounded whole-root command/format matrix.
- `tmp/survey-notes-audit-inputs/`: completed subfolder results and type-match timeouts.
- `tmp/survey-notes-audit-root-completed/`: completed root keys/values runs.
- `tmp/survey-notes-root-coverage.json`: complete whole-root coverage.
- `tmp/survey-books-matches.json` and `.txt`: targeted type matching.
- `tmp/survey-relationship-detail.err`: rejected partial investigation hint.

No unrestricted full-root contract/relationship completion time is claimed.
Silence was measured through redirected stdout/stderr, not an interactive TTY.
The whole-root coverage runtime was not timed by the matrix harness and is not
presented as a precise benchmark. Cache cancellation left no source edits; no
index-only freshness or Linux/WASM validation is claimed. All proposed changes
need focused implementation tests before adoption.
