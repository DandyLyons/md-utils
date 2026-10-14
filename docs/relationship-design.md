# Named relationship implementation design (#177)

Approved 2026-10-13. Implements RFCs 0003/0004 and epic #169 using the
#170 resolver, #173 whole-value parser, and #175 occurrence provenance.

Future direction: [Claims-first document graph](claims-first-document-graph.md)
records the 2026-10-14 decision to separate observable claims from optional
conformance requirements. The design below still documents current behavior;
the follow-on work requires explicit compatibility and migration decisions.

## Meaning and contracts

Users define domain meaning and truth. md-utils verifies stored assertions and
explicit structural constraints; a successful assessment does not certify that
an assertion is true or that the user's domain model is appropriate. Names have
no built-in meaning. Named mdtype v2 `relationships` select literal frontmatter
keys/array elements and require `requires: [document-relationships]`.

Retain malformed selected values, original syntax, literal paths and indices,
source/definition/target revisions, resolution candidates and coverage. Keep
decoded-string coordinates separate from raw-file coordinates. Bind target type
resources from the types root, allowing cyclic relationship definitions while
preserving JSON Schema resource-cycle rejection.

## Evaluation

Core owns selection, portable resolution and positive recursive conformance.
Hosts supply bounded coherent snapshots; Core performs no implicit I/O. Outcomes
are pass, fail and unavailable. Required conjunction uses fail < unavailable <
pass. Discover obligations before publishing the greatest fixed point; revisits
only establish dependency edges. Evaluate advisories separately against required
results without recursively demanding destination advisories.

Coverage separately describes source enumeration, resolution namespace and record
availability. Zero/one candidates in an incomplete namespace cannot prove absence
or uniqueness; two candidates establish ambiguity. Explicit paths can use narrow
coverage. Missing context is unavailable. Bounds and truncation are observable;
cancellation aborts publication. Resource defaults require representative tests.

## CLI and output

`relationships` has alias `rel`; `outgoing` has alias `out`; `incoming` has alias
`in`; `both` queries both directions in one snapshot. Explicit `--root` defines
the collection independently of source selection. `--type` and optional
`--relation` select declaring contracts, including for incoming queries.

Text, mutually exclusive `--json` and `--yaml` expose the same evidence. Results
have separate outgoing, incoming and selfLinks sections. Self-links occur once
in their own section, classified by established document identity. Queries retain
failed assertions and return successfully when evidence was obtained; validation
returns nonzero for required failure/unavailable. Incomplete query evidence is
explicit and never proves absence. Ordering is deterministic.

## Index integration

Follow rules validation: automatically refresh/use an existing compatible index;
without one read sources directly. `--no-index` bypasses it. `--indexed-only`
requires registered coverage, refreshes known candidates, never discovers new
files or falls back, and reports limited coverage. It may read known source files.
`--verify-hashes` detects stat-preserving changes. Ordinary index errors warn and
fall back; cancellation never triggers fallback. Use existing writer leases and
generation checks. Resolution coverage must not shrink to selected sources.

Reuse indexed source evidence and verified relationship assessments through the
[#180 cache](relationship-cache.md), with conservative whole-collection invalidation. Policies are
implemented by #178 in [relationship policies](relationship-policies.md); repairs
belong to #179. Preserve durable drafts/receipts and immutable schemas;
do not advance authoring defaults. Add a separately named capability schema.

## Verification

Test malformed and nested selections, null/count/duplicate rules, aliases,
anchors/embeds, explicit paths, partial coverage, target structural failures,
recursive pass/fail/unavailable propagation, advisory isolation, resource bounds,
cancellation, query partitioning and serialization, portable/native and
direct/indexed parity, and compatibility. Native build/tests and CLI smoke checks
run locally; Linux runs in CI, and WASM verification requires matching tooling.
