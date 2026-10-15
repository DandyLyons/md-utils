# Relationship query relevance

Relevance is a dependency decision, not a heuristic based on file count or a
relationship's name. Keep separate sets for visible assertions and evidence needed
to select documents, determine applicability, or verify those assertions.

## Planning rules

1. **Select endpoints first.** Apply file/folder unions, intersections and exclusions
   before document analysis. Evaluate content-dependent selectors only for surviving
   candidates. Type conformance requested by a selector remains a dependency even
   when that type declares no relationships. Required-type selection needs positive
   unconditional rule requirements, not proof that the document conforms.
2. **Choose possible sources by direction.** Outgoing sources are selected endpoints.
   Incoming sources are sources with edges into those endpoints, plus ambiguous or
   unavailable evidence that could still refer to them. Both takes the union, with
   self-links deduplicated. A definitely resolved edge to another endpoint and a
   definitely unresolved destination cannot be incoming evidence. Without an index
   proving absence, discovering incoming sources can require a collection scan.
3. **Choose declaring contracts.** Explicit `--type` restricts named interpretation to
   those types. Otherwise retain declarations supported by applicable positive rule
   requirements/alternatives, type hints, or successful conformance. An unverified
   hint or a failed required contract still supports an authored interpretation;
   do not discard its malformed or failing assertions. Negated rule references do
   not declare relationships. Types with no relationship declarations need no graph
   root unless selection or another contract requires their conformance.
   Before automatic conformance discovery, use literal selector traversal as a cheap
   prefilter: a type is a candidate if it has a possible authored relationship value,
   an explicit/rule/hint binding, a selector dependency, or an assessment dependency.
   If all four are provably absent, skip it. Unknown traversal or malformed selected
   values remain candidates. Forced bindings remain candidates even with zero values,
   so required cardinality failures are not lost.
4. **Choose visible relationships.** `--relation` restricts named results within the
   explicit declaring types. Ordinary links remain visible. Determine which ordinary
   occurrences are covered by named declarations before filtering presentation, so a
   filtered named assertion does not incorrectly reappear as an ordinary link.
5. **Close over necessary assessment dependencies.** Extract selected values, resolve
   destinations, and assess only target types demanded by relevant assertions.
   Continue recursively only for required conformance dependencies, memoizing each
   source revision/type pair. If the answer reports whole-type conformance, required
   sibling relationships can affect that result even when `--relation` hides them.
   Such siblings are evidence dependencies, not additional visible triples. Preserve
   cardinality failures even when extraction yields no occurrences. Collection-wide
   policy validation is not implicitly requested by an ordinary relationship query.
6. **Skip an empty named plan.** If there are no visible named declarations and no
   selector or conformance dependencies involving relationships, perform no named
   graph assessment. Ordinary link extraction/resolution remains independent. Unknown
   applicability or missing projection coverage cannot justify pruning: retain the
   uncertainty and report incomplete findings. Detail levels change presentation,
   never this plan or the semantic results.

For example, an unsupported leading-`/` Markdown destination has no publishing-root
mapping. It can leave incoming coverage uncertain, but must not make an unrelated
outgoing query incomplete. A resolved edge to a different document can be excluded
from an incoming query immediately.

## SQLite-only queries and publication

`--index-only` performs **no assessment of raw files**. Query relevance controls SQL
edge lookups and decoding of published facts. The current projection implements
direction/endpoints-based source pruning, preserves uncertain incoming candidates,
and applies declaring-type/relation filters in the shared portable projection.
Per-document payloads currently include all that document's stored named evidence;
finer per-contract SQL storage is a possible later optimization.

Explicit indexing prepares evidence for future queries across its published scope;
it cannot limit publication to the endpoints of one later query. Publication roots
include only types that declare relationships; target dependencies are discovered
by the relationship evaluator. With no declaring types, there is no named graph to
assess. Independent type-selector facts reuse registered type scopes; missing facts
remain unavailable rather than triggering speculative all-types validation during
relationship publication. Explicit `index type` requests that additional work.

The live outgoing/incoming adapters still construct broader type root sets than
this full planning contract requires. Applying rules 3–5 to those adapters is a
separate optimization: retain selector dependencies, alternative/hint provenance,
whole-type verification, and negative-resolution evidence before narrowing roots.
Do not claim the full dependency planner is implemented merely because the snapshot
reader now uses reverse-edge lookup.

Regression cases for further narrowing must cover: no relationship declarations;
explicit overrides; selector-only type dependencies; alternative and negated rules;
failed hints/requirements; required sibling relationships hidden by `--relation`;
zero-occurrence cardinality failures; ambiguous incoming candidates; recursive
cycles; and result equivalence across direction, detail, and output format.
