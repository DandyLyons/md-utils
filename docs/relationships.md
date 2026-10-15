# Named frontmatter relationships

The [#188 query contract](relationship-query-design.md) supports collection
selection, ordinary links and `--detail summary|explain|evidence` for text, JSON
and YAML. Named declarations retain the structural semantics described below.

Relationships are user-authored assertions stored as ordinary frontmatter values
and whole-value wikilinks. Users define their domain meaning and truth. md-utils
checks explicit structural contracts: selection, syntax, counts, resolution, and
destination conformance. A successful check does not prove a real-world relationship.
No meaning, reciprocity, or cycle prohibition is inferred from names such as spouse.

## Declare a contract

Save this as `.md-utils/types/article.mdtype.yaml` and provide a supported Person
definition at `.md-utils/types/person.mdtype.yaml`:

```yaml
md-utils-type-schema: '2'
requires: [document-relationships]
name: Article
version: '1'
frontmatter: {}
body: {requirements: [], recommendations: []}
context: {requirements: [], recommendations: []}
relationships:
  authors:
    select: [written_by, {each: true}]
    target: {type: person.mdtype.yaml}
    cardinality: {min: 1}
    duplicates: forbid
    anchors: forbid
    embeds: forbid
```

`authors` names the relationship; `written_by` is the selected frontmatter key.
The name and key need not match. A document can assert:

```yaml
written_by: ['[[People/Bob]]']
```

Selectors contain literal keys and explicit `{each: true}` array steps, with at
most 128 steps. Keys containing periods/slashes remain literal. Missing keys yield
no occurrences; wrong intermediate containers fail. Terminal null fails unless
`nulls: ignore`. Every other selected value remains visible, including nonstrings
and malformed links. `See [[Bob]]` is not a whole-value assertion.

Cardinality counts occurrences after ignored nulls are removed, before syntax or
resolution. Defaults are minimum zero and unbounded maximum. Duplicate checking
uses resolved document identity, independently of aliases and anchors. `duplicates`
defaults to `allow`; `anchors` and `embeds` default to `allow`. `severity: advisory`
reports findings without preventing required type conformance. Schema constraints
remain independent and conjunctive. Syntax/style assertions use the scalar schema
profile and, when authored, the separate `wikilink-constraints` capability gate.

Targets are explicit resources relative to `.md-utils/types/`, never the declaring
file's parent directory or a basename search. They must use an mdtype suffix and
remain confined to that resource root. Destination type hints do not prove
conformance: the target's required frontmatter, body, context, and relationships
are assessed. Cyclic target definition bindings are supported; cyclic JSON Schema
resource references retain their existing restrictions.

## Query stored assertions

```bash
md-utils relationships outgoing Articles/example.md --type Article --relation authors --root ./vault/ --json
md-utils rel out Articles/example.md --type Article --relation authors --root ./vault/ --yaml
md-utils rel in People/Bob.md --type Article --relation authors --root ./vault/ --json
md-utils rel both Articles/example.md --type Article --root ./vault/ --yaml
```

Document arguments are collection-relative and may select multiple files. `--root`
is required. `--type` overrides automatic named applicability with explicit declaring
contracts, including for incoming queries. `--relation` requires `--type` and filters
named results without hiding ordinary links or relabeling filtered named occurrences.
Without an override, conforming types, matching-rule requirements and explicit hints
supply declarations, preserving failed required/hinted assertions. Source selection
does not narrow incoming discovery or resolution.

Text is the default; `--json` and `--yaml` are mutually exclusive. All formats default
to `--detail summary`: declared triples and ordinary links, with short concern hints.
`--detail explain` adds applicability, diagnostics and coverage; `--detail evidence`
adds normalized occurrence/interpretation tables and full provenance. Incomplete
results never automatically increase verbosity. Evidence separates requested
`outgoing`, `incoming`, and `selfLinks` references. A confirmed
self-link appears once in `selfLinks`, including when an anchor points to its source.
Aliases and fragments do not create separate graph vertices. Ambiguous candidates
are never confirmed incoming edges. Outgoing results retain malformed assertions.

Evidence includes literal property paths and every array index, original values,
parsed decorations, source/target revisions, definition resource/revision and
declaration location, resolution candidates and coverage, and target outcomes.
Node assessments report selection completeness for each evaluated relationship;
selected native temporal values retain their original kind evidence.
Decoded UTF-8 ranges refer to scalar text; unavailable raw-file ranges are not
invented. Node dependency IDs provide finite explanations even for cycles.

Complete queries exit 0, including broken links and failed assertions. Incomplete
queries return available results and exit 1, including indexed-only coverage.
Invalid options/configuration or inability to
construct the requested query fails the command. `types check` and `rules validate`
return nonzero when required conformance fails or is unavailable.
`types verify` uses the same collection-aware evaluation for declared type hints;
an absent optional relationship can pass without destination evidence.

## Select a collection

```bash
md-utils rel in --select-folder books/ --root ./vault/
md-utils rel both --select-type Book --select-tag swift --select-mode intersection --root ./vault/ --json
md-utils rel both --select-rule Published --exclude-folder archive/ --root ./vault/ --detail explain
md-utils rel out --select-required-type Book --root ./vault/ --yaml --detail evidence
md-utils rel both --files-from selected-files.txt --root ./vault/
md-utils rel both --files-from0 selected-files.paths0 --root ./vault/
```

Folders recurse. Types mean structural conformance; rules mean applicability,
including failed checks. Required types mean unconditional positive obligations,
including obligations shared by every alternative, never negative references.
Tags are exact case-sensitive YAML `tags` array members. JMESPath receives `path`,
`frontmatterFormat` (`yaml` or `none`), `frontmatter` (empty object when absent),
and `body`; TOML is intentionally skipped by this selector with explicit notices.
Evaluation failures are unknown membership, not definite nonmatches.

Multiple selectors require `--select-mode union|intersection`. Repeated positional
paths and all file lists form one supplied set. Repeatable `--exclude-file`,
`--exclude-folder`, `--exclude-type`, `--exclude-rule` and `--exclude-tag` subtract
after combination. No selector is an error; `--select-folder .` selects the root.

List files use strict UTF-8 with LF (`--files-from`) or NUL (`--files-from0`)
separators. `-` consumes stdin once. Entries are root-relative; the list file itself
is working-directory-relative and may live outside the root. Preserve whitespace,
ignore empty entries, perform no expansion/unquoting, and reject absolute document
paths, root escapes, directories and non-Markdown entries. Empty lists select zero
documents successfully. Malformed/unreadable lists fail preflight; missing/unreadable
selected documents produce incomplete results. BOM handling remains deferred to #189.

Ordinary links need no definitions and include body/frontmatter Markdown and
wikilinks between Markdown files. Markdown paths are source-relative, percent-decoded
once, and exact (no extension guessing). Leading `/` is unsupported without a
publishing-root contract. Fragments are retained without renderer-specific anchor
validation. Ordinary embeds/images, attachments, external URLs and same-document
anchors are deferred; existing named capabilities remain supported.

## Coverage and recursion

Outcomes are `pass`, `fail`, and `unavailable`. Missing collection context is
unavailable, not a broken link. Zero candidates proves unresolved only with complete
relevant namespace coverage. One candidate proves resolution only with that coverage.
Two established candidates prove ambiguity even with incomplete coverage.

Name lookup uses the permitted collection namespace; explicit paths never fall back
to a basename. Slash-containing targets are root-relative except `./` and `../`.
Omitted extensions consider `.md` and `.markdown`; explicit extensions remain exact.
Anchor-only links require source membership. Allowed anchors assess the destination
document; heading/block existence is not asserted. Attachments can resolve while
their representation remains unavailable for Markdown type assessment.
Unsupported representations remain unavailable even for an otherwise unconstrained
target type. Candidate-list truncation preserves already established ambiguity.

Required recursive obligations converge to the greatest fixed point of positive
conjunctions. Structurally valid cycles pass. Definite failures propagate through
cycles; unavailable evidence propagates unless a definite failure dominates, while
causes remain visible. Revisiting a node only records an edge. Advisories inspect
completed required results without recursively demanding target advisories.

Core accepts immutable host-supplied records, identities, revisions, namespace
coverage and budgets; it performs no implicit filesystem or network access.
The native adapter performs confined bounded reads, hashes raw bytes, verifies
baselines and uses existing collection writer coordination. It exposes uncertainty
when files or discovery change during materialization. External processes are not
locked by the collection writer lease.

## Existing index behavior

Outgoing queries normally use source-directed reads instead of refreshing the
index. Explicit file selections (including intersections bounded by a supplied
file set) read only candidate sources and named target dependencies. Exact Markdown
destinations and path-qualified wikilinks use direct existence checks. Bare
wikilinks lazily discover a filename namespace without reading unrelated contents.
Consumed source revisions and destination evidence are verified before returning.
Folder/content selectors may require broader discovery or source assessment.

Incoming and bidirectional queries use and incrementally refresh an existing compatible project index.
They register a root directory scope when necessary for collection-wide source
evidence. Without an index they read source files directly. Index failures warn
and fall back; cancellation aborts. Hidden entries and symlinks are outside the
native collection universe, following existing discovery behavior.

- `--no-index` bypasses the index.
- `--index-only` (alias `--indexed-only`) reads exclusively from a published SQLite
  snapshot. No raw source/definition reads, stats, refresh, writes or fallback.
  Missing indexed evidence is reported; results identify the snapshot generation.
- `--verify-hashes` refreshes stat-preserving edits to known indexed files.

For ordinary outgoing queries, `--no-index` uses the same source-directed path;
source contents are always revision-verified, independently of `--verify-hashes`.
Explicit snapshot-only mode is separate from live verification for every direction
and rejects `--verify-hashes`. See [snapshot-only queries](index-only-queries.md).

Snapshot basename resolution describes recorded candidates, not today's filesystem.
Absent bodies and named applicability evidence prevent a complete relationship
answer; they never trigger raw-file access. Rule validation returns persisted
findings for indexed scopes without loading current rule/schema configuration.

The index accelerates candidate/freshness work and reuses unchanged extraction.
Raw records are still materialized and revision-verified for full structural
assessment. Relationship results may be reused after verifying a whole-collection
dependency certificate; see [relationship cache](relationship-cache.md). There is no promise of constant
time live queries. Snapshot-only queries never perform source reads. Drafts and receipts
remain outside disposable relationship evidence.

## Limits and compatibility

Default Core budgets are 10,000 records, 64 MiB raw record bytes, 100,000 selected
occurrences, 100,000 retained resolution candidates, 1,000 definitions, 100,000
assessment nodes, 100,000 dependency edges, and 10,000 emitted diagnostic entries.
Native discovery also limits candidate paths to the candidate budget. CLI queries
expose `--max-records` and `--max-occurrences`; library callers can configure all
budgets. Limits are conservative bounds, not scale guarantees. Tests exercise a
1,000-node cycle, ordering independence, and small-budget exhaustion. Exhausted
obligations are unavailable, known violations remain failures, diagnostic truncation
is explicit, and cancellation does not publish a completed evaluation.

The new bundled schema is `2-relationships_md-utils-type.schema.json`, with the
separate publication target
`https://dandylyons.github.io/md-utils/schemas/mdtype/2/document-relationships/mdtype.schema.json`.
`types schema --schema-version 2` selects this capable schema. Existing v2 scalar
and wikilink-only artifacts remain unchanged, as do v1 authoring defaults. Older
readers reject the capability instead of silently ignoring assertions. Schema
shape validation does not perform cross-document assessment.

Collection policies (#178) are implemented through explicit mdrule v1; see
[relationship policies](relationship-policies.md) for scopes, cycle witness flags,
return checks and JSON/YAML output. Repairs (#179) and persisted dependency invalidation
(#180) are implemented separately. Publication activation and the broader compatibility
matrix (#184) remain separate work. See [the agreed design](relationship-design.md) and
[RFC 0004](rfcs/0004-document-relationships.md).
