# md-recipes: exploring storage and exchange

Status: exploratory examples, 2026-10-21. No recipe schema, field names, profiles,
exchange format, or CLI syntax are approved or implemented. This applies the
[mdstandards proposal](mdstandards-design.md) to the owner's interoperability goal.
The task is to design reusable mdstandards primitives, not to define md-recipes.
Domain details below are illustrative only and need not be settled for this work.

## What a useful recipe collection could describe

Separate instructions for making a dish from events in which someone made it.
A recipe can exist without ever being cooked. A cooking event can refer to a
recipe, record deviations, and preserve an experience without changing the recipe.

| Concept | Candidate information | Initial modeling recommendation |
| --- | --- | --- |
| Recipe | Stable identity, title, description, yield, ingredient groups, ordered instruction sections, preparation/cooking/rest durations, equipment, source attribution, tags, media | Core mdtype and standard rule |
| Ingredient entry | Authored text, ingredient name, optional quantity/unit, preparation, optionality, substitutions | Nested recipe data initially |
| Instruction step | Ordered text, optional heading, ingredient/equipment references, duration, media | Nested or body structure; choose one authoritative representation |
| Cooking entry | Recipe reference, date, actual yield, substitutions, actual durations, observations, rating, photos | Separate mdtype and rule; `CookingEntry` is a working name |
| Recipe collection | Named selection, ordering, description | Optional later type if a cookbook itself must be exchanged |
| Ingredient catalog | Reusable ingredient identities, aliases, descriptions | Later capability; do not require a catalog to share a recipe |
| Meal plan | Scheduled meals and recipe references | Separate optional capability |
| Pantry/shopping list | Stock, desired purchases, quantities | Separate optional capability; different lifecycle from recipes |

Nutrition, dietary labels, cuisine, allergen declarations, cost, authorship, and
licensing metadata are useful extension candidates. Authored labels remain claims;
passing structural validation must not imply their factual correctness.

Recommend a small core: identity, title, nonempty ingredient entries, and ordered
instructions. Whether identity is mandatory and which other fields are required
is still open. Free text must remain available for quantities such as “to taste”
and “1–2 small onions”; optional structured quantities can support computation.
Do not silently reinterpret authored units or infer missing measurements.

Choose where instructions live before defining transformations: Markdown body,
frontmatter steps, or explicit supported variants. Two independently editable
copies would need a conflict policy. The body can preserve rich narrative while
the contract defines the structure needed for exchange.

## A cooking entry is an event, not a revised recipe

Illustrative example:

```text
Recipe: Lentil soup
  identity: recipe-17
  ingredients: red lentils, stock, onion, cumin
  instructions: ordered preparation and cooking steps

CookingEntry: Lentil soup on October 20
  identity: cooking-42
  recipe: recipe-17
  cookedOn: 2026-10-20
  substitutions: used water instead of stock
  observations: needed more salt; texture was thicker than expected
```

One recipe can have many cooking entries. Recommend keeping the event's reference
to the recipe explicit, without requiring a redundant list on the recipe. A
recipe revision reference or snapshot may be useful when the recipe changes;
otherwise the event links to today's recipe, not necessarily the one cooked.
Whether snapshots, detached events, or multiple recipe references are supported
needs a decision.

Recipe identity must survive transport. A local wikilink can resolve a reference
inside a vault, but its spelling alone cannot identify the destination after
another system imports and renames files. Exchange needs an identity mapping and
a way to resolve, include, or explicitly leave external references.

## Rules as exchange roles

An md-recipes standard references a recipe rule and, if included, a cooking-entry
rule. The adopter explicitly binds local rules to those roles. A collection might
store recipes under `Kitchen/Recipes/` while another uses `Notes/Food/`; neither
path should inherently determine whether their recipe data can interoperate.

Recommendation, still open: let local rules choose local populations and define
standard obligations over explicitly bound exchange roles. A portable exchange
must identify which role each resource is offered under, then validate it;
that role declaration is not proof of conformance. This requires explicit matcher
binding semantics, not silently dropping existing rule matchers.

Population membership also differs from relationship coverage. Exporting one
cooking entry may require including its recipe or declaring a resolvable external
reference. Selecting fewer source files must not hide a missing required target.

Decide whether cooking entries are mandatory support or an optional named profile.
If mandatory, “supports md-recipes” must cover both roles even when a collection
currently has zero cooking entries. If optional, an integration should advertise
its supported profile rather than imply support for all md-recipes data. No profile
mechanism is approved yet.

## At rest: standard-shaped local records

A user binds `my-recipes` to the standard recipe rule. Their local rule retains
every standard obligation and additionally requires `householdRating`.

Every valid local recipe meets the standard contract. But an imported standard
recipe may have no household rating. Structural strengthening therefore does not
guarantee that all standard recipes can become valid local records unchanged.

Options include making the local field optional, permitting an explicit unrated
state, supplying an author-declared meaningful default, or requiring user input.
Do not fabricate a rating to make validation pass. User input also means the
operation is not fully automatic for that case. At-rest exchange can still need
placement, reference rewriting, extension handling, and identifier allocation.

## In transit: adapters between distinct shapes

Suppose local frontmatter stores `name`, `components`, and `method`, while an
illustrative exchange representation uses `title`, `ingredients`, and `steps`.
Exact standard fields and body representation are still to be designed.

| Direction | Illustrative operations | Assessment after transformation |
| --- | --- | --- |
| Import | `title → name`, `ingredients → components`, `steps → method`; place file in the bound local collection | Bound local rule and applicable collection policies |
| Export | `name → title`, `components → ingredients`, `method → steps`; package references | Standard rule and exchange coverage requirements |

These renames are simple only if the corresponding value shapes agree. If local
ingredients are free-text lines and standard ingredients require separate numeric
quantities, renaming is insufficient. Prefer preserving authored text or declaring
the unsupported case over pretending arbitrary text can be parsed losslessly.

An importer may be import-only. An exporter may be export-only. Supporting both
does not prove that export(import(x)) preserves every field or original byte.
Unknown extensions need a preserve, reject, or explicitly lossy policy. A strict
local schema may require an extension store outside the record; that is another
design decision, not an assumed existing facility.

The adopting user owns the import strategy and handles the gap between standard
data and their local rules. The standard author does not promise complete import
support. md-utils follows the supplied strategy and reports validation or execution
failures; a strategy's existence does not prove universal success. This ownership
also applies to additional local requirements when adopting at rest.

## Exchange also needs collection operations

A useful workflow should address these cases explicitly:

1. Import one recipe with no cooking history.
2. Import a recipe with several cooking entries, images, and internal links.
3. Export a cooking entry whose recipe already exists at the destination.
4. Reimport the same package without duplicating every record.
5. Receive a changed recipe with the same identity after local edits.
6. Exchange a recipe containing extensions unknown to the receiver.
7. Convert shape successfully but fail a local additional requirement.
8. Import an older standard version via a version migration and then a local adapter.

These require decisions about the exchange envelope or manifest, stable identities,
reference closure, media, duplicate detection, conflict policy, preservation, and
partial completion. A bag of individually valid Markdown files does not by itself
answer these questions. Start with a local file/bundle exchange; remote transport
protocols need not be part of the first contract.

Keep three transformations distinct even if they share operation primitives:

```text
standard version A → standard version B     author-owned version migration
standard version B → local contract        adopter-owned import definition
local contract → standard version B        adopter-owned export definition
```

No universal losslessness, inverse relationship, or automatic reversibility follows
from the presence of these edges. Validate each destination and preserve the exact
definitions used in the operation's evidence.

## General primitives illustrated by this example

- Multiple referenced rule contracts and explicit local adoption bindings.
- Relationship assertions, cardinality requirements, and preserved target identity.
- Are modes exclusive per binding, rather than for an entire collection or user?
- User-authored import/export strategies distinct from standard-author migrations.
- Identity/reference/bundle handling and honest per-operation conformance results.

Which recipe fields or optional roles a future md-recipes standard chooses is
outside the current design task.

Selector ownership remains open. The interoperability goal motivates independent
local paths and portable roles, but the exact semantics should be tested against
both recipe-only and linked cooking-history exchange before being finalized.
