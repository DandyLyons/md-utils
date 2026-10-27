# Linked data and human-authored Markdown

Status: JSON-LD/YAML-LD integration deferred by owner, 2026-10-26. Retained as
research, not a current implementation plan or mdstandards release prerequisite.
No dependency adoption, format approval, or runtime implementation. Extends the
[Schema.org proposal](schema-org-alignment.md) and
[claims-first design](claims-first-document-graph.md); coordinates #186 and #191–#196.

## Goal and deferred recommendation

People should be able to write ordinary Markdown, structured frontmatter, and
familiar links while exchanging unambiguous machine-readable claims. Recommend
RDF-compatible semantic identity and JSON-LD exchange first; investigate YAML-LD
as an opt-in authoring/exchange profile. Do not require users to write expanded
IRIs or contexts in every note, or replace authoritative files with a graph.

[RDF](https://www.w3.org/TR/rdf11-primer/) provides a shared model of statements
about resources using subjects, predicates, and objects. Its particular value
here is composition across independently authored collections. A local triple
display is not sufficient interoperability: exported entities and predicates need
explicit identities, literals need agreed interpretations, and unresolved values
must not become invented resolved edges.

## Responsibilities in our stack

| Layer | Responsibility |
| --- | --- |
| Markdown/YAML and wikilinks | Human authoring, narrative, navigation, local references |
| Semantic bindings (proposed) | Interpret selected values as identified entities, predicates, and typed/language-tagged literals |
| JSON Schema | Validate the structured source representation |
| mdtype | Constrain a document's frontmatter, body, context, and relationships |
| mdrule | Select populations and enforce document/collection requirements |
| mdstandard | Package versioned contracts, dependencies, bindings, and migrations |
| JSON-LD / YAML-LD | Exchange or directly author those interpreted claims |

Semantic interpretation is cross-cutting, not a new required validation level.
An RDF class assertion is not proof of mdtype conformance. Existing named
relationship definitions retain their identities; two definitions become bound
to the same external predicate only explicitly. Nonconforming claims remain
observable. Standard adoption must not become mandatory to interpret a claim.

## A human-facing example

An illustrative local cooking-entry file can remain:

```markdown
---
name: Sunday dinner
recipe: "[[Recipes/Lentil soup]]"
---
Used less salt this time.
```

A proposed profile says the record describes a cooking action and `recipe`
means `https://schema.org/recipe`. The existing resolver identifies the target
document; a separate explicit entity binding identifies the recipe described
there. Export uses the entity identifier. The source document, described action,
and recipe are distinct identities, even when each document describes one entity.

JSON-LD contexts cannot parse wikilinks, disambiguate basename collisions, or
decide whether a fragment denotes a heading or a concept. Those remain md-utils
responsibilities. An ordinary body link implies navigation/reference, not an
arbitrary domain predicate. Preserve ambiguity and failed resolution as evidence.

An equivalent direct YAML-LD example, using existing JSON-LD syntax expressed as
YAML, could be:

```yaml
"@context":
  schema: https://schema.org/
  id: "@id"
  kind: "@type"
  name: schema:name
  recipe:
    "@id": schema:recipe
    "@type": "@id"
id: https://example.org/actions/sunday-dinner
kind: schema:CookAction
name: Sunday dinner
recipe: https://example.org/recipes/lentil-soup
```

This illustrates keyword aliases and identifier-valued properties, not an
approved frontmatter format. A shared context can remove repetition; bundling
must make it available offline. A context supplied by md-utils configuration
does not automatically make an isolated Markdown file self-describing to other
processors. Define the export/embedding contract explicitly. Markdown extraction
and body handling are additional conventions, not supplied by YAML-LD itself.

## Preservation and usability boundaries

- Graph equivalence is weaker than document round-trip fidelity. Preserve body,
  comments, field spelling, formatting where promised, duplicate occurrences,
  and source locations separately from graph output.
- Ordered properties need declared list semantics; a context can associate a
  property with `@container: @list` while authors keep ordinary YAML sequences.
- Inventory unmapped data before conversion. JSON-LD processing is not a loss
  detector for arbitrary local metadata. Unknown data must survive a preservation
  channel or appear in the approved staged loss workflow.
- Null, missing values, and explicit negative assertions are distinct. Missing
  claims do not establish negative facts. Keep validation scope and completeness
  separate from graph interpretation.
- Stable entity IDs should survive file moves. Do not impose public hosting:
  private identifiers can be used, with explicit cross-vault identity policy.
- Contexts change meaning and need version/digest pins. Core must not acquire
  implicit network access. Retain authored versus derived claims and provenance;
  no automatic reasoning or trust follows from a shared vocabulary.

## YAML-LD maturity and implementation boundary

The [October 24, 2026 Working Draft](https://www.w3.org/TR/2026/WD-yaml-ld-10-20261024/)
is on the W3C Recommendation track but is not a Recommendation. It constrains
YAML for JSON-LD conversion: YAML 1.2+, string mapping keys, no alias cycles, and
date-looking scalars kept as strings. Comments are presentation, and anchor
names do not identify RDF entities. These requirements need a separate parser
profile rather than silently changing existing frontmatter behavior.

No open Swift YAML-LD processor was established in this research; that is not
proof none exists. A feasible implementation could combine a conforming YAML
front end with a JSON-LD processor. Merely decoding YAML and encoding JSON is
insufficient to claim conformance: assess streams, scalar resolution, aliases,
numeric handling, loaders, and the draft's required test suites.

## Swift projects to track

- [mattt/Ontology](https://github.com/mattt/Ontology): JSON-LD-serializable Swift
  vocabulary models, focused on Schema.org, with Apple framework conveniences.
  Potentially useful for typed integrations; not established as a general
  JSON-LD algorithm processor. Dynamic user-authored standards must not be
  limited to a compiled catalog of domain types.
- [Kingpin-Apps/swift-jsonld](https://github.com/Kingpin-Apps/swift-jsonld): exposes
  expansion, compaction, framing, flattening, RDF conversion, and a pluggable
  loader. Its README reports full passage of six W3C suites; this has not been
  independently verified here. Evaluate a pinned revision, tests, dependencies,
  resource limits, platforms, and an offline loader before adopting it. The
  documented default loader uses URLSession, which would not suit Core's policy.

These are candidates to inspect, not installed dependencies or scheduled monitors.

## Considerations if this research is reopened

The following records the subsequent discussion, not approved features:

- Assigning an interpretation and checking a requirement are separate operations.
  A future mdtype might require an interpreted classification, but supplying that
  classification would be a separate declaration with explicit provenance.
- Context applicability should follow explicit declarations or rule selection,
  not successful type conformance. Otherwise interpreting the data depends on
  validation that itself needs the interpretation; invalidating a document could
  also unexpectedly change the meaning of unrelated fields.
- A tentative future placement is an optional interoperability profile published
  with an mdstandard, with mdrules providing local application. Public standard
  definitions do not imply public instance data or publicly hosted entity IDs.
  No context processing or classification requirements are currently approved
  for mdtype or mdrule.

## Deferred design experiment

Compare three representations of the same small recipe/cooking-entry collection:
current frontmatter with wikilinks; direct YAML-LD; exported JSON-LD. Specify
expected semantic equivalence and separately expected source preservation before
runtime work. Exercise moved files, ambiguous links, a private stable ID, ordered
duplicates, unknown fields, nulls, a date-only value, and failed conformance.

If resumed, the first decision is the authoring experience: consider familiar frontmatter
plus explicit reusable semantic bindings by default, with direct YAML-LD opt-in.
Then define identity, binding precedence/conflicts, extraction, and preservation.
Only then select a processor and pin the supported YAML-LD draft/profile.
