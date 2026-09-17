# Refreshing collections

Register independent selections and refresh their derived content transactionally.

## Open a project cache

Create the database's parent directory, open ``SQLiteIndexDatabase``, and pass it
to ``CollectionIndexer/init(database:root:)``. The initializer canonicalizes the
root, applies migrations, and rejects a database bound to a different project.

```swift
let root = URL(fileURLWithPath: "/path/to/project/", isDirectory: true)
let cache = root.appendingPathComponent(".md-utils/", isDirectory: true)
try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
let database = try SQLiteIndexDatabase(
    path: cache.appendingPathComponent("index.sqlite").path
)
let indexer = try CollectionIndexer(database: database, root: root)
let scope = IndexScope(kind: .type, path: "notes/", name: "Book")
```

## Supply the existing evaluator

Call ``CollectionIndexer/update(adding:fingerprint:rebuild:verifyHashes:evaluate:)``
with a combined fingerprint and an evaluation closure. The closure receives the
scope, project-relative path, UTF-8 source, and observed modification timestamp.
It returns ``IndexEvaluation`` containing valid JSON metadata, extracted source
body, parsing state, and an independent ``IndexAssessment``.

Type selections set `selected` only for conforming documents. Rule selections
retain matching documents even when validation fails. Keep selection errors,
validation failures, and advisories separate in ``IndexDiagnostic``. Return
`evaluation-error` for an unavailable evaluation so the next refresh retries it.

Build fingerprints with ``IndexFingerprint/combined(_:)``. Include configuration,
definitions, and fully resolved transitive schemas in deterministic order.
Include a host version component when custom extraction or evaluation changes.
The database keeps fingerprints and runtime provenance, not a definition catalog.

For overlapping scopes, prefer
``CollectionIndexer/updateMany(adding:fingerprint:rebuild:verifyHashes:limits:evaluate:)``.
It reads and hashes one changed file once and passes every scope needing assessment
to one closure, allowing the host to parse/extract once and evaluate many policies.

## Refresh and rebuild

Every update refreshes all registered scopes. Normal refreshes reuse successful
assessments when file mtime, size, and the fingerprint match. Enable `verifyHashes`
to hash every candidate and detect stat-preserving edits. A timestamp change
still triggers evaluation even when content bytes remain the same.

Discovery paths and changed results are staged in SQLite instead of corpus-sized
arrays. ``IndexRefreshLimits`` independently bounds candidate batches, discovery
path bytes, and one source-file read. Publication remains a set-based transaction.

Set `rebuild` to reevaluate all candidates. Rebuilding retains saved scopes,
configuration paths, SQL expression indexes, and views. Removing the database
also removes those declarations; a rebuild does not restore a folder from SQLite.

## Handle partial failures

Always inspect ``IndexUpdateReport/errors``. An update can commit useful results
while reporting an incomplete scope or a file that failed parsing. Incomplete
scopes retain prior membership without presenting it as current. Only successful
enumeration permits missing candidates to be removed from that scope.

Scopes become unavailable before scanning. Cancellation or a failed transaction
leaves old rows unavailable until a subsequent refresh succeeds. Content,
assessments, diagnostics, and optional FTS entries commit together. Concurrent scans use
a generation check; a superseded scan fails instead of overwriting newer data.
Filesystem scans are observations over time, not atomic snapshots.

Use ``SQLiteIndexDatabase/selectedPaths(scope:)`` for sorted current membership.
For SQL reads, `current_documents` excludes parse failures and incomplete scopes;
selected rule nonconformance remains visible when parsing succeeded. Raw tables
retain diagnostic records and unavailable data. Join FTS results to
`current_documents` before treating them as current content.

New databases are metadata-only. Use ``SQLiteIndexDatabase/setBodyMode(_:)`` to
opt into FTS before rebuilding; this retains one body in `documents` and creates
external-content FTS. Disabling it drops FTS and clears all bodies.

Use ``SQLiteIndexDatabase/streamQuery(_:limits:shouldCancel:columns:yield:)`` for
one typed, bounded, read-only SQL statement with one-row memory use, callback
backpressure, cancellation, and independent row/aggregate-byte/value limits. The
collecting ``SQLiteIndexDatabase/query(_:limit:)`` wrapper remains available for
small results. Hosts must complete a refresh and reject a report containing errors
before calling it when claiming fresh results. ``SQLiteIndexDatabase/addField(jsonPath:columnName:)``
creates an explicit JSON expression index and regenerates standard-SQL type views;
``SQLiteIndexDatabase/freshness()`` exposes the persisted generation, timestamps,
runtime version, and scope states.
