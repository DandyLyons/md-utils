# Collection index commands

Cache parsed text and type or rule assessments in a rebuildable SQLite database.

## Register and refresh selections

```sh
md-utils index update ./notes/
md-utils index type Book ./notes/
md-utils index rule books
md-utils index update
md-utils index update --verify-hashes
md-utils index update --rebuild
```

The database lives at `.md-utils/index.sqlite` under the project root. Each
command refreshes every saved scope. Directory scopes select all eligible files;
type scopes select only conforming records; rule scopes retain matching records
even when validation fails. Overlapping memberships remain independent.

The root defaults to the working directory or the root inferred from a
conventional `--config <root>/.md-utils/md-utils.json`. Nonstandard configs require
`--project-root <directory>/`. Explicit config paths are saved for future updates.
Directory arguments resolve from the working directory and must remain inside
the project root.

Scans skip hidden entries and symlinks. `--include-non-md` is saved per scope and
enables existing wrapper/comment extraction for other UTF-8 text files. Parsing
and evaluation failures are recorded separately from nonconformance and advisories.

## Check freshness

Ordinary updates use mtime and size to avoid unnecessary reads. `--verify-hashes`
checks every candidate's SHA-256, including files whose stat values are unchanged.
Configuration, transitive schema, and evaluator changes invalidate assessments.
`--rebuild` reevaluates all saved scopes while retaining SQL field indexes and views.

An incomplete scope retains old rows but does not expose them as current.
Read/parse/evaluation failures and incomplete scans produce a failing exit status.
Use the `current_documents` SQL view for current parsed members and inspect
`assessments` and `diagnostics` for details. Rule-selected malformed files retain
their selection records but are excluded from current parsed results.

Files remain authoritative. SQLite is neither a folder backup nor an atomic
filesystem snapshot, and no index command writes changes back to source files.
