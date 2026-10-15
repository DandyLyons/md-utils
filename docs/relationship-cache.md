# Verified relationship assessment reuse (#180)

Named relationship queries and relationship-aware rule validation can reuse
persisted evidence in an existing native index. Files remain authoritative.

Ordinary outgoing CLI queries use source-directed reads and lazy target loading
instead of this whole-collection cache path. Ordinary incoming/bidirectional
queries retain the certification behavior described here. Index-only queries
read stored facts without filesystem certification; see [snapshot-only queries](index-only-queries.md). See
[query execution costs](relationship-query-design.md#implementation-and-costs).
Core evaluators remain database-independent and retain the existing mdtype v2
and mdrule v1 semantics. This does not implement the future claims-first model.

## Freshness certificate

Every reuse first refreshes/materializes source evidence, then verifies the entire
bounded collection. A deterministic certificate covers canonical root, record
paths/identities/revisions and context (including modification dates), all candidate
paths including attachments, exact-path coverage, source/namespace completeness,
limitations, recorded scopes, definitions and resolved resource bindings, evaluator
profile and budgets. The request separately identifies roots/types or selected
rules and cycle-witness mode. Definition fingerprints include compiled rule data,
authored type revisions, resource locations, transitive schemas and type bindings.
Canonical top-level schema bindings are retained even for v1 schemas without `$id`.

The certificate conservatively covers the whole supplied collection, including
nonmembers, negative lookups and ambiguous candidates. Additions, removals and
moves invalidate reuse even when the original source and target are unchanged.
Target/definition/policy edits and membership changes likewise cause reevaluation.
Recursive components are reevaluated together by the existing portable evaluators;
there is no separate persistent graph-dependency engine.

The refresh generation is a publication/concurrency token, not the input identity.
An unchanged refresh can reuse evidence across generations. Returned evidence,
including nested policy extraction and type assessments, names the current verified
generation. An index epoch prevents reuse across rebuilds.

## Publication and failure

Verification means evidence freshness, not successful conformance. Stable failures,
malformed assertions, conflicts and unavailable outcomes can be cached. Read failures,
changing snapshots, budget exhaustion and truncated diagnostics are not cached.
The service checks both collection limitations and per-node/occurrence diagnostics
for exhaustion. Oversized results are returned without persistence.

The native service holds the existing collection writer lease during cache access,
evaluation and publication. It rechecks source bytes/context, namespace and compiled
definitions before returning a hit and before publishing newly staged evidence.
SQLite checks the current and published generations plus epoch. Superseded requests
fail explicitly rather than publishing stale evidence. External editors do not
honor the lease: these checks detect changes but do not promise a filesystem-wide
atomic snapshot or freshness after the operation returns.

Evidence is encoded incrementally by occurrence/node/record, with a 64 MiB aggregate
payload ceiling, and staged in transactions containing at most 256 KiB. Manifest
and chunks switch together in one publication transaction. At most four requests
and 64 MiB of total published payload are retained; eviction affects performance,
not semantics. Evaluation's existing independent budgets still apply. A large
individual evidence item may require its own temporary encoding allocation.

Corrupt or incompatible payloads are cache misses. Generation/epoch mismatch is
an error, not permission to use an older snapshot. Cancellation does not publish
partial evidence. Normal exits clear staging; the next publication reclaims
abandoned relationship staging under the writer lease. Cache pages remain reusable;
the SQLite file need not shrink after eviction. This storage uses cache format 9;
older disposable indexes require `index update --rebuild`.

## Modes and mutations

- `--no-index` evaluates directly without cache reads or writes.
- Ordinary indexed operation retains source refresh and authoritative revision
  verification. A hit avoids graph evaluation, not source reads or discovery.
- Live internal recorded-candidate refresh never discovers new paths or falls back. Stable limited evidence
  has a separate certificate; a hit cannot certify global consistency, absence,
  or unique basename resolution. Known exact-path evidence retains its meaning.
- `--verify-hashes` retains its existing stat-preserving-edit refresh behavior.
  Relationship materialization and verification additionally compare source bytes.

Managed mutations continue through existing native writes, drafts and receipts.
Their refresh changes publication generation; a failed native refresh invalidates
current readers even when failure precedes staging. A newly loaded assessment
rechecks authoritative files, including after partial completion or recovery.
Cache evidence never authorizes a repair or replaces #179's final review/revision
checks. Rebuild discards relationship evidence and changes epoch without rewriting
durable drafts or mutation receipts outside SQLite.

The cache does not replace source-local `assessments` rows or make context-free
type views collection-aware. The shared native session is the supported access
path; raw cache tables are historical artifacts until their certificate is verified.

## Verification and measurement

Focused verification:

```bash
swift test --filter 'RelationshipCache|RelationshipPolicyCommands|RelationshipRegressionCommands|RelationshipCommands|MarkdownMutationTests|MarkdownDraftTests|IndexApplyCommandsTests'
```

The cache tests cover actual evaluator bypass, negative/ambiguous resolution,
recursive target failures, policy changes, nonmember changes, relative source moves,
attachments, transitive schemas and resource moves, context changes, limited
coverage, exhaustion, cancellation, superseded sessions, corruption, atomic failure,
retention and rebuild preservation of durable intent. Existing policy and mutation
suites retain direct/indexed parity and receipt/recovery coverage.

Run `python3 scripts/benchmark-relationship-cache.py --files 1000 --runs 3` after
building the desired CLI; pass `--binary` to select another build. The benchmark
uses project-local `tmp/` corpora and macOS `/usr/bin/time -l`, records RSS, elapsed
time, manifest reuse, retained/chunk sizes and staging cleanup. It compares direct,
cold, warm, target changes and a newly ambiguous namespace on cyclic paired records.
See [measurements](relationship-cache-benchmarks.md) for measured limits and tradeoffs.
Linux verification remains CI-only. WASM builds and smoke checks remain deferred
until release preparation, as required by the project toolchain policy.
