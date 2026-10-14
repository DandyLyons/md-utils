# Claims-first document graph

Status: design direction agreed with the project owner on 2026-10-14;
architecture below is a recommendation, not an implemented or approved backend.
Builds on [epic #169](https://github.com/DandyLyons/md-utils/issues/169).
Follow-on work: [epic #186](https://github.com/DandyLyons/md-utils/issues/186).

## Purpose

md-utils queries attributed claims from human-readable documents. Queries
construct scoped semantic views, preserve provenance and disagreement, and
report validation and completeness separately. Types constrain conformance;
they do not determine whether claims may be observed.

The descriptive term is a provenance-aware, inconsistency-tolerant knowledge
graph over human-readable files. "Claims-first document graph" is project
terminology, not the name of an existing standard. The design draws inspiration
from Tim Berners-Lee's Web and Linked Data vision: independent documents make
claims and link to other things, while readers choose what to trust.

## Agreed principles

- Human-readable files are authoritative. Preserve transactional safeguards
  where practical, but promise no collection-wide ACID semantics. Human
  readability takes precedence. Disagreement between semantic claims is data,
  not by itself a failed transaction or a reason to reject the collection.
- Types and rules are optional structure. A user may opt into them to improve
  reliability; unmet requirements produce findings without breaking unrelated
  querying or hiding the underlying claims.
- Each file owns its authored description and can make claims about other
  things. A subject's identity and observable claims do not depend on inbound
  assertions or another document's type conformance. Source and subject are
  separate concepts; an external claim does not overwrite the subject's file.
- Authorship, semantic interpretation, conformance, trust, and consistency are
  distinct dimensions. Trust must not be inferred from passing validation.
- Conflicting claims may originate in different sources or within the same
  source, including the same revision. Preserve individual occurrences and
  their locations; one source must not be assumed internally consistent.
- Each query selects sources, interpretation bindings, and scope, producing its
  own graph view. An optional collection index catalogs claims without asserting
  their collective truth. Conflicting evidence remains available even when a
  query explicitly selects a preferred answer.
- Completeness is relative to the query scope, not the world. Read failures,
  changing files, unresolved interpretation, and exhausted budgets must expose
  incomplete evaluation even within that scope. Missing claims do not by
  themselves establish negative facts.
- Ordinary metadata participates in queries, including typed scalar filtering
  combined with traversal: for example, students of a class born in January.
- A date-valued relationship should eventually be discoverable as incoming to a
  document representing that date, without requiring an authored wikilink.

## Semantic definitions and requirements

Support relationship definitions independently of types. A shared `subjects`
definition can interpret a frontmatter array on documents without requiring a
common type. Defining a semantic meaning and requiring conformance are distinct
operations. Types can require relationship contracts; requiring at least one
occurrence additionally needs an explicit presence/cardinality requirement.
Rules are a proposed additional site for relationship requirements and bindings;
their exact declaration syntax remains to be designed.

`Person:spouse` and `Employee:spouse` are distinct predicates. A display label
alone is not identity: two resources can both define `Person` or `spouse`.
Bindings must identify the intended definition resource, with revision evidence
retained separately. Ambiguity requires explicit user disambiguation rather
than first-match selection. Durable identity across definition moves and edits
remains an open design question.

The proposed display forms below express the same directed claim:

```text
Bob -Person:spouse-> Alice
Alice <-Person:spouse- Bob
```

The second form presents an incoming edge from Alice's viewpoint. It does not
assert `Alice -Person:spouse-> Bob`, infer symmetry, or imply Alice authored the
claim. A third document might be its source. Shorthand `-spouse->` is safe only
when the query's explicit bindings identify exactly one predicate; passing type
validation must not be required to interpret it. These are illustrative display
forms, not supported CLI syntax. Quoting and qualified resource syntax are open.

Proposed reciprocal display: `Bob <-Person:spouse-> Alice` summarizes two
oppositely directed claims under the same bound predicate. Keep both underlying
claims and their provenance. To label this as mutual agreement by Alice and Bob,
the evidence must attribute each claim to its respective subject's source;
two edges asserted by a third source do not establish that agreement. Do not
manufacture the return claim from an inferred symmetry policy. Agreement on
these two assertions does not establish truth, exclusivity, or absence of other
conflicting claims, including conflicts within either source. Final notation
and attribution rules remain design questions.

## Recommended architecture (not yet selected)

Use an RDF-inspired attributed-claim model in portable Core, an optional SQLite
projection in the existing native index, and optional RDF/property-graph export
adapters. Do not require a new graph database server at this stage.

```text
Authoritative Markdown and semantic definition files
                    |
       Extraction and explicit interpretation
                    |
    Claim occurrences, provenance, and resolution evidence
                    |
       Query-scoped graph and scalar operations
                    |
       Answers, supporting claims, and findings

SQLite optionally accelerates the derived layers.
```

The logical model should distinguish:

| Component | Responsibility |
| --- | --- |
| Source snapshot | Document identity, revision, observed location, and coverage |
| Claim occurrence | Source location, authored value, subject, predicate binding, and object evidence |
| Semantic term | Entity reference or typed literal, retaining authored spelling |
| Resolution | Candidates and confirmed bindings; uncertainty is not a fabricated target |
| Derivation | Input claims and explicit mapping or inference that produced a derived claim |
| Assessment | Separately attached conformance and consistency findings |
| Query view | Scope, bindings, policies, generation evidence, and completeness |

An interpreted claim resembles `(source, subject, predicate, object)`, but needs
an occurrence identifier and source revision/location as well. A statement may
occur twice in a file or be supported by multiple files. RDF graphs are sets of
triples, so bare triples/quads alone cannot preserve all occurrence evidence.
Malformed values and unresolved references stay in the evidence layer even
when they cannot enter the resolved graph. A query can report them explicitly.

RDF datasets/named graphs provide a useful standard model for separating source
contexts, but RDF does not automatically define a graph name as its source or
provide trust policy or inconsistency-tolerant reasoning. md-utils must specify
those conventions. No OWL reasoning, global graph union, or inference of domain
semantics from arbitrary property names is implied by this recommendation.

SQLite tables can index terms, source snapshots, claim occurrences, bindings,
derivations, and findings. Index subject/predicate and predicate/object access
paths. SQL joins support scalar filtering; recursive CTEs or bounded Swift
traversal support paths. Choose execution plans using representative benchmarks;
this document makes no performance or graph-size guarantee.

The index is a materialized view, not a second writable authority. Semantic edits
go through source-file mutation and existing revision/draft/receipt mechanisms;
then affected derived state is refreshed. Never silently write graph edits back
to files. Rebuilding derived claims from the same source snapshot and bindings
must preserve observable query semantics. This does not make historical
observations, drafts, or receipts disposable. SQLite transactions protect index
publication without promising a transaction across externally edited files.

Neo4j is a possible later projection for Cypher exploration and graph workloads.
Its property graph can represent claims, but preserving conflicting scalar
values and per-occurrence attribution needs explicit claim modeling rather than
overwriting a single node property. An RDF store is another possible adapter.
Neither is required to define the portable semantic model.

## Scalar-to-document connections

The required use case is that Alice's date-valued birthday can appear as incoming
to `1990-05-12.md`. Recommended implementation: an explicit mapping associates a
date value with documents representing it. Retain the authored date literal and
mark the document connection as derived, including the mapping provenance.
Filename coincidence alone should not silently establish semantic identity.
Missing or multiple date documents must not invalidate or overwrite the date
claim. The mapping syntax and whether date values are traversable terms remain
open design decisions.

## Related work: OKF and claim assessment

The Open Knowledge Format (OKF) has overlapping goals: portable human-readable
Markdown/YAML knowledge exchanged between independent producers and consumers.
It is related work, not a format adopted wholesale. The project owner disagrees
with aspects of its design, specifically its `index.md` conventions; those
conventions must not become implicit requirements of the claims-first model.

Version distinction, checked 2026-10-14: Google's introductory article describes
v0.1, while the linked main-branch specification identifies itself as v0.2 and
discusses provenance, trust, freshness, lifecycle, and computation attestation.
This research does not change md-utils' existing OKF v0.1 conformance target.

Include these areas in #186's design finalization. The following separation is
recommended, with exact schemas and policies still open:

| Area | Question for a claim or assessment |
| --- | --- |
| Provenance | Which source occurrence, citation, or derivation produced it? |
| Trust | Who chooses to rely on which source or assessor, for which purpose? |
| Confidence | How strongly does a particular assessor believe this particular claim? |
| Freshness | When was it observed or checked, and when should it be reviewed? |
| Lifecycle | Is it active, superseded, withdrawn, or otherwise qualified? |
| Attestation | Who attests to what, against which revision and supporting evidence? |

The requested capability is optional numeric confidence in a claim, expressed
as a finite floating-point value in the inclusive interval [0, 1]. Confidence
should be an attributed assessment rather than a single global truth score:
retain the assessor, target claim/revision, and assessment time where available.
Different assessors may assign different values to the same claim. Missing
confidence is unspecified, not zero. Endpoint meanings and whether any profile
defines calibrated probability remain design questions; a bare score must not
automatically be presented as a statistical probability. Do not silently average
scores, propagate them through citations, or convert source trust into claim
confidence without an explicit policy. Low confidence does not hide a claim
unless the query explicitly filters it.

Freshness of source content, assessment freshness, and index freshness are
different. Modification time is not proof of renewed verification. Superseding
or withdrawing a claim should retain available provenance rather than silently
erasing it; historical retention guarantees still need design. An attestation
is evidence of its stated check or endorsement, not proof of domain truth.
Cryptographic signatures and execution protocols are not selected here.

Citation design must distinguish a direct assertion of X from an assertion that
another source asserts X, and from endorsing X while citing support. Confidence
in an attribution's accuracy is distinct from confidence in the attributed X.
This distinction, external URI/URL source identities, and cross-source claim
comparison remain open design work; they must not imply automatic endorsement,
retrieval, or identity merging.

## Relationship to existing work

The current [#177 design](relationship-design.md) and
[RFC 0004](rfcs/0004-document-relationships.md) implement type-bound relationships
and recursive target conformance. That remains the description of current
behavior. The new direction separates claim interpretation/querying from those
assessments. It does not silently change released contracts, defaults, or current
validation exit behavior. Versioning and migration must explicitly address this
separation before implementation changes existing semantics.

[#180](https://github.com/DandyLyons/md-utils/issues/180) remains responsible for
safe cached relationship assessment invalidation. It is necessary groundwork,
not an implementation of the broader claims-first query model. Track the latter
in a follow-on epic, linked from #169, rather than making all query-engine work
a prerequisite for finishing #169.

## Design-first delivery plan

The first step of #186 is to finalize design decisions, not to begin runtime
implementation or prematurely split implementation tickets. Resolve and record
the open decisions below with worked examples and explicit owner agreement.
Then author implementation sub-issues following #169's organization: scoped
acceptance criteria, named milestones, an issue/dependency map, and explicit
blocking relationships. Milestone boundaries and blocker edges must follow the
settled design; they are not selected by this document. Track the design gate
and subsequent decomposition in #186 before implementation starts.

## Candidate first implementation slice and open decisions

Prove a query that joins class membership with January birthdays, retaining a
conflicting birthday and a malformed value with provenance. Also demonstrate
standalone `subjects`, ambiguous definition names, incoming/outgoing views,
reciprocal displays with source attribution, same-source conflicts,
date-document mapping, and incomplete scope reporting. Direct and indexed
execution must agree for the same evidence and query bindings.

Before implementation, settle entity versus document identity; predicate and
occurrence identity over edits; standalone definitions and rule bindings;
query syntax and ambiguity behavior; explicit negation and conflict policies;
scalar equality and date mappings; RDF export conventions; and cache
invalidation/coverage contracts. Different values are not automatically a
contradiction: multiplicity, time, and explicit policies determine conflicts.

## References

- [Google Cloud: Introducing the Open Knowledge Format](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing)
- [OKF specification (moving main branch; v0.2 when reviewed)](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
- [Tim Berners-Lee: Linked Data](https://www.w3.org/DesignIssues/LinkedData.html)
- [Named Graphs, Provenance and Trust](https://www.w3.org/2009/12/rdf-ws/p613.pdf)
- [RDF 1.1 Concepts and Abstract Syntax](https://www.w3.org/TR/rdf11-concepts/)
- [SQLite recursive queries, including graphs](https://www.sqlite.org/lang_with.html)
- [Neo4j property graph concepts](https://neo4j.com/docs/getting-started/appendix/graphdb-concepts/)
