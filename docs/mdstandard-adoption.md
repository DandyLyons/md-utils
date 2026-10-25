# mdstandard adoption and rule bindings

Status: proposed normative contract for [#192](https://github.com/DandyLyons/md-utils/issues/192),
2026-10-21. **Owner agreement pending.** MUST/MUST NOT below describe the proposed
contract, not current runtime support. No schema, configuration syntax, or new
mdrule version is approved by this document.

Parent: [#191](https://github.com/DandyLyons/md-utils/issues/191).
Read alongside the [original design](mdstandards-design.md),
[concept stack](../CONCEPT_STACK.md), and [recipe exploration](md-recipes-use-cases.md).
Recipe and journal contracts below are deliberately small fictional examples;
this proposal does not define either domain standard.

## Decisions proposed for approval

| Decision | Proposal | Reason |
| --- | --- | --- |
| Required rule identity | A standard-local role identifies each required rule resource in a pinned standard release | Display names and installation paths cannot identify an obligation reliably |
| Population ownership | Preserve referenced matchers by default; allow rebinding only when the standard explicitly authorizes it for that role | Portable layouts need an explicit interpretation, without changing old rule meanings |
| One-to-many bindings | One role binds one or more local rules; their selections form a union, with each member preserving the full per-record minimum | Partitioning a collection must not weaken obligations |
| Collection policies | Prove preservation over the role's entire population and required reachable context | Separate shard checks cannot prove a union is acyclic or reciprocal |
| Modes | Exactly one mode per role binding; an adoption may mix modes | Different kinds of local records can require different representations |
| Evidence | Report declaration, structural assessment, data assessment, and operation result independently | A declaration or successful import is not a standing conformance certificate |

These choices are recommendations resolving #192's questions for review. They
become agreed decisions only after the owner approves this document or specified
revisions. #193–#196 still own their respective proof, format, release, execution,
and exchange decisions.

## Identity and explicit adoption

A standard release MUST identify every required rule through a unique local
**role identifier**, such as `recipe` or `cooking-entry`, and an exact referenced
rule resource. A role is an address for a requirement, not a new type or predicate.
Two roles can reference the same rule and still require separate explicit bindings.
The complete role reference is `(standard identity, authored release, role ID)`.
The resolved artifact revision and transitive dependency revisions MUST accompany
assessment evidence. Identity and revision are distinct: identical display names
or identical bytes do not merge independently identified standards.

An adoption MUST record:

- An adopter-local adoption identifier and explicit collection/root context.
- A resolved standard identity, release, artifact revision, and dependency closure.
- Exactly one binding group for each required role, with a stable local binding ID.
- Each group's mode, nonempty list of exact local rule resources, and selection
  interpretation allowed by that standard role.
- Explicit interpretation bindings for any distinct relationship resources being
  compared, and directional strategy references when required by the mode.

Resource locators identify files; declared names are presentation, not fallback
lookup keys. Local rules retain their resource identity and revision evidence;
using a supplied rule directly is permitted but still requires an explicit binding.
No filename coincidence, type hint, installed package, or passing sample implies
adoption. Missing required roles make the declaration incomplete; unknown role IDs,
duplicate binding groups, ambiguous resources, and unsupported selection modes
are declaration errors. An incomplete draft may be retained but MUST NOT be
reported as a complete adoption.

The initial proposal has required roles only. Optional profiles are deferred;
an empty population is not a way to omit a required binding. A local rule can
participate in several roles or standards, with separate assessment of each.
No binding overrides another applicable local rule or standard.

Exact identity encoding, publication, digest algorithms, and resolution are #194
work. Configuration location and format activation require #135/#184 coordination.
This logical model is not permission to add keys to config 0.3.0 or reinterpret
existing project-relative resource references.

## Population and selector semantics

Let `U` be the explicitly supplied collection universe and `P(r, U)` the records
selected by local rule `r` under its unchanged matcher. For a role bound to rules
`r1 … rn`, its local population `P` is their union. Membership MUST be selected
before enforcement: invalid records remain members. Unknown selection or discovery
coverage MUST remain visible, not be treated as an empty population.

The standard author MUST choose one of these interpretations for each role:

1. **Preserved selection (default).** The referenced rule's matcher selects a
   required population `S` in the declared collection context. The binding MUST
   establish that `S` is covered by `P` for all supported inputs, not just today's
   files. Additional locally selected records are permitted, but all bound members
   must preserve the standard minimum. Standard data assessment uses `S`; local
   binding assessment also reports the additional population. Narrowing from
   `Books/` to `Books/published/` does not meet the coverage requirement.
2. **Explicitly rebound population.** The standard explicitly declares that the
   referenced rule's *entire matcher* is replaceable for this role. The adoption
   chooses `P`, and the standard's enforcement obligations apply to `P`. Reports
   MUST identify the original matcher and its replacement interpretation. Neither
   partial matcher substitution nor implicit intersection is permitted. Body,
   context/path requirements inside types, and collection-policy scopes remain
   obligations; population rebinding does not remove them.

Rebinding is an explicit standard/adoption interpretation of a referenced rule;
ordinary execution of that rule retains its original matcher. A role without
author authorization MUST reject rebinding. A legacy mdrule cannot acquire this
meaning merely by being referenced. Whether this declaration can live entirely
in a new mdstandard format or needs rule syntax is a decision for #193/#184.

For a rebound role, conformance is explicitly limited to the adopter-declared
population. It does not certify that every real-world recipe or journal entry
in the vault has been included. Changing a selector changes the adoption scope
and invalidates prior evidence; it is not a repair of excluded records. A complete
empty selection can pass data requirements that are universally quantified, but
MUST report zero records. It proves neither structural implication nor import
capability. No implicit minimum population size is introduced by this proposal.

### Binding several rules

Each member MUST independently preserve the role's complete per-record minimum
on its own population. Overlap imposes all applicable local obligations; records
are counted once for population membership, with every binding origin retained.
Relationship occurrence duplicates retain their existing meaning and provenance.

Splitting different portions of one record's required contract across member
rules is not a supported proof shortcut. If one rule requires a title and another
requires ingredients, neither alone fulfills a role requiring both. The adopter
can author one local rule expressing both obligations and bind it. More general
joint implication is deferred to a separately approved extension of #193.

Collection-level obligations MUST additionally be preserved across the complete
effective standard population. Individual member proofs do not establish this.
An independently bound local rule covering the union may supply the needed
policy evidence, but its coverage and policy implication must actually be proved.
Merely rerunning the standard policy on today's data does not establish structural
rule conformance. If a checker cannot prove the aggregate guarantee, report
structural assessment unavailable and still report any independently assessed
data findings.

## Relationships and coverage

Reuse the current [relationship](relationships.md) and
[collection-policy](relationship-policies.md) contracts. Population selection,
resolution universe, relationship target conformance, and policy closure are
distinct. The resolution universe MUST NOT shrink to the requested source files.

Rebound `selected` policies use the complete role population, not each partition
in isolation. `reachable` policies start there and follow the declared relations
under the existing bounded closure contract. Preserved-selection policies retain
their original population. Boundary edges, missing context, ambiguity, budgets,
and unavailable evidence MUST remain visible. In particular, `selected` policies
still exclude boundary edges from return obligations; adoption does not turn
them into `reachable` policies. Type-level target checks still apply independently.

A relationship name or another role's name MUST NOT implicitly change its target
contract or require the destination to belong to that role. If a standard needs
role membership beyond existing target-type conformance, it needs an explicit
supported contract; #193/#196 must resolve that capability before support is
claimed. Likewise, identical relationship labels in distinct definitions do not
establish semantic identity. Binding them requires explicit resource-qualified
meaning and supported comparison coordinated with #186. Adoption creates neither
a second graph nor inferred return assertions.

Exchange selection is also distinct from relationship coverage. Exporting a
single source cannot certify a required target without including adequate target
evidence or using an explicitly supported external-reference contract. #196 owns
the packaging and external-reference mechanism. Until available, missing evidence
is unavailable, not success or permission to drop the reference. A definitively
missing required target can still produce a proven failure.

## Modes and directional operations

Each role's binding group MUST declare exactly one mode, shared by all its member
rules. Two modes cannot be assigned to the same group by duplicating it. Separate
adoptions can intentionally describe different populations; they retain separate
identities and cannot be combined into an unqualified certificate.

- **At rest:** local rules must structurally preserve the standard minimum in
  the agreed scope. Import/export strategies are optional declarations, but any
  actual transformation needs explicit operation semantics. Placement, identity
  mapping, reference rewriting, and filling additional local requirements do not
  by themselves change this mode.
- **In transit:** at least one explicit adopter-owned import or export strategy
  MUST connect the pinned standard and local endpoints. Local storage need not
  imply standard conformance. Each declared direction is separate; neither one
  strategy nor two directions prove universal success or lossless round trips.

An adoption may have at-rest recipe bindings and in-transit cooking-entry
bindings. Its mode summary is then **mixed**, not wholly at rest. Whole-adoption
import/export capability requires that direction for every required role, with
supported handling of relationships between them. A subset capability MUST name
the supported roles. At-rest mode alone does not advertise an executable import
or export strategy; an eventual explicit identity/no-op strategy can do so.

A relationship crossing modes still requires assessment in a coherent endpoint
representation. Do not compare an exported cooking entry against an unadapted
local target whose shape differs from its standard contract. Mapping missing,
ambiguous, or unsupported endpoints prevents a success claim for that operation.
It does not retroactively erase independently evidenced at-rest results.

## Separate findings and responsibilities

| Dimension | What it establishes | What it does not establish |
| --- | --- | --- |
| Adoption declaration | Required roles resolve with explicit modes and bindings | Structural or data conformance |
| Structural assessment | Proven implication, known incompatibility, or unavailable proof for at-rest bindings, including scope | That today's records pass; correctness of transit strategies |
| Data assessment | Pass/fail/unavailable for specified standard and local obligations at a named snapshot and scope | Future data validity, rule implication, or domain truth |
| Execution result | Planned/applied/skipped/failed items, destination findings, and any partial completion | Universal import success or collection-wide atomicity |

In-transit structural implication is **not applicable**, not a synthetic pass.
Strategies can have declaration errors even before execution. Assess standard
inputs/outputs and local inputs/outputs separately as relevant to each direction.
Required failures and evidence gaps cannot produce a complete conformance claim;
known failures remain visible alongside unavailable regions. Advisory constraints
remain advisory. Known contradictory local requirements MUST be diagnosed rather
than presented as useful conformance through vacuous implication. #193 specifies
the supported proof procedure and contradiction detection limits.

Every finding MUST retain adoption/role/binding IDs, exact definition revisions,
scope and selection interpretation, relevant record revisions, coverage, and
the cause or witness appropriate to its dimension. No persistent certificate
survives an unverified change to those inputs.

Standard authors own minimum contracts and version migrations. Adopters own
local bindings and import/export strategies, including gaps caused by stronger
local requirements. md-utils owns faithful execution and honest reporting; it
MUST NOT invent domain values or select an arbitrary ambiguous destination.
Invalid or unsupported bindings prevent affected standards operations from
claiming success. They MUST NOT hide authored claims or impose a new global
block on unrelated queries, editing, or other standards. Existing independently
authorized mutation safeguards remain in force.

Owner clarification (2026-10-22): every authored standard has a version number,
and every release after the first must define migration from its preceding
version. **#195 designs migration between standard versions; #194 designs its
versioning and publication.** This is distinct from #193's definition-format
migration work. See [the standard-version migration requirement](mdstandards-design.md#required-migrations-between-authored-standard-versions).

See [publication and migration placement](mdstandards-design.md#definition-identity-and-publication)
for the approved per-release resource layout and destination-owned
migration declarations and separate operation files. Independent releases, pinned
cross-version references, and destination-owned placement are now approved;
identifier syntax and operation formats remain under review in #194/#195.

## Worked use cases

The following are semantic fixtures, not runnable configuration. In all recipe
examples the fictional standard has two required, population-rebindable roles:
`recipe` requires string `title` and a nonempty string array `ingredients`;
`cooking-entry` requires a date and exactly one declared recipe reference whose
target meets the recipe contract. Other constraints are stated explicitly.

### A. Two households use different folders

| Binding | Household A | Household B |
| --- | --- | --- |
| Recipe population | `Kitchen/Recipes/**/*.md` | `Notes/Food/**/*.md` |
| Cooking-entry population | `Kitchen/Log/**/*.md` | `Daily/Cooking/**/*.md` |
| Mode | Both at rest | Both at rest |

Both households bind exact local rule resources to both standard roles. Each
rule retains the corresponding requirements. A stores `Kitchen/Recipes/soup.md`;
B stores `Notes/Food/soup.md`. Both records have `title: Soup` and
`ingredients: [lentils, stock]`.

Household B's logical declaration could be written for review as follows. This
is notation, not supported file syntax; revision labels stand for exact resolved
artifacts rather than mutable aliases:

```text
adoption: household-b-food
collection root: /vault-b/
standard: example-recipes, release 0.1.0, artifact revision S1
required role recipe:
  standard resource: rules/recipe.mdrule.json at S1
  binding: b-recipes; mode: at rest; selection: explicitly rebound
  local resource: .md-utils/rules/food.mdrule.json at L1
  local match: Notes/Food/**/*.md
required role cooking-entry:
  standard resource: rules/cooking-entry.mdrule.json at S1
  binding: b-cooking; mode: at rest; selection: explicitly rebound
  local resource: .md-utils/rules/cooking.mdrule.json at L2
  local match: Daily/Cooking/**/*.md
```

Both role references are qualified by `example-recipes` and release `0.1.0`.
The standard artifact explicitly permits rebinding for both; local resource
paths alone do not grant that permission. A separate standard's `recipe` role
would require another binding even if B reused `food.mdrule.json`.

Expected: both bindings can structurally conform despite different paths, and
these recipe records pass data assessment. A's cooking entry can link to
`[[Kitchen/Recipes/soup]]`; B's to `[[Notes/Food/soup]]`, assessed in their respective
roots. Importing between them still needs explicit placement and identity/reference
mapping; copying A's link spelling into B does not preserve its destination.

Counterexample: the published role did not authorize population rebinding and
its matcher selects `Kitchen/Recipes/**/*.md`. B cannot silently substitute
`Notes/Food/`. B must preserve/cover the published population or request a revised
standard contract. An empty `Kitchen/Recipes/` today does not prove coverage.

### B. Split active and archived populations

One adopter binds `active-recipes.mdrule.json` selecting `Recipes/Active/**/*.md`
and `archived-recipes.mdrule.json` selecting `Recipes/Archive/**/*.md` to `recipe`.
Both require title and ingredients; archived recipes additionally require an
`archivedOn` date. The role population is their union.

Expected: both can preserve the minimum. An archived record missing its title
fails data assessment even though the binding's rule implication is sound.
If the archived rule permits missing ingredients, structural conformance fails
even when every current archived record happens to include them.

If selections overlap, the record owes all applicable requirements; neither
rule wins. If one rule requires only title and the other only ingredients,
the proposed per-member binding contract rejects that decomposition, even if
their current populations coincide. Bind a combined rule instead.

### C. A cycle crosses partitions

Extend the example with a declared `derivedFrom` relation and a required
`selected` no-cycle policy on the recipe role. Put `Recipes/Active/a.md` and
`Recipes/Archive/b.md` in the two partitions, with A → B and B → A.

Each partition checked alone has only an outgoing boundary edge; neither proves
a cycle. The role union contains the cycle and MUST fail standard data assessment.
Two partition-local no-cycle policies do not structurally preserve the union
policy. A local policy selecting the union, with the same relation and forbidden
cycles, is a candidate proof; #193 must establish its coverage and implication.

If B cannot be read, report unavailable coverage rather than declaring acyclicity.
If a complete cycle witness was already obtained, preserve that failure even
when unrelated evidence later becomes unavailable.

### D. Export a cooking entry without its recipe

`Kitchen/Log/tuesday.md` refers to `[[Kitchen/Recipes/soup]]`. Export requests only
the log entry. Local assessment can resolve the recipe in the full collection
even though it is not an export source. The export still needs target inclusion
or a supported external identity/reference contract with sufficient evidence.

Expected: local success does not certify the incomplete exchange. Until #196
defines an external-target mechanism, the operation cannot claim complete
exchange conformance without supplying the required recipe evidence. A broken
local reference remains a failure; an unassessable external target is unavailable.
Neither case removes the authored reference from queries or manufactures a recipe.

### E. Stronger local data prevents an otherwise valid import

The local recipe rule also requires integer `householdRating` from 1 through 5.
An incoming record has valid title and ingredients but no rating.

Expected: at-rest structural conformance can pass; the incoming standard record
passes the standard contract; the proposed local destination fails its additional
requirement. Import must report the unmet local requirement. The adopter can
provide a meaningful value through explicit user input or revise the local
contract. The engine cannot invent a rating. A strategy that pauses for input
is not automatic success for that input. No standard-author migration is owed
for this adopter-specific gap.

### F. Mixed modes and direction-limited support

Recipes use standard-shaped data under `Notes/Food/` in at-rest mode. Cooking
entries under `Journal/Meals/` instead store `dish` and `day`; the standard uses
`recipe` and `date`. Their binding is in transit with an export-only strategy
that maps those fields and preserves the resolved recipe identity.

Expected: the declaration can be complete and mixed. Cooking-entry structural
implication is not applicable. Exported records need standard validation and
cross-role target evidence; the presence of a rename strategy does not prove
either. There is no cooking-entry import capability and therefore no whole-standard
import capability. To advertise whole-standard export, the at-rest recipe role
also needs an explicit supported export path. A second binding group for the
same role declaring at-rest mode is an error, not a way to evade the choice.

### G. Adoption, current data, and proof disagree

| Situation | Declaration | Structural result | Data/operation result |
| --- | --- | --- | --- |
| Both roles bound; recipe rule makes title optional; today's recipes all have titles | Complete | Known incompatible | Current recipe data may pass |
| Recipe rule retains all minima; one recipe lacks title | Complete | Can be proven | Standard data fails |
| Cooking-entry role omitted because no logs exist yet | Incomplete | Recipe result can still be shown | Empty logs do not complete adoption |
| Exact required resources resolve, but implication uses unsupported expressions | Complete | Unavailable | Current data can be assessed independently |
| Two `recipe` relationship labels refer to different definition resources | Ambiguous without explicit mapping | No inferred identity proof | Preserve assertions and ambiguity |
| Bound journal rule requires a date both to exist and not to exist | Complete if syntactically valid | Known contradiction; no useful conformance claim | Empty data does not cure the contradiction |

## Acceptance and coordination record

| #192 criterion | Review artifact / remaining gate |
| --- | --- |
| Reference identities and one/many bindings | Identity, population, and binding sections; A/B/G |
| Selectors, local paths, relationship coverage | Explicit preserved/rebound interpretations; A–D |
| Mode exclusivity and granularity | One mode per role group, mixed adoptions; F |
| Declaration, structural, data, execution separation | Findings table; E–G |
| Stronger local requirements and unsupported/ambiguous bindings | Responsibility section; E/G |
| Owner agreement and normative contract | Proposed contract prepared; **agreement not yet recorded** |

Owner approval record: **partial, 2026-10-21**. The owner approved the per-release
directory layout containing the standard file and separate rules, types, and
schemas, stating “This design is approved” in the annotation on that layout.
On 2026-10-22 the owner also approved independent release bundles, explicit pinned
cross-version references, and destination-owned migration definitions. Standard
identifier syntax remains open. The remaining #192
semantics and full normative contract are still pending approval.
Do not mark #192 complete or begin runtime
implementation on the strength of this draft. Record the approving owner message,
date, and approved document revision here before changing the status to accepted.
Approval of these semantics does not approve unresolved serialization or the
implementation scope of adjacent issues.

Handoffs:

- **#193:** proof fixtures above, aggregate policy preservation, matcher coverage,
  supported relationship comparison, contradiction handling, and explicit format
  impact of author-authorized population rebinding.
- **#194/#184/#135:** exact resource identity and pinned resolution, adoption
  storage, reader rejection, immutable schemas, and separate version axes.
- **#195:** explicit endpoint revisions, direction-limited strategies, stronger
  local requirements, coherent destination assessment, and partial execution.
- **#196/#186:** role-qualified exchange, target coverage and identity preservation,
  explicit semantic mappings without merging predicates or suppressing claims.

No runtime files, schemas, defaults, or published formats change in this work.
