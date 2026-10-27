# Survey a collection

Use survey to get oriented before validating or editing documents. Observed
conventions do not create requirements. All examples assume the working directory
is the project root; supply `--project-root ./vault/` otherwise.
Use `md-utils help survey` for the command group; `survey --help` describes the
default overview and lists the available subcommands. Each
`md-utils survey <subcommand> --help` page explains its purpose, gives starting
examples, and documents scope, configuration, cache behavior, and exit status.

```bash
# Overview and explicit metric selection.
md-utils survey ./knowledge/
md-utils survey ./knowledge/ --metrics coverage,keys

# Investigate metadata syntax, conventions, and informal vocabularies.
md-utils survey malformed-fm ./knowledge/ --format yaml
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
md-utils survey keys ./knowledge/ --json
md-utils survey malformed-fm ./knowledge/ --index-only --json
```

## Scope and properties

Scope is a deduplicated union of recursive directories and explicit files within
one project root. It includes Markdown and supported other UTF-8 text files.
Hidden entries and symlinks are skipped with a visible note; configured definitions
inside `.md-utils/` may still load. Unsupported host syntax, absent frontmatter,
malformed frontmatter, binary files and unreadable files are distinct outcomes.

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

`rules` describes selection and referenced types without full validation.
`uncovered` reports confirmed non-selection; `overlaps` reports multiple matches.
Unknown applicability remains separate. `types` inventories configured/discovered
definitions; `type-matches` explicitly assesses conformance, which does not prove
intended usage. `--rule` filters rule inventory; `--type` filters types or matching.

Follow generated investigation hints. A named rule's `rules validate` command can
extend beyond the surveyed folder. Survey never repairs documents. Relationship
surveying summarizes outgoing Markdown evidence within the full project namespace;
non-Markdown relationship coverage is excluded explicitly. Detailed directional
investigation belongs to [Relationships](relationships.md).

`survey standards` explicitly reports unsupported and exits unsuccessfully.
Functional support is deferred to [#202](https://github.com/DandyLyons/md-utils/issues/202).
Do not interpret unsupported as an empty standards inventory.

## Cache, JSON, and completion

Recursive directory surveys reuse an existing project index and refresh requested
scopes; no absent index is created. Contract metrics also read authoritative source
records. Explicit-file and nonrecursive surveys currently read directly. Cache
errors warn on stderr and fall back; cancellation stops. `--no-index` bypasses the
cache; `--verify-hashes` detects stat-preserving edits during indexed refresh.

`--index-only` (alias `--indexed-only`) reads published SQLite evidence only, without
source/configuration reads, freshness checks, refresh, writes or fallback. It rejects
`--no-index` and `--verify-hashes`. Missing extraction/coverage evidence stays
unavailable. Contract inventory, rule coverage and type matching do not yet have
survey snapshot projections and explicitly report unavailable. Relationships use
their existing published projection with its coverage limitations.

`--json` emits one versioned report with scope, metric completion, provenance,
coverage, findings, truncation and hints. Diagnostics go to stderr. `--no-hints`
suppresses investigation hints, not coverage limitations.

Exit 0 means analysis completed, even with malformed files or outliers. Exit 1
means incomplete execution/evidence; inspect partial results. Invalid usage follows
existing ArgumentParser behavior (exit 64). Malformed files are determined findings
and explicitly unassessable inputs for key statistics; unreadable files prevent
completion.
