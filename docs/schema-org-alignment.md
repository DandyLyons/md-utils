# Schema.org alignment proposal

Status: JSON-LD/YAML-LD integration deferred by owner, 2026-10-26. Retained as
research, not an approved format, implementation plan, or mdstandards release
prerequisite. Coordinates #192–#196, #201, and the claims-first work in #186.
The proposals below describe possibilities to revisit, not current deliverables.
Borrowing Schema.org domain vocabulary and researching consuming applications
does not require adopting JSON-LD processing.

## Deferred recommendation

The [linked-data authoring proposal](linked-data-authoring-proposal.md) expands
the RDF/JSON-LD/YAML-LD fit, familiar wikilink authoring, and Swift library candidates.

Make mdstandard vocabulary-neutral, with explicit semantic bindings and a
documented Schema.org/JSON-LD exchange profile as the first concrete application.
A standard supplies a versioned application contract: required fields, supported
representations, rules, migration definitions, and preservation guarantees.
Schema.org supplies shared meanings. Do not require every standard or source
Markdown file to use Schema.org, or make the standard manifest itself JSON-LD
merely because its content can be exported as JSON-LD.

[Schema.org's data model](https://schema.org/docs/datamodel.html) describes
type/property associations as guidelines, supports multiple inheritance, and
expects coexistence with other vocabularies. Consequently its expected types
must not be mechanically converted into our required fields or closed schemas.
A claim that something is a Recipe remains observable when it fails an adopted
recipe contract. This preserves the [claims-first direction](claims-first-document-graph.md).

## Reuse and boundaries

| Concern | Proposed treatment |
| --- | --- |
| Domain meanings | Reuse Schema.org class/property IRIs where their meanings fit; use namespaced extensions for gaps. |
| Local field names | Bind explicitly to terms; identical spelling never establishes semantic equivalence. |
| Entity identity | Export stable entity identifiers as JSON-LD `@id`; distinguish entities, source documents, standard releases, and publishers. |
| Exchange | Define a bounded JSON-LD profile, including unsupported forms and preservation behavior. Do not claim full JSON-LD processing from a field-renaming adapter. |
| Validation | Retain JSON Schema, mdtype, and mdrule responsibilities; semantic class membership is distinct from structural conformance. |
| Graph constraints | Evaluate SHACL correspondence before inventing new graph constraint machinery; no requirement to replace the existing engine. |
| Publication and migrations | Retain independently pinned releases, destination-owned migrations, and staged declarative transformations. Vocabulary reuse does not supply those workflows. |

[JSON-LD](https://www.w3.org/TR/json-ld11/) supplies contexts, identifiers, types,
and collections. Context aliases can express that local `title` means
`schema:name`; they cannot by themselves flatten ingredient groups, resolve
wikilinks, or move Markdown body sections. Those require explicit adapters using
md-utils operations. Bundled contexts and dependencies must be pinned and resolved
offline; an identifier is not permission to fetch or evidence of publisher trust.

[SHACL](https://www.w3.org/TR/shacl/) separates data graphs from shapes and has
standard graph constraints and validation reports. A later supported mapping may
reuse these, but validating example data does not prove general implication
between local and standard rules. No arbitrary SPARQL or executable extensions
are authorized by this proposal.

## Ordering update and recipes

The [June 17, 2026 announcement](https://blog.schema.org/2026/06/17/supporting-ordering-in-schema-org/)
explicitly supports RDF collections/containers as property values, interpreting
expected types against their elements. It removes ambiguity around using lists
for properties such as recipe instructions. ItemList remains useful for named
collections and additional collection metadata.

Recommend ordered JSON arrays in our authoring representation and JSON-LD
`@list` for the generic graph-preserving export of ordered property values.
Illustrative exchange fragment, not a complete recipe or approved mdstandard syntax:

```json
{
  "@context": {"schema": "https://schema.org/"},
  "@id": "https://example.org/recipes/lentil-soup",
  "@type": "schema:Recipe",
  "schema:name": "Lentil soup",
  "schema:recipeInstructions": {
    "@list": [
      {"@type": "schema:HowToStep", "schema:text": "Rinse the lentils."},
      {"@type": "schema:HowToStep", "schema:text": "Simmer until tender."}
    ]
  }
}
```

The current data-model documentation explicitly says not all parsers must
support collections. A concrete app adapter may therefore need a different
representation, verified against that app. Generic JSON-LD compatibility and
Nextcloud Cookbook compatibility are separate fixture claims. Preserve duplicate
list entries; ordinary RDF property values have set semantics. Keep occurrence
provenance outside a deduplicated graph projection.

[Recipe](https://schema.org/Recipe) already provides ingredient, yield, timing,
and instruction terms. Reconsider the proposed local names and groups against
these structures before approving the recipe contract; prefer direct reuse when
it remains pleasant to author. Do not flatten named groups silently.

[CookAction](https://schema.org/CookAction) supplies the action of preparing food
and a `recipe` property for the recipe used. A cooking-entry document can describe
that action, while remaining a distinct source record. A day-only journal date
must not become an invented precise start timestamp. Narrative observations and
historical recipe revisions still need explicit preservation decisions.

## Compatibility decisions and fixtures

[Schema.org developer guidance](https://schema.org/docs/developers.html) provides
versioned vocabulary downloads and documents both HTTP and HTTPS term spellings;
its published context currently expands to HTTP terms. Define a Schema.org-specific
alias policy and preserve authored identifiers. Never normalize all HTTP/HTTPS
identifiers indiscriminately. Pin the chosen vocabulary/context resources
separately from the authored standard's release version.

If this work is reopened and a profile approved, consider these acceptance cases
for #201; they are not current release requirements:

1. Two local spellings explicitly map to the same property; an unrelated identical
   spelling does not acquire meaning automatically.
2. A recipe and cooking-entry exchange their stable identities and relationship.
3. Repeated steps and ingredients retain order, duplicates, and group labels.
4. Equivalent supported compact/expanded forms resolve consistently; unsupported
   contexts or representations produce explicit diagnostics without network fetches.
5. A semantically described recipe with missing required data remains queryable
   while contract validation fails.
6. Unsupported application fields survive a documented preservation channel or
   appear in the staged loss report with required acknowledgment.

If resumed, settle semantic bindings and exchange profile boundaries before
building linked-data fixtures. Current recipe design and mdstandards delivery
do not depend on resolving these questions. No runtime work or new dependency
is authorized. See the linked-data proposal's reconsideration notes for the
distinction between interpretation and validation and possible layer placement.
