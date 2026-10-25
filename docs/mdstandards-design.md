# mdstandards: interoperability and evolution

Definition-language work now lives in [RFC 0005](rfcs/0005-mdstandard.md), started
at the owner's request on 2026-10-23. This document retains design rationale and
decision history. The RFC is a working draft, not an approved published format.

Status: exploratory design, 2026-10-21. Nothing here enables runtime behavior or
constitutes an approved format. The structural adoption model below was clarified
by the project owner on 2026-10-21; versioning and execution details remain open.
This document distinguishes established design intent from recommendations. See the
[concept stack](../CONCEPT_STACK.md) for existing behavior.

The [#192 adoption proposal](mdstandard-adoption.md) now supplies a proposed
normative contract and concrete cases for identities, one/many bindings,
selector ownership, relationship coverage, and modes. Its decisions await owner
agreement; the open questions below remain historical design context, not an
approval or a competing specification.

## Required migrations between authored standard versions

Owner clarification, 2026-10-22: every user-authored standard MUST have a version
number. Every release except its first MUST define how to migrate from the
preceding standard version. This concerns, for example, **md-recipes 0.1.0 →
md-recipes 0.2.0**, not upgrading the mdrule definition language. It applies to
patch, minor, and major releases; the older suggestion that major releases could
omit migration definitions is superseded.

[#195](https://github.com/DandyLyons/md-utils/issues/195) owns the design of these
standard-version migration definitions and execution: transformations, endpoint
contracts, validation, previews, failures, receipts, and recovery.
[#194](https://github.com/DandyLyons/md-utils/issues/194) owns their version and
publication contract: identifying the predecessor, publishing migration resources,
resolving paths, and correcting published migrations. #193 separately addresses
migration/refusal when the mdtype/mdrule/config definition formats change.

For example, if md-recipes 0.2.0 replaces a required `title` with `name`, its
author must supply the definition for upgrading 0.1.0 records and assessing
them against the 0.2.0 contract. Custom local rules that still require `title`
need explicit adaptation or a reported conflict; changing data alone does not
complete adoption of the new version. Neither supplied operations nor the
mandatory migration definition guarantee success for every input.

Recommended for a release with no required data changes: an explicit identity
migration with source/destination assessment, rather than an omitted definition.
The operation format, treatment of manual steps, and predecessor selection across
release branches remain design work. These details cannot silently waive the
requirement to define migration from the preceding version.

## Shared decision checklist for #192–#196

Coordination requested by the owner on 2026-10-22: design these issues together.
The issue boundaries track deliverables; they do not require completing one
design in isolation before considering the others. This checklist is the shared
decision entry point; detailed examples remain in the linked documents.

Established: explicit structural adoption and stronger local requirements;
separate rule/data conformance; author-owned standard migrations and user-owned
import/export strategies; no universal success guarantee or suppression of claims.
Specifically approved: per-release directories with separate rule/type/schema
resources, and versioned standards with mandatory predecessor migration definitions
for every release after the first. On 2026-10-22 the owner also approved independent
release bundles, pinned cross-version references, and destination-owned migration
definitions. Identifier syntax remains open. Other recommendations remain proposals.

| Decision | Questions still to resolve | Issues |
| --- | --- | --- |
| Migration publication and predecessor | Placement and explicit predecessor references approved; root catalog, branches, prereleases, and history verification remain open | #194/#195 |
| Release compatibility | Initial 0.1.0 policy; exact patch invariants; minor/major meaning; advisory changes; corrected migrations and remediation | #194/#193/#195 |
| Resource identity and installation | Stable standard identity, exact references/digests, dependency closure, offline installation, updates, namespaces, and adoption storage | #192/#194, coordinate #135/#184 |
| Population ownership | Preserved versus explicitly rebound selectors; local paths, empty populations, target coverage, and required collection presence | #192/#193/#196 |
| Binding cardinality and modes | One/many local rules; overlapping populations; aggregate policy guarantees; per-role modes and mixed adoption; optional roles/profiles | #192/#193/#195 |
| Structural proof | Supported schema/type/selector/policy comparisons, relationship identities, contradictions, and proven/incompatible/unavailable evidence | #193, coordinate #186 |
| Migration and strategy language | Literal paths and operations; missing/null/arrays; body/file/reference changes; conflicts, loss, identity migrations, and manual steps | #195/#196 |
| Adapting local contracts | How a standard migration interacts with custom local rules, stronger requirements, adapters, and adoption-state changes | #192/#193/#195 |
| Execution and recovery | Frozen inputs, previews, destination validation, write refusal, partial completion, receipts, retries, and reuse of existing mutation services | #195/#196 |
| Exchange boundaries | Single records versus bundles, role labels, stable record identities, targets/attachments, repeated imports, collisions, local edits, extensions, and preservation | #196/#195, coordinate #186 |
| Format and compatibility handoff | Concrete syntax, required capabilities, mdrule format impact, unsupported readers, immutable schemas, fixtures, and implementation slices after approval | All, coordinate #184/#135 |

Work through one decision at a time with a concrete example, record the owner's
answer and its consequences across affected issues, and update this checklist.
Continue with resource resolution in RFC 0005; migration placement and explicit
predecessor references are already approved. Operation syntax and version-numbering
policy still need separate decisions.

First proposed example: release 0.2.0 declares predecessor 0.1.0 and references
`migrations/from-0.1.0.json` inside its own release. The next release 0.2.1 declares
0.2.0 as its predecessor and supplies an explicit identity migration if no data
changes are needed. A root catalog may advertise these edges without owning their
definitions. Choosing a predecessor explicitly avoids assuming publication order
or version sorting uniquely determines it when maintenance branches exist.
Destination ownership and pinned predecessor references were approved on
2026-10-22. Identity-migration representation, branch selection constraints,
and extra supported source versions remain to be settled.

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
- Major-version compatibility meaning remains unsettled; the owner's subsequent
  clarification above requires migration definitions for major releases too.

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

Earlier version-policy alternatives (migration optionality is superseded by the
2026-10-22 requirement above):

| Policy | Minor release | Major release |
| --- | --- | --- |
| Recommended SemVer compatibility model | During `0.x`, contract changes may break compatibility; after `1.0`, additions preserve declared compatibility | Establishes stability at `1.0`; later majors may break compatibility; migrations permitted |
| Original migration-continuity model | Contract changes may break compatibility but must include migration recipes | Historically proposed optional recipes; superseded by required predecessor migration |

The second is a legitimate custom policy, but should not claim ordinary SemVer
compatibility semantics after `1.0`. The existence of a recipe also does not
guarantee successful migration for every collection, so it is a weak proxy for
compatibility.

Every release after the first must now define its predecessor migration,
independently of compatibility classification. Recommend distinguishing executable
transformations and explicit identity migrations. Whether and how a definition
may include manual steps remains #195 work; a missing definition is not an
acceptable substitute. Major-transition migration definitions are required too.

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

Publication layout approved by the owner on 2026-10-21: each standard release
has its own directory containing the standard definition and separate `rules/`,
`types/`, and `schemas/` resources. Subsequent approval on 2026-10-22 settles
independent release bundles and destination-owned migration placement, but not
the complete adoption specification. All referenced dependencies
must be available; a type that does not constrain frontmatter need not introduce
a frontmatter schema solely to fill the directory layout.

### Independent releases and migration placement: approved model

Owner approval, 2026-10-22: keep incoming migration declarations in the **destination standard
file**, with operation definitions in separate files inside that release's
`migrations/` directory. Each version describes how to reach itself; an older
release does not need advance knowledge of later releases.

Each version is independently publishable and downloadable. The shared parent
directory below is only a possible hosting layout; versions need not share a
folder, server, or bundle. A release contains its own contract's complete rule,
type, and schema dependencies and its incoming migration definitions. It does
not recursively bundle predecessor releases or all historical versions.

An explicit predecessor reference identifies the standard, exact release,
retrieval location, and expected content digest. A version string alone is
insufficient. Identity is separate from retrieval location. Exact identifier
syntax, reference serialization, and digest algorithm remain design decisions.

Adopting a release from scratch needs only that release's contract dependencies.
Preparing a migration additionally obtains the source contract and any intermediate
release and operation dependencies required by the chosen route, reusing installed
resources where available. A resolved migration must retain those inputs for
offline execution. It need not download unrelated historical releases.

```text
md-recipes/
  migrations.json                 optional discovery catalog
  0.1.0/
    recipes.mdstandard.json       initial release; no incoming migration required
    rules/
    types/
    schemas/
  0.2.0/
    recipes.mdstandard.json       declares the 0.1.0 → 0.2.0 migration
    migrations/
      from-0.1.0.json             operation definition referenced by this release
    rules/
    types/
    schemas/
```

The filenames above illustrate placement, not an approved migration file format.
A declaration identifies the migration, supported source standard/release and
contract revisions, exact destination release, operation resource and digest,
and required executor capabilities. A resolved operation pins concrete source
and destination artifacts even if discovery permits a source range. Operation
definitions carry ordered declarative transformations and explicit preconditions,
conflict/loss behavior, and destination validation requirements; #195 owns their
language and execution semantics. For example, renaming `title` to `name` needs
literal property paths and an explicit existing-destination conflict policy.
It cannot silently overwrite an existing `name` or invent a missing title.

A root-level `migrations.json` could index published edges to help find a route,
but should not be the mutable authority for execution. Its entries would point
to immutable destination declarations and pinned resources. Installing a chosen
route must retain every required release and operation dependency for offline
execution. A catalog change must not change an already resolved plan. Whether a
catalog is needed at all, and its format, remain #194 decisions.

This destination-owned arrangement permits publishing 0.2.0 without editing
0.1.0. Correcting a published migration requires a new immutable artifact; the
existing proposal uses a destination patch release, as discussed below. Repairing
data already damaged by the old migration remains a separate remediation task.

The mdstandard **definition schema** validates migration declarations; it should
not be republished for each author's standard release. The operation-language
schema is likewise distinct from individual authored migration definitions.

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

## Standard-version migration semantics (#195)

### Declarative actions and staged files: owner direction, 2026-10-23

Standard authors define migrations in JSON; adopting users define import/export
strategies in JSON. md-utils interprets a closed, versioned set of supported
actions on text files and structured values. Definitions MUST NOT supply arbitrary
code: no shell commands, subprocess hooks, dynamically loaded plugins, evaluated
scripts, or executable template escape hatches. Merely serializing instructions
as JSON is not sufficient; every operation and operand must have specified,
bounded semantics, and unsupported actions must be rejected. Exact operation
names and the initial operation set remain to be designed.

The default transformation workflow writes proposed file contents to a separate
staging directory without replacing original files. The user reviews these files
and then invokes a separate apply command. Apply installs the reviewed staged
contents rather than rerunning the transformation definitions. After successful
completion it deletes the staging directory. This direction applies to standard
migrations and user-owned import/export strategies; it is not an implementation
claim or approval of concrete CLI syntax. Export apply publishes to the explicitly
chosen export destination, not back into the original collection.

Clarification, 2026-10-23: cleanup is performed by the apply command itself,
not a separate command the user must run. Generate a persistent Markdown review
report with fenced `diff` hunks and nearby context in addition to CLI summaries.
Manual edits of staged files are approved with renewed validation and review;
the owner permits dropping that feature if its design proves too complex. See
[RFC 0005](rfcs/0005-mdstandard.md) for report examples and the proposed review
contract. The closed md-utils operation vocabulary confirms the owner's original
intent; JSON is not a mechanism for executing author-supplied code.

Recommended safeguards to complete this design (details pending):

- The invoking user supplies allowed source and destination roots. Definitions
  select within those boundaries; they cannot grant themselves access to arbitrary
  files, follow escaping symlinks, execute code, or fetch arbitrary network data.
  Dependency acquisition is separate from transformation execution. Internal
  metadata, receipts, and the staging directory are excluded from ordinary input
  discovery. No installation can implicitly authorize applying a migration.
- A staging manifest records exact definitions/dependencies, original file hashes,
  destination paths and expected existence, staged hashes, and explicit proposed
  creates/replacements/deletions. Absence from the staged tree never means deletion.
  The first operation set need not support every kind of file mutation.
- Preview and destination validation assess the staged replacements together with
  unchanged collection records, including relationships and stronger local rules.
  Staging does not change the collection's declared adopted version.
- Apply preflights the whole batch, then rechecks authoritative source/destination
  revisions and staged contents before each write. Changed originals, conflicting
  new destinations, changed supporting definitions/evidence, or changed staged
  content require renewed validation/review rather than silent overwrite. Manual
  editing is provisionally approved; exact review mechanics remain to be specified.
- Reuse native writer coordination, atomic per-file replacement, durable receipts,
  and retry/recovery facilities where their semantics fit. A staging directory
  does not provide a transaction across all files or prevent external editors
  from writing. Stop on failure and report completed and remaining work.
- Delete staging only after all intended writes and completion bookkeeping are
  confirmed. Retain staging on conflict, interruption, or partial completion.
  Cleanup must target only the verified operation directory; unrelated files must
  not be removed. A cleanup error after successful writes is reported separately
  and must not cause retry to repeat transformations.
- Staging is preview, not backup. Recommend retaining original bytes and recovery
  receipts separately before replacements, so successful staging cleanup does not
  erase the only recovery copy. Backup retention and restoration policy are open.

The restriction removes arbitrary-code execution from the operation language;
it does not prove the interpreter has no bugs or that authorized transformations
cannot lose data. Bound file sizes, output growth, iteration, and operation counts.
Preserve untouched bytes and disclose serialization changes in the preview.

### Operation semantics still to resolve

Recommend starting with bounded structured-frontmatter operations and explicitly
specified text operations. A rename is a move between literal property paths. Use typed key/index
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
3. Freeze selected records and revisions; generate deterministic proposed contents
   in the separate staging directory, retaining a manifest of exact inputs/outputs.
4. Assess the result against the destination contract and relevant local policies.
   Unknown coverage must not be reported as successful migration.
5. Present staged files and a diff with conflicts, validation findings, and exact
   recipe identity for user review.
6. Apply through a separate explicit command, recheck authoritative revisions and
   reviewed staged bytes, and record per-file receipts.
   Report partial completion and support recovery; do not promise collection-wide
   atomicity that the existing persistence model does not provide.
7. Update adoption state only after the relevant destination assessment succeeds;
   interrupted work needs an explicit incomplete state, not a false version claim.
8. Delete the staging directory after confirmed completion; retain it on partial
   completion or failure. Keep any separately retained backups and recovery receipts.

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
4. How do mandatory predecessor migration definitions represent executable,
   identity, and any permitted manual steps?
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
