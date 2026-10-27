# Survey extension proposals

Status: proposals for owner review. No snapshot-contract or relationship API
extensions below are implemented by this document. The current CLI explicitly
reports the unavailable modes rather than filling evidence gaps from source files.

## Snapshot-only contract surveys

Goal: `survey rules`, `types`, `uncovered`, `overlaps`, and explicit `type-matches`
can answer from a published SQLite generation after documents/configuration have
been removed or become unreadable. Snapshot-only remains read-only: no source
stats, raw configuration/schema loads, writer lease, refresh, or direct fallback.

Recommended first phase: publish a compact contract catalog and rule-selection
projection during ordinary explicit indexing/refresh. The catalog records type
and rule names/versions, stable source paths, definition digests, referenced types,
and discovered-in-scope provenance. Rule evidence records matched/not-matched/
unavailable per file, diagnostic codes/messages, selection population, and scope
completion. Inventory and coverage queries then aggregate these facts rather than
running arbitrary selectors or declaring absent evidence to be a non-match.

Publish catalog, selection facts, scope coverage, and dependencies atomically in
the same generation as document evidence. Bind them to the definition/resource
digests, configuration bindings, evaluator profile, and index epoch/generation.
Unavailable selectors and partially covered populations remain explicit. File
deletion or definition changes invalidate every affected projection; mixed
generations must never produce a complete report.

Recommended second phase: add snapshot type matching through explicitly indexed
type assessments. Existing type-index operations should be reused where their
evidence covers all candidate files and all three outcomes; a list of passing
members alone cannot distinguish failure, unavailable evidence, or unassessed
files. Recursive relationships additionally require compatible collection proofs
and candidate coverage. Type matching must not be silently added to every normal
index refresh because its cost is substantially higher than inventory.

Proposed CLI: retain the current survey spellings and `--index-only` semantics.
Do not add a separate snapshot command family. An optional explicit indexing
opt-in for missing contract/type projections can be considered after checking
which existing `index rule`/`index type` scopes already supply the required facts.
No new flag spelling is selected here. Until required projections are published,
the relevant metric is unavailable with an explanation and a concrete indexing
hint; metadata metrics that have complete evidence still succeed independently.

Acceptance: byte/logical read-only checks, removed/inaccessible sources and config,
overlapping scopes, negative selection evidence, retained unreferenced definitions,
definition changes, stale/missing profiles, recursive targets, cancellation,
concurrent readers, and direct/snapshot semantic equivalence on a frozen generation.

## Relationship coverage

### Custom configuration first

This is the smaller extension. `survey relationships --config FILE` already
parses but reports unavailable. Thread the explicit configuration through the
shared collection-query session and outgoing source planner, including collection
loading, registry bindings, cache fingerprints, and resolution dependencies.
Survey should use the shared query path rather than build a second evaluator.
The current native collection loader already accepts a config path, but the query
session still constructs the conventional config path internally.

In ordinary mode preserve the shared cache/fallback/cancellation policy. In
snapshot-only mode configuration selection must use published identity/bindings;
never inspect the named raw file to decide whether a snapshot is compatible.
Unknown or incompatible configuration remains unavailable. Preserve the current
source-relative/path resolution rules and full-project destination namespace.

### Named frontmatter relationships in non-Markdown text

Extend the shared relationship engine to supported mapped frontmatter hosts and
plain text using the existing host parser. Reuse the selected file population;
avoid a survey-specific relationship syntax or Markdown parsing of code/comments.
The initial scope should be named relationships from declared frontmatter values.
Ordinary body-link scanning remains a Markdown capability; extending it to code
or arbitrary text needs a separate explicit design decision.

Report separate named/ordinary coverage by source kind. Unsupported host syntax,
unreadable inputs, and missing target evidence remain unavailable; a non-Markdown
source must never look like an empty successful Markdown scan. Reuse current
type-conformance checks, literal selector paths, temporal distinctions, provenance,
and root-confined target resolution. A resolved attachment is not automatically
an assessable target document.

For survey, the proposed default follows its existing selected text-file scope
once the shared engine supports it; `--markdown-only` restricts sources as usual.
Standalone `relationships` command defaults/opt-in flags need their own explicit
review because their current source selection differs from survey. No standalone
CLI change is selected in this proposal.

Acceptance: YAML/TOML, wrapped and line-comment hosts, null/malformed/unmapped
values, sources and targets of different kinds, nested/array selectors, self-links,
ambiguous/exact paths, full-project boundaries, custom config, and cached/snapshot
equivalence. Implement custom config first, then non-Markdown frontmatter sources;
publish compatible snapshot evidence only after both source capabilities are explicit.
