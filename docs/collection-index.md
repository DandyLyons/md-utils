# Incremental collection index

Files remain authoritative. The SQLite database is a disposable cache of parsed
text and selection assessments, not a backup or a way to restore a folder.

```sh
md-utils index update ./notes/
md-utils index type Book ./notes/
md-utils index rule books
md-utils index update
md-utils index update --verify-hashes
md-utils index update --rebuild
md-utils index query "SELECT path FROM current_documents ORDER BY path"
md-utils index explain "SELECT path FROM documents WHERE json_extract(metadata, '$.status') = 'draft'"
md-utils index field add '$.status'
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

Document, assessment, diagnostic, deletion, and FTS updates commit in one SQLite
transaction. Cancellation or transaction failure leaves old rows marked
unavailable. Concurrent updates use a generation check: a superseded scan cannot
overwrite newer results. Stat checks around reading and evaluation detect common
concurrent file edits, but filesystem enumeration is **not an atomic snapshot**.

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
reject mutations. Results default to JSON with `columns`, typed `rows`, and a
`truncated` flag; `--format jsonl` and `--format csv` are also available. The
default limit is 1,000 rows and the accepted range is 1 through 10,000. BLOBs are
base64 objects in JSON and base64 text in CSV. Use column aliases for unique JSONL
keys.

All index commands use `<project-root>/.md-utils/index.sqlite` by default.
`--database <file>` selects another cache, which must be bound to the same project
root. `index status` reports the generation, last started and fully completed
refresh times, and every saved scope's state and error.

## SQLite contract

| Object | Contents |
| --- | --- |
| `files` | Root-relative path, mtime, byte size, SHA-256, parse/read state |
| `documents` | JSON metadata and source text body for selected records |
| `scopes` | Selection JSON, combined fingerprint, scan state/error |
| `assessments` | Per-scope candidate selection, validation status, detailed evidence |
| `diagnostics` | Separate parse, selection, validation, evaluation, and advisory records |
| `documents_fts` | Transactionally maintained FTS5 source bodies |
| `current_documents` | Selected documents with successful parsing and a complete selecting scope |
| `index_metadata` | Root, config path, update generation, extraction/evaluator version |

Raw tables may contain unavailable records after failures. Use
`current_documents` for current parsed content. For a particular scope, also
join `assessments` and `scopes`, requiring `selected=1` and `state='complete'`.
Rule-selected malformed documents retain selection and diagnostics in raw tables
but are excluded from `current_documents`. Negative type assessments never imply
membership. Selected invalid but successfully parsed rule documents remain current.

```sql
SELECT d.path, d.metadata
FROM current_documents AS d
JOIN documents_fts AS f ON f.path = d.path
WHERE documents_fts MATCH 'search terms';
```

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
example, `Book` becomes `type_book`). It includes `path`, JSON `metadata`, `body`,
and one `json_extract` projection for every managed field. Views use only
successful `conforms` memberships from complete scopes, and one document may
appear in several overlapping type views. `type_views` records the exact mapping
when normalized type names collide. These views, tables, indexes, and FTS use only
JSON text and standard SQLite facilities, so compatible external SQLite tools can
query the same file without md-utils custom functions. Unmanaged SQL indexes and
views also survive refresh and rebuild. There is no JMESPath-to-SQL translation,
schema-validation extension, definition catalog, or bidirectional file writing.

See [native SQLite packaging](sqlite-index-packaging.md) for runtime requirements.
`swift test --filter 'MarkdownUtilitiesIndexTests|IndexCommandsTests'` covers
refresh/rebuild, migration rollback, interruption, scope overlap, unreadable
directories, stat-preserving edits, evaluator parity, schema invalidation,
non-Markdown extraction, and a 1,000-document collection. Native SQLite CI runs
these suites on macOS and Linux.
