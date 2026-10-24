# Collection indexing

On macOS, `md-utils index watch ./notes/` registers a scope and completes an
initial refresh before watching native changes. Omit the directory to watch
saved scopes. It reloads configuration, debounces changes, and periodically
reconciles missed events while retaining the persisted metadata-only/FTS mode.
Ctrl-C/SIGTERM cancels pending work. Other platforms require `index update`.
Use `--debounce <seconds>` and `--reconcile-interval <seconds>` to tune latency.

`md-utils rules validate` automatically refreshes an existing project index's
requested rule scopes and reuses current assessments. Without an index it validates
directly, suggesting indexing after scans above 1,000 files. Index failures warn
on stderr and fall back to source validation. `--no-index` bypasses indexing and
suppresses advice; `--verify-hashes` detects stat-preserving edits. Both validation
paths skip symlinks; consistent symlink support including indexing is future work.
Simple positive rule paths such as `PROBLEMS/**/*.md` automatically narrow direct
validation and native CLI index discovery to `PROBLEMS/`. Broad globs and recursive
match groups retain full-project discovery; manual narrowing is unnecessary for
simple directory-based rules.

`md-utils index update ./notes/` registers a directory scope and refreshes all
saved scopes in `.md-utils/index.sqlite`. `index type Book ./notes/` selects only
conforming documents; `index rule books` preserves rule-selected invalid members.
Use `index update --verify-hashes` to detect stat-preserving edits, or
`index update --rebuild` to create a fresh cache from `.md-utils/md-utils.indexconfig.json`,
restoring managed fields/type views and discarding observation history. Files remain authoritative. Use `--project-root <directory>/` and
`--config <file>` for explicit configuration; nonstandard configs require a root.
`--include-non-md` is saved per scope. Scans skip hidden files and symlinks.
Incomplete scans retain unavailable rows and report errors. Query
`current_documents` for current parsed members, and inspect `assessments` and
`diagnostics` for nonconformance, parsing/evaluation errors, and advisories.
Use `index query '<sql>'` for bounded read-only SQL that refreshes every scope
first and streams rows with independent `--limit`, `--max-bytes`, and
`--max-value-bytes` bounds. Use one-column `--format nul` for unambiguous paths.
New caches are metadata-only. Run `index search enable` to retain one body per
document and build external-content FTS; `index search disable --vacuum` removes
bodies and search storage. Use `index explain '<sql>'` for query plans, `index field
add '$.field'` for an explicit JSON expression index and type-view projection, and
`index status` for freshness. Type views are named `type_<normalized-name>`.
`index provenance <path>...` prints retained observations and confirmed operations
after a hash-verified refresh; it never repairs UUIDs automatically.


Arrays require explicit `json_each` membership queries; indexing the whole JSON array does not accelerate individual elements.

Read [mutations.md](mutations.md) for durable drafts, apply, and recovery.
