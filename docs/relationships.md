# Named frontmatter relationships

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

The document argument is collection-relative. `--root` is required and defines
both the collection and the project containing definitions. `--type` always names
the declaring contract, including for incoming queries. Omitting `--relation`
queries all its declared relations. Source selection does not narrow resolution.
Queries do not filter out assertions merely because their source type fails.

Text is the default; `--json` and `--yaml` are mutually exclusive and preserve the
same evidence. Results separate `outgoing`, `incoming`, and `selfLinks`. A confirmed
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

Queries return successfully when they produce evidence, including failed assertions
and explicitly incomplete results. Invalid options/configuration or inability to
construct the requested query fails the command. `types check` and `rules validate`
return nonzero when required conformance fails or is unavailable.
`types verify` uses the same collection-aware evaluation for declared type hints;
an absent optional relationship can pass without destination evidence.

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

Ordinary queries use and incrementally refresh an existing compatible project index.
They register a root directory scope when necessary for collection-wide source
evidence. Without an index they read source files directly. Index failures warn
and fall back; cancellation aborts. Hidden entries and symlinks are outside the
native collection universe, following existing discovery behavior.

- `--no-index` bypasses the index.
- `--indexed-only` requires registered scopes, refreshes recorded candidates, and
  never discovers new files or falls back. It may read known source files. Results
  state `New files were not discovered.` and retain limited coverage.
- `--verify-hashes` refreshes stat-preserving edits to known indexed files.

Indexed-only basename results with zero/one known candidates remain unavailable;
this mode cannot prove global uniqueness or absence of incoming links. Source
read failures are retained as limitations, never silently converted into empty data.
For relationship-aware `rules validate`, named indexed-only rules require their
registered rule scopes, and unregistered rules are listed when validating all.

The index accelerates candidate/freshness work and reuses unchanged extraction.
Raw records are still materialized and revision-verified for full structural
assessment. Relationship results may be reused after verifying a whole-collection
dependency certificate; see [relationship cache](relationship-cache.md). There is no promise of constant
time warm queries or index-only operation without source reads. Drafts and receipts
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
