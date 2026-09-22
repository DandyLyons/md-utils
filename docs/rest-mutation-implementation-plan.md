# REST mutation implementation sequence

Status: implementation plan, 2026-09-22. No implementation acceptance criteria are
claimed complete. Product contract: [REST mutation design](rest-mutation-design.md).
Internal policy: [FileEditPolicy](document-edit-policies-design.md).

## Scope and sequencing

Implement in dependency order with #153 (named lookups/scoped constraints) and #154
(shared slug generation) as approved prerequisites to #82 integration. Both are now
listed with #152 in #93's Phase 3 roadmap. Keep #108 as the generated
mutation OpenAPI follow-up, #142 as the CLI index-apply consumer, and #152 as partial
provenance work. Do not create additional issues or mark dependencies complete merely
because this plan exists. Verify branch and prerequisite state before implementation;
use a short-lived codex/ issue branch from the appropriate integration state.

No new per-file policy configuration, universal UUID requirement, implicit filename
normalization, automatic title-to-slug synchronization, domain-value invention,
document history, or arbitrary move/rename endpoint is introduced.

## 1. Configuration, route, and request contracts

Extend existing configuration and EndpointPlan with named lookup extractors,
explicit protected-identifier designation, resource/server uniqueness constraints,
creation allocation, identity editing, and independent mutation operation opt-ins.
Keep existing configurations read-only and accepted. Use a new explicit server
configuration version for the new vocabulary, with old-version decoding retained;
do not silently drop unrecognized write/security fields. No mdtype/mdrule schema
change is needed for FileEditPolicy.

Finalize strict request envelopes and deterministic route descriptions alongside
schema/bootstrap/help updates. Preserve default item routes and reserved fallback.
Use explicit exact-path query addressing for resource-scoped remediation. Resolve
route overlap in the compiler, including named lookups versus identity-edit suffixes.
Provide a query-value route for scalar values that cannot safely occupy one path
segment rather than changing their values. URI encoding never alters filenames.

Working HTTP mapping: malformed 400, unsupported media 415, bounded size 413,
missing item 404, ambiguous identity/uniqueness conflict 409, missing revision 428,
stale canonical revision 412, invalid proposal/protected fields 422. Keep canonical
revision headers separate from ETags. Specify reversible versioned encoding for
opaque revision strings and test rejection of wildcard/weak-ETag/generation inputs.

Gate: compiler/schema compatibility tests, disabled-operation tests, route collision
tests, strict envelope decoding, and round-trip opaque revision encoding.

## 2. Lookup and collection invariants

Extend bounded native projections with named aliases and scoped uniqueness
assessment. One shared optional UUID field is an implementation choice consistent
with server-wide identity. Scan the complete configured collection for server-wide
constraints, not only public memberships. Fail closed on incomplete assessment;
do not assume an indexed absence proves authoritative absence after external edits.

Keep canonical storage handles separate from mutable resource lookup identifiers.
UUID lookup resolves the current path after reconciliation, without requiring UUIDs
for path-identified documents. Copies are collisions, not silently merged records.
Changing ISBN or slug must not change the storage identity or revision domain.

Gate: aliases across overlapping resources; missing/invalid/duplicate optional
UUIDs; unexposed holders; filename ambiguity; external moves/copies; metadata-only
and FTS parity; bounded conflict details; no leaked unexposed record representations.

## 3. Derived FileEditPolicy and mutation planning

Compose revision-bound baseline evidence with resource codecs and document-wide
identifier protections. Reuse #90 validation, including default preservation,
explicit endpointOnly, and remediation of previously failing checks. Derive identity
protections from resources selecting the baseline and proposal to prevent a single
request from escaping protection by changing membership. General writable-field
differences between resources remain resource-specific.

Add a distinct identity-edit planner using configured identifier mappings; preserve
unrelated metadata/body. Persistent UUID repair is a separate narrow capability.
Deletion checks routing/identity/revision, not conformance of absent source.

Gate: required is not immutable; full-proposal compound validation; unexposed
contracts; cross-route identity bypass attempts; membership-changing edits;
endpointOnly loss reporting; policy invalidation; no writes during planning.

## 4. Creation allocation and slug tooling

Resolve configured destination and expressive filename, protected creation-only
inputs, and automatic UUID allocation for opted-in resources. Allocate once per
idempotent operation. Filename collision defaults to rejection; an explicit suffix
policy claims a path without replacing an existing file.

Extract shared slug-generation behavior without changing existing heading anchors.
Generation must satisfy the selected identity slug format, preserve supplied values,
and fill only missing values at creation. Scoped uniqueness allocation is a separate
coordinated step. Persist generated slug/UUID/path decisions in operation intent.

Gate: spaces/Unicode/punctuation in filenames; host-equivalent path collisions;
unsafe/empty names; provided and missing slugs; format-specific output; collision
suffixes; template/identity schema validation; concurrent allocation; replay stability.

## 5. Shared native commit coordinator

Implement RecordStore mutations through a shared native service usable by REST and
#142. Start with a collection-level cross-process writer lease for participating
mutations and refresh publication. Define acquisition order and cancellation; Swift
actor isolation alone does not coordinate separate CLI processes.

Prepare bounded source and validation outside long-held locks when possible, then
revalidate source/configuration/generation/uniqueness under coordination. Stage file
content on the same filesystem; use atomic replace, no-clobber create, and checked
delete adapters. Preserve relevant permissions/metadata explicitly. Use modern Swift
facilities where suitable; isolate/document any required system-call adapter.

Gate: concurrent processes, stale revisions, external edits before commit, failure
before replacement, no-clobber creation, alias deletion, source bounds, cancellation,
and Linux/macOS filesystem behavior. Document the approved external-editor race
boundary rather than describing hash-plus-rename as universal compare-and-swap.

## 6. Durable intent, idempotency, and crash recovery

Record intent before source persistence and completion evidence afterward. Keep
recovery data distinct from disposable projections and pending drafts, and preserve
it through supported index rebuild/migration. Select storage after reviewing existing
index transaction/rebuild code; never claim filesystem and SQLite share a transaction.

State model: prepared -> source committed -> published -> completed. Also support
definite pre-commit failure and recovery-required for ambiguous outcomes. A crash
between source persistence and receipt update can be indeterminate; inspect durable
evidence and source without overwriting external changes. Absence after DELETE or
matching content alone is not universal proof of who performed an operation.

Default completed-key retention is seven days, configurable. Unresolved operations
do not expire. Scope keys to collection/resource/operation, compare canonicalized
validated payloads, conflict on changed input, and return original receipts on replay.
Return explicit committed/publication-pending outcomes and an operation-status link.
Persist enough receipt information for replay while keeping materialization bounded.

Gate: injected interruption at each durable boundary; lost-response replay; concurrent
same-key requests; changed payload; restart; expired completed keys; unexpired pending
work; external edits during recovery; preservation through index maintenance.

## 7. Consistent refresh and publication

Refresh all affected identities, memberships, validity diagnostics, optional FTS, and
server projections through existing bounded staging. Prevent an older staged refresh
from overwriting post-mutation state using writer coordination and generation checks.
Ordinary success requires consistent publication and read-after-write visibility.
Changed generation invalidates existing cursors. Publication failure never implies
source rollback; recovery republishes authoritative state when safely established.

Gate: CLI/watcher/server overlap, stale staging, FTS/metadata-only parity, aliases,
read-after-write, cursor invalidation, post-write publication failures, bounded memory,
and untouched pending drafts. No full-corpus body snapshot.

## 8. Repair integration, HTTP delivery, and handoff

Connect explicit UUID repair and best-effort automatic repair to the same revision-
checked service. #152 supplies partial evidence: automatic repair needs a supported
unambiguous evidence rule; ambiguous cases return actionable candidate choices.
Do not fabricate provenance, block HTTP on interactive input, or rewrite backlinks
automatically. Managed-copy evidence is usable only if such evidence actually exists;
this plan does not add a copy endpoint solely to supply it.

Finish generic Hummingbird handlers, structured diagnostic/fix-it responses,
configuration examples, client retry guidance, and preservation documentation. Carry
the exact implemented contract into #108; read OpenAPI must not be mislabeled as
covering mutations before that work is complete. Do not implement #142's CLI apply
workflow as an incidental expansion; expose its required shared service.

Gate: complete CRUD/identity/repair integration matrix; malformed/media/size/precondition
errors; overlapping resources and invalid records; explicit operation opt-ins. Then
run the full Swift suite and relevant native Linux checks, with Core/WASM checks for
changed portable code. Do not claim runtime validation for documentation-only work.

## Reconciled design points

- Authored editPolicy YAML is withdrawn; FileEditPolicy is derived Swift state.
- UUID generation follows resource opt-in automatically; no second generation flag.
- Uniqueness scope includes unexposed documents within the configured collection.
- Slug generation is approved, separate from uniqueness and filename handling.
- Persistent UUID, default identity, and explicitly designated identifiers are
  protected; merely adding a lookup does not protect an ordinary field.
- Repair uses available evidence and user selection when ambiguous; it does not
  promise the current index already records sufficient provenance.
- Recovery outcomes are approved; exact encoding/storage choices are engineering
  work. No additional product approval is required unless a genuine tradeoff emerges.
