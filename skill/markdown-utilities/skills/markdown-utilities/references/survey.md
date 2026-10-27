# Survey a collection

Use survey to get oriented before validating or editing documents. Observed
conventions do not create requirements. All examples assume the working directory
is the project root; supply `--project-root ./vault/` otherwise.
The default text overview is compact: coverage, up to five common keys, leading
rules/types, and at most three hints. Dedicated subcommands and JSON retain detailed
results. Rules rank by selected files, then unknown applicability, then name;
types referenced by applicable rules rank before locally discovered and other
configured definitions. Display limits apply after ranking.
Use `md-utils help survey` for the command group; `survey --help` describes the
default overview and lists the available subcommands. Each
`md-utils survey <subcommand> --help` page explains its purpose, gives starting
examples, and documents scope, configuration, cache behavior, and exit status.

```bash
# Overview and explicit metric selection.
md-utils survey ./knowledge/
md-utils survey ./knowledge/ --metrics coverage,keys

# Investigate metadata syntax, conventions, and informal vocabularies.
md-utils survey malformed-fm ./knowledge/ --fm-format yaml
md-utils survey key tags ./knowledge/ --outliers
md-utils survey values status ./knowledge/
md-utils survey values tags ./knowledge/ --elements

# Separate definition inventory from optional conformance assessment.
md-utils survey types ./knowledge/
md-utils survey type-matches ./knowledge/ --type Article

# Explore rule coverage and outgoing relationships.
md-utils survey ./knowledge/ --metrics rules,uncovered,overlaps
md-utils survey relationships ./knowledge/

# Structured output and strictly published snapshot findings.
md-utils survey keys ./knowledge/ --format json
md-utils survey malformed-fm ./knowledge/ --index-only --format json
```

## Scope and properties

Scope is a deduplicated union of recursive directories and explicit files within
one project root. It includes Markdown and supported other UTF-8 text files.
Hidden entries and symlinks are skipped with a visible note; configured definitions
inside `.md-utils/` may still load. Unsupported host syntax, absent frontmatter,
malformed frontmatter, non-text files and unreadable files are distinct outcomes.
Recognized non-text attachments are skipped before text-size budgets are applied;
their presence does not make the survey incomplete. Large text files still obey
the read budgets. `survey key` text output summarizes presence, absence, and kinds.

Use `--markdown-only`, `--no-recursive`, and repeated root-relative `--exclude`
paths/globs to narrow scope. `--files-from` and `--files-from0` accept UTF-8 LF/NUL
lists of root-relative files (`-` reads stdin once). File lists alone do not add the
current directory. With no inputs, select the current directory. `--config`
selects a nonstandard project configuration.

`keys` ranks literal top-level keys by document prevalence. `key <key>` reports
presence, missing/unassessable counts and kinds. `values <key>` reports typed value
frequencies. Dots and slashes are literal unless `--pointer` is explicit:

```bash
md-utils survey key '/author/name' ./knowledge/ --pointer
md-utils survey values '/ingredients/0/unit' ./knowledge/ --pointer
```

Null differs from missing; strings, numbers and native temporal kinds remain
distinct. Arrays remain whole values unless `--elements` is selected. Elements
count each document once per distinct value; `--elements --count occurrences`
counts repetitions. Non-arrays and empty arrays are reported separately.

`--top` defaults to 10 ranked entries; `--limit` defaults to 20 detailed rows.
Zero means all. These limit presentation, not scanned inputs; omitted counts are
explicit. `--max-files` defaults to 100000; exhaustion is incomplete. Reads also
have per-file and total memory budgets.

`key --outliers` requires at least 20 assessable files containing the key and a
95% dominant kind. Adjust with `--min-files` and `--min-share`. Missing keys are
separate. `keys --min-files` filters the key inventory (default 1).

## Contracts and investigation

`survey keys` and `survey key` show prevalence against assessable files
(`present + missing`), including files without frontmatter. Null values count as
present; malformed/unsupported/read-failed files do not enter the denominator.
Key summary JSON adds `assessable`, `presentProportion`, and `missingProportion`
(fractions from 0 to 1). With no assessable files proportions are null and text
shows N/A. Percentages are rounded to one decimal only for human output.
Relationship investigation hints prefer sources with unresolved/ambiguous/malformed
link evidence, then unavailable named assessments, then a source with observed
links. Selection precedes display truncation; type and cache options are retained.

`survey keys` and literal `survey key` include one `fm has --key NAME <folders>`
hint using the surveyed paths and supported recursion/exclusion options. Look for
true in the per-file output to find files with the key, including null values;
false means absent, not a failed command. Supported mapped non-Markdown formats
are included unless Markdown-only was requested. Substitute another key.
Pointer, file-list, and snapshot-only surveys omit this folder hint. Existing
hint limits and `--no-hints` still apply.

Human survey reports use the CLI's shared Rainbow/CLIStyle colors for headings,
table labels, counts, paths, hints, and scope notes. Existing terminal detection
and `NO_COLOR`/`FORCE_COLOR` behavior apply; redirected reports remain plain under
normal detection. JSON is never styled. Color adds no new warning/error semantics.

Every survey report includes `fileIssues`: bounded `rows` with project-relative
`path`, `category` (`unsupported`, `malformed`, or `unreadable`), and `reasons`
containing diagnostic `code` and `message`. `total`, `omitted`, and category
`counts` describe the full observed scope. These are frontmatter/read observations,
not type-validation failures or proof that every metric needs the missing evidence.
Text shows three examples; `--limit 0` expands all. Follow the generated
`survey coverage ... --format json --limit 0 --no-hints` command to investigate the same
scope. `--no-hints` retains diagnostics. Non-text skips and absent frontmatter are
not file issues. Snapshot queries derive these findings from stored observations;
limitations without per-file evidence remain in `limitations`.

Focused `types`, `type-matches`, `relationships`, `uncovered`, and `overlaps`
reports lead with counts/tables. File and edge examples are capped at three by
default; `--limit 0` expands them. Type matching samples the first displayed type;
use `--type NAME` to investigate another. JSON retains bounded detailed evidence
and totals regardless of the human presentation. Uncertain coverage is not proof
that no relationships or overlaps exist.

`rules` describes selection and referenced types without full validation.
Human output leads with rule coverage and a compact table, hiding confirmed
zero-match rules behind a count. JSON retains detailed rule rows and adds `summary`
and bounded `uncertainties` (path, rule, diagnostic codes/messages). Summary counts
distinguish unique uncertain files from rule/file pairs; `assessmentComplete`
indicates whether every selection was decidable. Uncertain rule selections are
successful survey findings, not execution failures. Use `--limit 0` for all details.
Missing explicit input paths fail before discovery or rule evaluation; snapshot-only
queries continue to use published evidence without checking source paths.
`uncovered` reports confirmed non-selection; `overlaps` reports multiple matches.
Unknown applicability remains separate. `types` inventories configured/discovered
definitions; `type-matches` explicitly assesses conformance, which does not prove
intended usage. `--rule` filters rule inventory; `--type` filters types or matching.

Follow generated `rules describe`, `rules matching <file> --explain`, and
`rules files-matching <rule>` hints before validation. Matching uses a concrete
surveyed example file; files-matching lists the rule's full project selection,
including files beyond the survey folder or exclusions. Named-rule commands can
extend beyond the surveyed folder. Survey never repairs documents. Relationship
surveying summarizes outgoing Markdown evidence within the full project namespace;
non-Markdown relationship coverage is excluded explicitly. Detailed directional
investigation belongs to [Relationships](relationships.md).

`survey standards` says it is an upcoming feature and exits unsuccessfully.
When standards is the only requested metric, it does not scan source files or
touch the index: `source` is `not-run` and `coverageEvaluated` is false. Its zero
coverage counters are placeholders, not an empty-folder finding. Mixed metrics
still evaluate supported metrics and report standards as unsupported.
Functional support is deferred to [#202](https://github.com/DandyLyons/md-utils/issues/202).
Do not interpret unsupported as an empty standards inventory.

## Cache, JSON, and completion

All survey commands use `--format text|json|json-pretty`. Text is the default;
json emits one compact JSON document and json-pretty emits the same report with
indentation. `--json` is not accepted. For malformed-frontmatter syntax filtering,
use `--fm-format yaml|toml` independently of output format, for example:

```sh
md-utils survey malformed-fm ./knowledge/ --fm-format yaml --format json-pretty
```

Recursive directory surveys reuse an existing project index and refresh requested
scopes; no absent index is created. Contract metrics also read authoritative source
records. Explicit-file and nonrecursive surveys currently read directly. Cache
unavailability produces a performance advisory on stderr and falls back; cancellation stops. `--no-index` bypasses the
cache; `--verify-hashes` detects stat-preserving edits during indexed refresh.

`--index-only` (alias `--indexed-only`) reads published SQLite evidence only, without
source/configuration reads, freshness checks, refresh, writes or fallback. It rejects
`--no-index` and `--verify-hashes`. Missing extraction/coverage evidence stays
unavailable. Contract inventory, rule coverage and type matching do not yet have
survey snapshot projections and explicitly report unavailable. Relationships use
their existing published projection with its coverage limitations.

`--format json` emits one versioned report with scope, metric completion, provenance,
coverage, findings, truncation and hints. Diagnostics go to stderr. `--no-hints`
suppresses investigation hints, not coverage limitations.
Hints have an independent maximum of three; `--limit` controls detailed result
rows, not the hint budget. Keys show one representative mixed-kind investigation,
prioritizing non-null kind differences. Rule-validation hints are limited to one
relevant example on rules/overview, not unrelated inventory or coverage commands.
Follow-up survey commands preserve `--no-index` when supplied.

Slow CLI runs show phase feedback on stderr after one second, then only when the
phase changes. Known counts come from actual discovered text records, not an
extra scan or a prior snapshot. Discovery/cache refresh messages omit counts
until known; snapshot-only execution never scans sources for progress.
`--no-progress` suppresses these messages without hiding limitations or advisories.
Use `coverage.skippedNonText` for the skipped attachment count. Schema version 1
also retains `coverage.skippedBinary` as a compatibility alias with the same count.
Human output uses a value-distribution table and nested findings summaries for
contracts, malformed frontmatter, and relationships. JSON envelopes are exclusive
to `--format json` and `--format json-pretty`; individual structured property values can still use compact JSON
notation in the value column. Hints quote only shell arguments that need escaping.

For individual scalar values, ordinary unrestricted directory surveys offer one
`fm dump --format json | jq ...` example, preferring the most frequent non-null
value among displayed rows. Change the value to investigate others. `fm dump` reads supported Markdown and
mapped text frontmatter, including YAML and TOML; its traversal is distinct from
survey discovery. Output includes `$path` for provenance. For example:

```bash
md-utils fm dump ./knowledge/ --format json |
  jq --arg key Status --argjson value '"✅ Read"' '.frontMatter[] | select(has($key) and .[$key] == $value)'
```

These hints require `jq`. Structured hints retain the first command in `argv`
and add optional `pipeTo` for the second command's argument array. Connect the
first process's stdout to the second's stdin, use `workingDirectory`, and check
both exit statuses. Do not join unescaped arguments into shell code. Hints are
omitted for restricted/file-list/snapshot scopes, pointers, array elements, and
native temporal values where this pipeline would not preserve query meaning.

Exit 0 means analysis completed, even with malformed files or outliers. Exit 1
means incomplete execution/evidence; inspect partial results. Invalid usage follows
existing ArgumentParser behavior (exit 64). Malformed files are determined findings
and explicitly unassessable inputs for key statistics; unreadable files prevent
completion.
