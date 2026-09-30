# Applying pending edits

Persist explicit intent separately from disposable indexing, then preview or commit it safely.

## Stage an explicit baseline

Construct ``MarkdownDraftService`` with a native project directory and an optional
server resource configuration file. Construction writes nothing. Resources must
declare a codec and explicitly enable patch or replacement operations.

Call ``MarkdownDraftService/stage(path:resource:revision:request:)`` with the raw
source SHA-256 and shared mutation request. The service captures configured UUID,
original path, registry/resource fingerprint, and current provenance epoch while
preserving explicit intent. It rejects stale source, invalid identity, disabled
operations, and another active draft for the same path or UUID.

Drafts live in versioned JSON files under `.md-utils/drafts/`. Ordinary refresh,
FTS changes, and rebuild leave baseline, conflict, and attempt information intact.
They are not source backups and do not make indexed rows authoritative.

## Preview authoritative source

``MarkdownDraftService/preview(_:)`` returns ``MarkdownDraftReport`` with exact
before/after source, proposed hash, diagnostics, contract assessments, and target
resolution. It does not initialize or refresh SQLite, update drafts, or create or
prune receipts. Invalid proposals and unresolved targets are explicit reports;
malformed storage, cancellation, and unavailable configuration may throw.

Configured UUID discovery includes visible regular Markdown files outside exposed
resources. Only an unambiguous, chronological, coordinator-confirmed managed-move
chain in the draft's original unpruned epoch permits following another path.
Current UUID and source hash must still match. External relocation candidates,
collisions, changed source, and replaced paths require explicit review. A rebuild
preserves draft identity while discarding the evidence needed to follow old moves.

Metadata edits preserve unaffected values and exact body bytes but can reserialize
frontmatter. Body-only edits preserve its bytes. Semantic no-ops preserve source
bytes. Preview and execution share the existing codec and full-record validation;
no fix-it, merge, or rebase is automatically applied.

## Apply and recover a batch

``MarkdownDraftService/apply(ids:dryRun:report:)`` streams one bounded report per
draft. An empty selection uses all noncompleted drafts; IDs are processed in
lexicographic order. Dry-run has no persistent side effects. Apply holds the
collection writer lease, recovers confirmed existing commits, preflights the
selection, then replans and rechecks each source before native persistence.

A stable attempt ID is saved before submission and identifies the durable receipt.
Receipt pins prevent retention pruning before acknowledgement. Restart adopts
completed receipts or republishes confirmed commits without repeating edits.
Prepared or indeterminate outcomes require explicit operator resolution through
``MarkdownDraftService/resolve(_:decision:)``. Missing receipts cannot trigger a
blind retry; only explicit confirmNotCommitted with matching baseline can reset
such an attempt. ``MarkdownDraftService/discard(_:)`` rejects unresolved submitted
drafts.

The first execution failure stops later writes and reports unattempted drafts.
Earlier source commits remain durable; there is no multi-file rollback or
filesystem/SQLite transaction. Completed success requires refreshed memberships,
identity, diagnostics, enabled FTS, and server publication. Search is never
implicitly enabled. External editors do not honor the writer lease and may race
final source checks, as with existing native mutations.

Planning uses bounded per-file source and incremental traversal. It can require
multiple collection passes per draft; it does not cache all bodies or simulate
cross-file uniqueness swaps. Registry/resource changes require review/restaging.
