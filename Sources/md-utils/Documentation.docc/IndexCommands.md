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
md-utils index query "SELECT path FROM current_documents"
md-utils index field add '$.status'
md-utils index search enable
md-utils index search disable --vacuum
md-utils index explain "SELECT path FROM documents WHERE json_extract(metadata, '$.status')='draft'"
md-utils index status
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

## Query and accelerate fields

`index query` and `index explain` refresh every saved scope before executing one
read-only statement. Refresh failures prevent the query; mutations are rejected.
JSON output is the default, with JSONL, CSV, and one-text-column NUL output
available through `--format`. NUL output safely preserves whitespace and newlines
in paths. Rows stream from a consistent snapshot with callback/output backpressure.
`--limit`, `--max-bytes`, and `--max-value-bytes` independently cap rows,
aggregate value bytes, and one text/BLOB value.
Use `--database <file>` to select a cache other than the project default.

New caches are metadata-only and do not retain bodies or create FTS tables. Use
`index search enable` to select FTS mode and rebuild every scope. It stores one
body in `documents` and uses an external-content `documents_fts` index. `index
search disable` clears bodies and drops FTS; `--vacuum` also reclaims free pages.
Body and FTS SQL fail explicitly in metadata-only mode. `index search status`
reports both the body mode and persisted metadata encoding.

`index field add <json-path>` creates an explicit expression index. Use the exact
expression printed by `index field list` in predicates. Managed fields also become
columns in deterministic `type_<normalized-name>` views backed by complete,
successful type memberships. Arrays are indexed as whole JSON values; use
`json_each` for element membership, which is not accelerated by that index.

`index status` reports generation, refresh timestamps, and saved scope states.
Public views always expose ordinary JSON text. Raw metadata is JSONB when the
linked SQLite runtime supports it and JSON text otherwise; the cache records the
choice. Views, optional FTS5, and expression indexes use no md-utils-only SQL
functions.
