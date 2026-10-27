# Folder survey (#200)

Status: native implementation with red-green tests. Verification and current limits
are recorded in [survey-test-requirements.md](survey-test-requirements.md).
Survey describes observed practice and routes investigation to existing commands.
It does not make conventions into contracts or silently validate every rule.

## Commands

`md-utils survey [paths...]` is the overview, also available as `survey overview`.
Focused commands: `coverage`, `malformed-fm`, `keys`, `key <key>`, `values <key>`,
`rules`, `types`, `standards`, `uncovered`, `overlaps`, `type-matches`, and
`relationships`. Every command accepts selected paths and JSON output.

The overview includes coverage, relevant rules, referenced/local types, common
keys, findings from those computations, and investigation hints. Standards appear
only when supported. Expensive type matching and relationship assessment are
explicit metrics. `--metrics` selects comma-separated metrics, is repeatable, and
replaces defaults. Parameterized key/value inspection uses focused commands.

## Scope

Paths select a deduplicated union of files and recursive directories. Without
paths or file-list inputs, select the current directory. Include Markdown and
supported other UTF-8 text files. `--markdown-only`, `--no-recursive`, repeatable
`--exclude`, `--files-from`, and `--files-from0` refine this scope. CLI paths are
working-directory-relative; file-list entries are project-root-relative. File
lists alone must not add the working directory. One project root confines inputs;
`--project-root` and `--config` retain project resolution conventions.

Hidden directory entries and symlinks are skipped, with an explicit coverage note
in text and JSON. Configured internal definitions may still load from `.md-utils/`.
Do not count descendants of directories that were never traversed. Encoding,
unsupported host syntax, malformed frontmatter, absence, and unreadable files are
different outcomes. Preserve existing frontmatter delimiter/newline contracts.

## Statistical semantics

Count documents containing keys, not occurrences. Rank top-level literal keys by
descending prevalence and then lexical order. `--top` defaults to 10, with 0 for
all. `--min-files` defaults to 1 for keys, 20 for outlier detection. `--limit`
defaults to 20 detailed rows, with 0 for all. Display limits never sample inputs;
report total and omitted counts separately.

`key` and `values` take literal property keys, including periods and slashes.
`--pointer` interprets the argument as JSON Pointer, with concrete array indices
and no wildcard expansion. Preserve missing/null, boolean/integer/number/string,
array/object, and native temporal evidence. Do not collapse these through lossy
JSON cache representations. `key --outliers` uses a dominant-kind share of 0.95
(`--min-share`) among at least 20 assessable files containing the key; missing
keys are separate. Report effective thresholds and denominators.

`values` reports typed distinct values, frequencies, proportions, and remainder.
Arrays are whole values unless `--elements` is explicit. Elements count distinct
documents by default; `--count occurrences` counts repeated immediate elements
and requires `--elements`. Non-arrays and empty arrays remain visible. Preserve
array order and ignore object mapping order for equality. Never conflate `"1"`
with `1`. Literal fields remain distinct from nested pointer paths.

## Contracts and relationships

`rules` reports applicability and referenced types without full validation.
`types` inventories definitions, distinguishing local presence from reference;
always explain the optional `type-matches` investigation and its cost.
`type-matches` assesses selected files against discovered or explicitly named
types; conformance is not evidence of intended usage. `--type` and `--rule` select
reported contracts, not the input population. `uncovered` reports confirmed zero
rule matches; `overlaps` reports at least two. Unknown applicability is separate.

`relationships` summarizes outgoing named assertions and ordinary links using the
existing collection query infrastructure. Group by declaring type/relation, retain
self-links and incomplete coverage, and distinguish selected-folder boundaries
from the project destination namespace. Do not claim non-Markdown coverage not
supported by the relationship engine. Offer existing directional commands for
deeper investigation rather than duplicate their API.

## Cache, reporting, and completion

Follow [index-cache-policy.md](index-cache-policy.md). Ordinary reads reuse an
existing cache, refresh requested evidence, warn/fall back on cache errors, never
create an absent index, and propagate cancellation. `--no-index` bypasses it.
`--index-only`/`--indexed-only` use only published SQLite evidence and reject
`--no-index`/`--verify-hashes`; never fill missing evidence with source reads.

All outputs include coverage. JSON is versioned and includes scope, requested
metrics, per-metric completion, execution provenance/snapshot, findings, display
truncation and hints with argv/working directory/scope notes. Warnings use stderr.
`--no-hints` suppresses hints, not coverage limitations.

Exit 0 means the requested analysis completed, even with malformed frontmatter or
outliers. Exit 1 means execution or required evidence is incomplete; retain partial
results. Invalid usage follows the existing ArgumentParser exit 64 convention,
replacing the proposed exit 2 to preserve project consistency. Malformed files are determined findings for
`malformed-fm` and explicitly unassessable inputs for key statistics. Unreadable
files prevent completion. Snapshot missing evidence is unavailable, never empty
success. Cancellation does not trigger fallback.

Hints are executable and correctly quoted, preserve scope/configuration, and
disclose broader rule-validation scope. Reuse `rules describe`, `rules validate`,
`rules matching --explain`, and `rel out/in` where appropriate.

## Deferred standards

`survey standards` has an explicit unsupported result until the standards runtime
is available. Functional standards support is a separate dependency, not a
completed feature. No definition/adoption format is invented for survey.

## Delivery

Write behavioral requirements and failing tests before production changes; then
implement and record red/green evidence. See [survey-test-requirements.md](survey-test-requirements.md).
Update canonical `references/survey.md`, route from `SKILL.md`, synchronize bundled
resources, exercise real CLI help/examples, and run skill validation. Do not close
#200 until all applicable criteria are verified and deferred work is tracked.
