# mdstandards: interoperability and evolution

Status: exploratory design, 2026-10-21. Nothing here enables runtime behavior or
constitutes an approved format. The structural adoption model below was clarified
by the project owner on 2026-10-21; versioning and execution details remain open.
This document distinguishes established design intent from recommendations. See the
[concept stack](../CONCEPT_STACK.md) for existing behavior.

## Initial proposal

- Standards sit above rules and enforce interoperability of rules.
- Authors publish standard files on websites, typically `foo.mdstandard.json`
  or `foo.mdstandard.yaml`.
- A standard carries a three-part version and starts at `0.1.0`.
- Patch releases preserve the enforced contract. They may change descriptions
  or correct migration implementations.
- Minor releases carry destination-owned migration definitions. For example,
  `0.2.0` explains how to migrate from the `0.1.x` contract line.
- Migrations use deterministic operations such as renaming properties or moving
  them into nested objects. Authors own their recipes' correctness and tests;
  md-utils promises faithful execution, not success for every input.
- Major releases might represent a break without an automatic migration. This
  interpretation is explicitly unsettled.

## What interoperability means

Established design intent: a standard defines minimum requirements on an
adopter's rules configuration. Its `.mdstandard.json` or `.mdstandard.yaml` file
references one or more rule files that express those minimum contracts.

At-rest adoption is explicit. The user chooses the standard and identifies which rule or
rules fulfill its referenced contracts. They may use the referenced rules
directly, or bind independently authored local rules that structurally conform
to them. Every required standard rule must be fulfilled; the precise binding
syntax and whether several local rules can jointly fulfill one requirement
remain open.

Rule conformance is structural, not nominal: matching names or resource identities
is neither necessary nor sufficient for a local substitute. A local rule may add
requirements but must preserve every minimum obligation of the standard rule.
One local rule may conform to several standard rules, and a user may adopt
multiple standards. Conflicting requirements must remain visible; adoption does
not grant one standard priority over another.

Users remain free to violate or stop following a standard. Such violations mean
nonconformance; adoption is not a global prohibition on edits or unrelated use.

For example, a standard rule requires a string `title`. A local rule requiring
both that string `title` and a string `isbn` can satisfy the minimum contract.
A rule requiring only `isbn`, making `title` optional, or permitting numeric
titles does not. Different names do not change these relationships. Examples
assume equivalent selection and no other differing obligations.

Additional document attributes remain allowed wherever the underlying contract
allows them. This structural model does not override an explicitly closed JSON
Schema or another explicit prohibition. Additional local requirements can narrow
the accepted records; they cannot weaken the standard's guarantees.

This supersedes the initial recommendation to start with supplied rules only.
Supplied rules are a convenient adoption path, not the definition of conformance.

## Rule conformance versus record conformance

There are two separate assessments:

1. **Rule conformance:** does the bound local rule guarantee the standard rule's
   minimum obligations?
2. **Collection conformance:** do the affected records and relationships actually
   satisfy those obligations, with sufficient assessment coverage?

A local rule can conform structurally while some documents violate it. Conversely,
today's documents might happen to satisfy the standard even though the local rule
permits future violations. Validating example documents cannot substitute for
checking the rule contract. Report adoption bindings, structural rule assessment,
standard data assessment, and additional local policy findings distinctly.

For fixed selection and context, the intended direction is:

```text
local rule requirements satisfied ⇒ standard rule requirements satisfied
```

This is implication, not equivalence: a stronger local contract is allowed.
It also describes transitive conformance: a record that meets the conforming local
contract meets the standard's minimum contract in that same scope. Collection
policies require collection-level evidence, not just a single-record implication.

The implication defines the design goal, not an implemented general-purpose
proof algorithm. A practical checker should prove supported cases, report a
counterexample or incompatible obligation when known, and return unavailable
when it cannot establish the relationship. Matching names, matching tests, or
failing to find a counterexample must not yield a conformance certificate.
Conjunctively retaining the standard obligations is one straightforward proof
path; independent equivalent or stronger expressions need supported reasoning.
Adding syntax is not always strengthening: an extra `anyOf` alternative can
weaken a requirement, and `not`/`oneOf` need their actual semantics respected.

## Selection and adoption scope: still to decide

The project's motivating goal is import/export interoperability, not merely
consistency within one local collection. The owner leans toward adopter-bound
selection but has not settled it. The [md-recipes exploration](md-recipes-use-cases.md)
examines this through exchange roles and local storage bindings.

Rules contain both selection and enforcement. Structural conformance must say
how their selectors relate; the minimum-requirement model alone does not settle
this. Suppose a standard selects `Books/**/*.md`, while a local rule selects only
`Books/published/**/*.md`. Stronger validation on that subset does not enforce
the standard on the remaining books if the standard's path is binding.

Two possible policies need an explicit choice:

- **Standard-owned selection:** the bound local rules must cover every record
  selected by the standard rule and guarantee its requirements there. Selecting
  additional records is allowed if the required guarantees are preserved.
- **Adopter-bound selection:** the user supplies the population through their
  local rules, while the standard supplies its minimum enforcement contract.
  Standard matchers would need explicit binding/parameterization semantics rather
  than silently being ignored.

The same decision affects relationship-policy scope and whether several local
rules may jointly cover one standard rule. Coverage cannot be inferred from a
currently empty dataset. A contradictory local contract also implies everything
in classical logic; diagnose known contradictions separately so an impossible
rule is not presented as a useful implementation of a standard.

An empty selected set currently satisfies many rules. A standard that requires
at least one book needs an explicit collection-presence obligation; importing
rules alone does not establish that. Whether to add such obligations is open.

## At-rest and in-transit conformance

The owner proposes two ways to adopt a standard:

- **At rest:** bound local rules structurally conform to the standard's rules;
  additional local requirements are allowed.
- **In transit:** local data may use a different shape. Adoption supplies an
  import definition, an export definition, or both, describing automatic
  transformations between the standard and the bound local rules.

Import means standard to local; export means local to standard. Each direction
is a separate capability. These strategies are authored by the adopting user,
unlike destination-standard-owned migrations between standard versions. They
may reuse deterministic transformation operations but have different endpoints,
selection, and validation obligations. Endpoint revisions and supported standard
versions must be explicit; final syntax remains open.

Mutual exclusivity is the owner's tentative preference, not a settled constraint.
Recommendation: at most one declared mode per adoption binding, while permitting
different bindings/collections to use different modes. At-rest data may still
need import defaults, file placement, or export packaging; those operations do
not necessarily mean its shape differs from the standard.

An important limitation follows from structural strengthening: local conformance
to the standard guarantees the local-to-standard implication, not the reverse.
A local rule requiring a private field can reject otherwise valid standard data.
Thus neither at-rest adoption nor merely providing an import definition proves
that every standard-valid input can be imported successfully.

Responsibility is explicit: the standard author defines migrations between
standard versions; the adopting user defines import/export strategies. When
local requirements differ, the user must define how that gap is handled, including
additional requirements in an at-rest adoption. In-transit adoption requires at
least an import or export strategy. The standard author does not promise support
for arbitrary local imports, and standard conformance is not such a promise.
md-utils executes the supplied strategy and reports its actual result; it does
not invent missing mappings or guarantee that every input can be transformed.
Per-operation validation and failure reporting remain distinct from proving a
user's strategy universally correct.

Both directions can exist without being lossless inverses. Data loss, unknown
extensions, linked-resource scope, identity, and repeated imports need explicit
policies. See the [recipe use cases](md-recipes-use-cases.md) for concrete examples.

## Versioning: compatibility and migration are independent

Recommend retaining `0.1.0` as the required first publication and the proposed
strict patch policy. However, do not define a major release by *absence* of a
migration. A key rename can be both breaking and easy to migrate automatically.
A compatible addition may need no edits at all.

Ordinary [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) uses
major versions for incompatible changes after stabilization and minor versions
for compatible additions; `0.x` is development and `1.0.0` establishes the stable
API. It does not encode migration availability. The stricter patch and initial
release rules here would be mdstandard-specific policy.

Two coherent choices remain:

| Policy | Minor release | Major release |
| --- | --- | --- |
| Recommended SemVer compatibility model | During `0.x`, contract changes may break compatibility; after `1.0`, additions preserve declared compatibility | Establishes stability at `1.0`; later majors may break compatibility; migrations permitted |
| Original migration-continuity model | Contract changes may break compatibility but must include migration recipes | May break the automatic migration chain; recipes optional |

The second is a legitimate custom policy, but should not claim ordinary SemVer
compatibility semantics after `1.0`. The existence of a recipe also does not
guarantee successful migration for every collection, so it is a weak proxy for
compatibility.

Under the recommended model, keep a separate migration-support declaration:
automatic recipe, explicit no-op, or manual transition with explanation. Require
a declaration for every minor transition. Whether a manual declaration may
satisfy that requirement, or every minor must have an executable recipe as
originally proposed, remains open. Allow optional major-transition recipes.

Compatibility itself needs a direction. Preserving acceptance of old valid
collections is useful but insufficient: newly allowed data could break an older
consumer. Define the supported producer/consumer expectations and stable field
meanings before promising compatible minor releases. An optional property can
break an old schema that rejects additional properties.

## Define the patch contract precisely

Recommended patch invariant: identical selection and required conformance
semantics, relationship meanings, and declared interoperability guarantees over
the complete dependency graph. Decide explicitly whether advisory changes are
also frozen; the initial proposal only freezes enforcement.

A prose description is patch-safe only when it does not redefine normative
meaning. Changing a rule matcher, a required field, a constraint severity, a
dependency's enforced behavior, or a relationship's meaning is not a patch.
Migration implementations can change without changing destination conformance.

General semantic equivalence is not something md-utils should promise to prove.
A first implementation could conservatively compare normalized enforcement
definitions and pinned dependencies, ignoring only explicitly designated
annotation and migration fields. This may reject equivalent rewrites; it must
not silently assume every `description` field is ignorable in every context.
Contract fingerprints are evidence under that algorithm, not mathematical proof
of equivalence. Full artifact digests must still distinguish migration patches.

## Definition, identity, and publication

Keep these separate in the eventual format:

- Definition-format version: the mdstandard language understood by a reader.
- Standard identity: a stable identifier independent of the versioned download URL.
- Standard version: the author's release, such as `0.2.1`.
- Contract resources: one or more referenced minimum-rule files, plus their
  type/schema dependencies; exact revisions and digests are recommended.
- Migration declarations: supported source contracts and destination-owned recipes.
- Documentation and author-provided conformance/migration fixtures.

Adoption configuration separately records the chosen standard release and explicit
bindings from its rule contracts to supplied or local rules. The configuration
location and syntax remain undecided.

The **destination standard file** contains its migration declarations. The
mdstandard **definition schema** validates those declarations; it should not be
republished for each author's standard release.

Recommend immutable version URLs and immutable dependencies, with explicit
fetch/update and a local pinned installation. A website's `latest` link can aid
discovery but should not silently change validation or migration behavior.
Loading a published definition should never execute author-supplied shell code.
Offline validation should work from the pinned dependency closure. Publication,
trust, and conformance are separate concerns.

Native types currently support JSON/YAML/TOML; standalone rules currently use
JSON. Proposed JSON/YAML standards are reasonable, but do not imply YAML rules
already exist. Installation layout, namespaces, bindings, and remote resource
resolution require explicit design; existing project-relative references cannot
simply be treated as unrestricted remote URLs.

## Migration semantics

Recommend a bounded declarative operation language over structured frontmatter
first. A rename is a move between literal property paths. Use typed key/index
paths or another unambiguous path syntax so a literal key containing a dot is
not confused with nested traversal. Exact syntax is still open.

Each operation needs defined behavior for missing sources, existing destinations,
non-object parents, nulls, arrays, and unsupported value representations. A safe
default is to stop on conflicts and require explicit conditions for skips or
parent creation. Never silently overwrite an existing destination or invent a
domain value. Identical source snapshots, bindings, and recipe revisions should
produce identical planned edits.

For example, moving `author` into `metadata.author` must state whether absent
`metadata` can be created. An existing scalar `metadata` or existing
`metadata.author` is a conflict, not permission to discard it. A recipe written
for one rule's records also needs a frozen source selection, so renaming a
selection key does not cause records to disappear halfway through execution.

Suggested workflow:

1. Resolve explicit source/destination releases and pin every recipe and resource.
2. Assess source conformance and coverage. Report nonconforming inputs separately;
   do not infer an old version merely from filenames or an adoption marker.
3. Freeze selected records and revisions; plan deterministic operations in memory.
4. Assess the result against the destination contract and relevant local policies.
   Unknown coverage must not be reported as successful migration.
5. Present a preview with conflicts, validation findings, and exact recipe identity.
6. Apply explicitly, recheck authoritative revisions, and record per-file receipts.
   Report partial completion and support recovery; do not promise collection-wide
   atomicity that the existing persistence model does not provide.
7. Update adoption state only after the relevant destination assessment succeeds;
   interrupted work needs an explicit incomplete state, not a false version claim.

With structural adoption, migration also needs to account for bound local rule
definitions and their dependencies. Moving `title` to a nested property in data
can leave a custom rule requiring the old property. Whether recipes may update
local definitions, or instead require explicit user adaptation, is open. Do not
claim adoption of the destination until its rule bindings structurally conform;
preserve or explicitly resolve the user's additional requirements.

The author's responsibility for recipe quality does not remove md-utils'
responsibility for correct operation semantics, revision checks, and honest
reporting. Recommend refusing a normal apply when preflight proves invalid
destination output. An override, if desired, is a separate decision.

Reuse the shared codec/draft/receipt model where its invariants fit, but do not
assume existing Fix-Its can perform version migration unchanged. Those repairs
normally preserve currently passing contracts; migration may intentionally
replace a source contract. It needs an explicit transition policy that preserves
unrelated obligations while assessing the destination. Frontmatter reserialization
may lose comments/formatting; untouched body bytes should retain existing safeguards.

## Patch corrections and migration paths

Your `0.2.1` example works: publish a corrected incoming recipe while preserving
the `0.2.0` destination contract. A new `0.1.x` migration can target the exact
`0.2.1` artifact and use that corrected recipe. Record the selected source release,
destination release, recipe identifier, and digest; do not execute a moving `0.2.x`.

A collection already migrated by a faulty `0.2.0` recipe is a different problem.
Updating the recipe does not repair those files retroactively. It may need an
explicit remediation recipe with provenance/preconditions, or manual repair;
discarded data may be unrecoverable. Such remediation must not be confused with
rerunning the incoming `0.1.x` migration on already transformed data.

Model migrations as directed edges. Each declares accepted source contract lines
and a pinned destination. Chaining `0.1.x → 0.2.x → 0.3.x` requires available
edges and successful intermediate assessment. Fail when a required edge is
missing; do not assume numeric adjacency proves support. Retain or explicitly
supersede incoming support in destination patches. Branch choice, prereleases,
downgrades, and whether to permit skipping versions remain open.

Authors should publish fixtures covering ordinary examples, null/missing values,
conflicts, nested paths, unrelated data preservation, failed preconditions, and
interrupted/retried application. Fixtures increase confidence, not universal proof.

## Decisions to settle before a schema or implementation

1. How do selection, adoption scope, and one-to-many rule bindings interact?
2. Ordinary SemVer compatibility or custom migration-continuity numbering?
3. What producer/consumer guarantees and advisory behavior belong to the contract?
4. Are minor migration declarations required to be executable, or may they say manual?
5. Which adoption bindings and collection-presence requirements are necessary?
6. How are identities, dependencies, migration paths, and adoption state pinned?
7. Is initial migration scope frontmatter only, and should invalid outputs always
   block normal application?
8. Which structural implication cases can the checker establish, and how are
   unsupported comparisons and contradictory contracts reported?
9. How do migrations update or require adaptation of custom rules and schemas?
10. Are modes exclusive per binding, and may one adoption mix modes by rule role?
11. How are import/export loss, identity, and applicable input conditions declared?

## Scope of the examples

`md-recipes` and `md-journal` are motivating examples for general standards
primitives, not standards to specify in this work. Recipe field lists, names,
and possible optional capabilities are illustrations, not pending product
requirements. The useful questions are how standards reference multiple rules,
how relationship obligations participate, and how user-owned strategies transform
data and connections. See [relationships in the concept stack](../CONCEPT_STACK.md#relationships-meaning-assertions-and-constraints).

No schema, CLI command, network resolver, or migration engine is implemented by
this draft. After these choices are settled, a normative RFC and fixture corpus
can define the first format without prematurely freezing the initial ideas.
