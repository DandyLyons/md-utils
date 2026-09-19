# Incremental collection index

Files remain authoritative. The SQLite database is a disposable cache of parsed
text and selection assessments, not a backup or a way to restore a folder.

The native server reuses this cache and evaluation library. Its bounded read
projections and explicit resource configuration are described in
[indexed server reads](indexed-server-reads.md). Indexing a rule/type never exposes
an HTTP resource automatically.

```sh
md-utils index update ./notes/
md-utils index type Book ./notes/
md-utils index rule books
md-utils index update
md-utils index update --verify-hashes
md-utils index update --rebuild
md-utils index watch ./notes/
md-utils index query "SELECT path FROM current_documents ORDER BY path"
md-utils index explain "SELECT path FROM documents WHERE json_extract(metadata, '$.status') = 'draft'"
md-utils index field add '$.status'
md-utils index search enable
md-utils index search status
md-utils index search disable --vacuum
md-utils index status
```

`update <directory>/` registers an unrestricted directory collection. `type`
registers a directory collection containing only conforming records. `rule`
registers a project-wide collection selected by the named rule, including
selected records that fail validation. Every invocation refreshes **all saved
scopes**. Adding another selection does not replace existing scopes. Nonmembers
have cached assessments but are not documents unless another scope selects them.

The cache lives at `<project-root>/.md-utils/index.sqlite`. The root defaults to
the current directory. A conventional `--config <root>/.md-utils/md-utils.json`
infers its root; a nonstandard config requires `--project-root <directory>/`.
An explicit config path is persisted for subsequent updates of that database.
Scope paths are stored relative to the canonical project root; names, selection
kinds, and non-Markdown inclusion are stored in `scopes.definition` as JSON.
The cache refuses to open as a different project. No configuration-schema change
or separate init command is needed. A plain directory collection needs no config.

Scans recurse into directories, skip hidden entries, and do not follow file or
directory symlinks. Directory arguments are resolved from the working directory
and must remain inside the project root. Use `--include-non-md` when registering
a scope to include other UTF-8 text files. This option is saved per scope.
Extraction uses existing YAML/TOML, wrapped-frontmatter, and hash-comment parsers.
Unmapped host files retain raw text; predicates needing unavailable syntax report
the existing evaluator diagnostics. Binary/non-UTF-8 files report read failures.

## Native watching

On macOS, `md-utils index watch ./notes/` registers a directory scope, completes
an initial reconciliation, then maintains **all saved scopes** until Ctrl-C or
SIGTERM. Omit the directory to watch existing declarations without adding an
unrestricted collection. Initial failure exits unsuccessfully; subsequent failures
are reported to stderr and retried on the next change or recovery interval.

The native FSEvents subscription starts before the initial scan. It covers the
whole project, including hidden configuration/type/schema inputs, and the saved
config's parent directory for nonstandard config locations. File reads do not
trigger refreshes. Create, edit, delete, rename, and atomic replacement events
are debounced (default `--debounce 0.3` seconds); continuous changes trigger a
refresh after at most four debounce intervals, with a one-second minimum.
Changes during refresh remain pending for another pass.

The watch service uses Swift actors, a one-element-buffered `AsyncStream`,
`ContinuousClock`/`Duration`, and structured child tasks. CLI shutdown consumes
`UnixSignalsSequence` from Swift Service Lifecycle (already part of the server's
dependency graph), rather than installing POSIX handlers in command code.
The only direct C interop is isolated in `IndexNativeWatch.swift`: FSEvents
provides recursive hierarchy notifications and event-loss flags. Dispatch's
Swift file-system source watches an individual open descriptor; using one per
file would add corpus-sized watch resources and registration races for this
large-collection index. This is the documented exception to the Swift API rule.

Every event batch conservatively reconciles all saved scopes through the same
bounded staging/publication service as `index update`. This is incremental
extraction and assessment reuse, not a path-only scan: discovery and hash
verification still visit all candidates. The persisted metadata-only/FTS mode is
preserved. Configurations are reloaded and fingerprinted on each refresh, so
transitive schema or definition changes invalidate assessments without editing
documents. Moves remain deletion plus addition; identity preservation is deferred.

Dropped, coalesced, and root-change notifications trigger reconciliation, never
direct deletion. `--reconcile-interval 30` also reconciles after 30 idle seconds,
covering lost events and temporarily unavailable roots. Missing or unreadable
scopes retain prior rows as incomplete; successful enumeration is required to
prune missing files. Invalid configuration invalidates the old assessments and
the watcher retries after repair. The database, its WAL/SHM/journal sidecars,
and `.md-utils/rebuild/` recovery copies are excluded from discovery and event
feedback. Refresh staging is inside the excluded database.

Concurrent CLI refreshes use the existing SQLite transactions and optimistic
generation checks. A superseded watch refresh cannot overwrite the newer
generation; it reports the failure and retries. Ctrl-C/SIGTERM cancels pending
work and discards unpublished staging; an already committed publication remains
valid. Stop watchers before exclusive `--metadata-encoding text` recovery. A
crashed process's staging is reclaimed by the next update.

Native watching currently supports macOS only. Linux and other platforms return
an explicit unsupported-platform error; run `index update` manually or from an
external scheduler there. There is no silent polling-only watch fallback. The
periodic reconciliation on macOS supplements native notifications and can cost
a full corpus read, so choose its interval accordingly for large collections.

## Freshness and failure semantics

Normal refreshes compare mtime and size, then SHA-256 hash candidates that need
reading. `--verify-hashes` hashes every candidate, catching edits that preserve
mtime and size. Timestamp changes still reevaluate context predicates even if
the hash is unchanged. Moves are removal of the old path and addition of the new
path. There is no cross-path identity preservation.

A combined fingerprint covers configuration, standalone rule contents, type
definitions, fully resolved transitive schemas, and the extraction/evaluator
version. A change broadly invalidates cached assessments. The database stores
the fingerprint and minimal version provenance, not a definition catalog.
Configuration is compiled once per invocation using the existing type and rule
evaluators, including native JMESPath evaluation.

Scopes become `updating` before filesystem work. A successful enumeration permits
removal of missing candidates in that scope only. A missing or unreadable
directory marks its entire scope `incomplete`, reports an error, and retains its
old rows without presenting them as current. Read, parse, and evaluation failures
are recorded explicitly and retried on the next refresh. Config-loading failures
invalidate existing scopes. The CLI exits unsuccessfully for incomplete scans or
parse/evaluation failures; ordinary nonconformance remains an assessment result.

Discovery paths and changed results are staged in SQLite in bounded batches; a
refresh does not retain the corpus in memory. A file shared by overlapping scopes
is read, hashed, and parsed once before each scope evaluates the shared extraction.
The defaults fetch 256 staged candidates, batch at most 1,024 discovered paths or
256 KiB of their UTF-8 bytes, and reject an individual source larger than 64 MiB.
Library hosts can change these independent `IndexRefreshLimits`.

Changed records flush after 128 files or 4 MiB of UTF-8 payload (including
metadata, assessments, and diagnostics). A record exceeding that batch budget
flushes the preceding batch and stages alone. The 64 MiB input-file limit still
applies; oversized input is persisted as a visible failure without being read.
Peak ingestion payload is one batch plus one file's input/extraction/evaluator
output, rather than all changed bodies. Custom evaluators must budget their own
working memory and output expansion. Metadata-only batches discard bodies before
queueing them. A file's content is staged once with all independent assessments,
then written/indexed once at publication. Directory traversal is incremental;
SQLite provides candidate ordering without an in-memory directory sort.

The index encodes typed assessment payloads and existing `JSONValue` metadata
with `JSONEncoder`; it does not round-trip through Foundation `Any` objects.
Native reads and file metadata use Swift System. A Swift traversal adapter uses
Foundation's incremental directory enumerator, preserving hidden-file and symlink
exclusions and propagating traversal errors, including failures at end of iteration.
These paths require no explicit autorelease pools. Reads use at most a 64 KiB
scratch buffer, honor short reads, and check cancellation between chunks.

Reports retain the first 100 failure messages, truncated to 4,096 characters,
and count omitted messages. Full per-file findings remain in `diagnostics`.

Document, assessment, diagnostic, deletion, and optional FTS updates publish in
one SQLite transaction. Cancellation or transaction failure leaves old rows marked
unavailable. Concurrent updates use a generation check: a superseded scan cannot
overwrite newer results. Stat checks around reading and evaluation detect common
concurrent file edits, but filesystem enumeration is **not an atomic snapshot**.

Staging uses the `refresh_*` tables in the existing cache, with no separate
temporary source files. Success and normal thrown exits clear that generation's
staging; if cleanup itself fails or the process crashes, the next refresh discards
abandoned staging before scanning. Stale writers cannot append staging or remove
a newer generation's work. Freed SQLite pages remain reusable (the cache does
not shrink on each refresh). This cleanup never touches pending edits or source
files. Keep the cache and its journals under hidden `.md-utils/`, excluded by
discovery and by any filesystem watch consumer; custom cache locations and their
journals are excluded from discovery by exact path and must likewise be excluded
by the host watcher.

Readers using a SQLite read transaction see a consistent committed snapshot.
Before publication, raw tables retain the preceding content while scope state is
`updating`, so current/type views with those scopes are unavailable. Publication
switches content, memberships, diagnostics, and FTS together. Separate statements
without a read transaction can see different committed generations; use
`streamQuery` for a single consistent query. A failed or cancelled refresh never
marks partially staged content complete.

`--rebuild` ignores cached results and regenerates all registered scopes. It
retains the database schema, saved scopes/config path, SQL field indexes, and
views. An incomplete rebuild retains unavailable rows for recovery. Deleting the
database also deletes these declarations; register scopes again after deletion.
Migrations are transactional; databases from newer versions are rejected rather
than reset automatically.

`index query` and `index explain` always perform the same incremental refresh of
every saved scope before opening a serialized read snapshot. Any incomplete scan,
parse failure, or evaluation failure exits unsuccessfully without running the SQL;
there is intentionally no `--no-update` option. Exactly one SQLite read-only
statement is accepted. SQLite's statement classifier plus `PRAGMA query_only`
reject mutations. Rows are pulled from one consistent snapshot and written only
as the consumer accepts them; the query layer retains at most one row. Results
default to JSON with `columns`, typed `rows`, and a `truncated` flag; `--format
jsonl`, `--format csv`, and one-text-column `--format nul` are also available. NUL
output safely represents paths containing whitespace or newlines. `--limit`,
`--max-bytes`, and `--max-value-bytes` independently bound rows, aggregate SQLite
value bytes, and one text/BLOB value. Defaults are 1,000 rows, 64 MiB, and 16 MiB.
Cancellation and a slow output consumer stop SQLite from advancing. BLOBs are
base64 objects in JSON and base64 text in CSV. Use column aliases for unique JSONL
keys. A later-row error can leave a valid prefix already written.

All index commands use `<project-root>/.md-utils/index.sqlite` by default.
`--database <file>` selects another cache, which must be bound to the same project
root. `index status` reports the generation, last started and fully completed
refresh times, and every saved scope's state and error.

## SQLite contract

| Object | Contents |
| --- | --- |
| `files` | Root-relative path, mtime, byte size, SHA-256, parse/read state |
| `documents` | JSON/JSONB metadata and, only in FTS mode, one body per selected record |
| `scopes` | Selection JSON, combined fingerprint, scan state/error |
| `assessments` | Per-scope candidate selection, validation status, detailed evidence |
| `diagnostics` | Separate parse, selection, validation, evaluation, and advisory records |
| `documents_fts` | Optional external-content FTS5 index over `documents.body` |
| `current_documents` | Current selected `path` and ordinary JSON `metadata`, plus `body` only in FTS mode |
| `index_metadata` | Root, config path, update generation, extraction/evaluator version |
| `refresh_*` | Bounded disk-backed staging for an in-progress generation |

Raw tables may contain unavailable records after failures. Use
`current_documents` for current parsed content. For a particular scope, also
join `assessments` and `scopes`, requiring `selected=1` and `state='complete'`.
Rule-selected malformed documents retain selection and diagnostics in raw tables
but are excluded from `current_documents`. Negative type assessments never imply
membership. Selected invalid but successfully parsed rule documents remain current.

New caches are metadata-only: they do not retain bodies, create FTS tables, or
expose `body` through current/type views. `index search enable` switches to FTS
mode and rebuilds current files. FTS mode stores exactly one body in `documents`;
`documents_fts` uses it as external content, and its update triggers do nothing
when only metadata changes. Body and FTS queries in metadata-only mode fail with
an actionable error. `index search disable` drops FTS and clears bodies; add
`--vacuum` to reclaim free pages.

```sql
SELECT d.path, d.metadata
FROM current_documents AS d
JOIN documents AS raw USING(path)
JOIN documents_fts AS f ON f.rowid = raw.rowid
WHERE documents_fts MATCH 'search terms';
```

Metadata representation is selected per cache from the linked SQLite connection:
new caches use JSONB when creation, extraction, and strict validation succeed on
the linked SQLite connection, and JSON text otherwise. The
choice is recorded. A runtime that cannot read a recorded JSONB cache fails before
mutation. Public views always return ordinary JSON text. External tools therefore
do not need custom functions, but their SQLite runtime must support JSONB to open
a JSONB-backed cache.

Existing text caches remain text, including after ordinary `--rebuild`; upgrading
the OS never silently changes their encoding. Raw `documents.metadata` has BLOB
affinity and contains only the persisted representation. Validation triggers reject
mixed storage and validate JSONB with `json_valid(metadata,8)`. Use public views or
`json(metadata)` for JSON exports; raw blobs are SQLite's internal format.

To recover a JSONB cache on an older runtime, run:

```sh
md-utils index update --rebuild --metadata-encoding text
```

This explicit recovery copies the database into `.md-utils/rebuild/`, discards
cached metadata there without decoding JSONB, and reevaluates every saved scope
from authoritative files. It retains field declarations, views, body mode, and
separate pending-edit tables. Pending edits must remain independent of disposable
document rows; this does not implement `index apply` (#142). Publication uses
SQLite backup only after a complete refresh. Cancellation, scan/evaluation errors,
or failed publication leave the original cache intact. Scratch copies are removed
on normal exit; abandoned copies after a crash can be deleted.

Recovery acquires an exclusive SQLite lock for the copy, refresh, and publication.
Stop watchers, servers, editors, and external connections if lock acquisition fails.
Generation and SQLite data-version checks also reject intervening writes through
the same connection. Recovery
requires enough disk space for a full copy plus staged refresh data. An incompatible
ordinary open reports this recovery command without migrating the cache.

Field indexes are ordinary SQLite acceleration structures, distinct from
collection membership. `index field add '$.status'` creates a managed expression
index on the exact documented expression `json_extract(metadata, '$.status')`.
Use `index field list` to see projected column names and expressions, and
`index field remove '$.status'` to remove one. Query predicates must use the same
expression for SQLite's planner to select the index. SQLite scalars retain their
native SQL types; objects and arrays are JSON text. An index on an entire array
does **not** accelerate individual membership through `json_each`; model and query
array membership explicitly.

Each registered type gets a deterministic `type_<normalized-name>` view (for
example, `Book` becomes `type_book`). It includes `path`, ordinary JSON `metadata`,
an FTS-mode `body`, and one `json_extract` projection for every managed field. Views use only
successful `conforms` memberships from complete scopes, and one document may
appear in several overlapping type views. `type_views` records the exact mapping
when normalized type names collide. These views, tables, indexes, and optional FTS
use standard SQLite facilities, so compatible external SQLite tools can query the
same file without md-utils custom functions. Unmanaged SQL indexes and
views also survive refresh and rebuild. There is no JMESPath-to-SQL translation,
schema-validation extension, definition catalog, or bidirectional file writing.

See [native SQLite packaging](sqlite-index-packaging.md) for runtime requirements.
`swift test --filter 'MarkdownUtilitiesIndexTests|IndexCommandsTests|IndexPayloadTests'` covers
refresh/rebuild, migration rollback, interruption, scope overlap, unreadable
directories, stat-preserving edits, evaluator parity, schema invalidation,
non-Markdown extraction, and a 1,000-document collection. Native SQLite CI runs
these suites on macOS and Linux.

See [refresh resource measurements](index-refresh-benchmarks.md) for the
reproducible 100,000-document benchmark, byte/record budgets, hardware, and
measured limitations. Million-document validation and optimization are deferred
to future improvement and are not part of #147's acceptance criteria.
