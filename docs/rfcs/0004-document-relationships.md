# RFC 0004: Named Document Relationships and Collection Policies

- Status: Provenance delivered in #175; lexical constraints in #176; named relationship runtime in #177; collection policies in #178; repairs and persisted dependency invalidation pending #179–#180
- Date: 2026-10-12
- Tracking: [#172](https://github.com/DandyLyons/md-utils/issues/172), [#169](https://github.com/DandyLyons/md-utils/issues/169)
- Depends on: [RFC 0003](0003-semantic-string-formats.md), implemented through #173/#174
- Coordination: [#135](https://github.com/DandyLyons/md-utils/issues/135), [#184](https://github.com/DandyLyons/md-utils/issues/184), [#70](https://github.com/DandyLyons/md-utils/issues/70)
- Reserved definition versions: unified mdtype `"2"`; explicit mdrule `"1"`

## Purpose and implementation boundary

The #177 implementation is documented in [named relationships](../relationships.md).
It implements declaration/query/required-conformance evaluation and reuses indexed
source evidence without caching cross-document assessments. Collection policies
are implemented by #178; see [relationship policies](../relationship-policies.md).
The repair and invalidation sections describe subsequent work. Publication/default
activation remains independent of runtime implementation.

Specify explicitly named frontmatter relationships and collection consistency
policies. A type can require that `authors` contains whole wikilinks to documents
conforming to `Person`; a rule can select articles that must satisfy that type.
Assertions describe stored data, not truth about the world. Property names such as
`spouse` carry no built-in meaning. No relationship, type, inverse, or repair is
inferred from arbitrary values or names.

MUST, MUST NOT, SHOULD, and MAY describe the future implementation contract. This
RFC reserves formats and defines acceptance examples; it does not enable runtime
support, publish schemas, change authoring defaults, or complete the implementation
epic. Existing mdtype v1 and project-selected rule semantics remain unchanged.
Design revision (2026-10-13): relationships, RFC 0003 semantic scalars, and #176
wikilink constraints share mdtype v2. This supersedes the earlier reservation of
v3 for relationships. Existing scalar-only v2 readers implement a subset, not the
complete contract. The relationship examples below require future capable readers.

## Ownership and evaluation stages

- **mdtype** owns named property/reference contracts and destination conformance.
- **mdrule** owns source applicability and collection policies over named relations.
- **Core** owns portable selection, assessment, evidence composition, and policies.
- **Hosts** supply bounded records, resolution evidence, resource bindings, revisions,
  and coverage. Core performs no implicit filesystem, database, or network access.
- **Native/index/server adapters** use the same semantics. The index is a disposable
  cache; it is neither the source of document truth nor the owner of policy meaning.

The stages are selection, whole-value syntax validation, destination resolution,
destination-type assessment, and collection policy evaluation. Later stages MUST
NOT relabel earlier failures. A valid scalar with unavailable collection context
is not a broken link. Querying an assertion does not prove that it conforms.

## mdtype declaration

Version `"2"` combines RFC 0003's scalar contract with an optional top-level
`relationships` object. Keys are nonempty, case-sensitive names without surrounding
whitespace, unique within the declaring type. A relationship's identity is the
declaring type identity plus its local name; it is not a dotted string assembled
from arbitrary names. Registry uniqueness and opaque authored type versions retain
RFC 0001 semantics. Definitions do not inherit or merge relationships implicitly.

```yaml
md-utils-type-schema: "2"
requires: [document-relationships]
name: Article
version: "1.0.0"
frontmatter:
  presence: required
  schemas:
    - inline:
        type: object
        required: [authors]
        properties:
          authors:
            type: array
            minItems: 1
            items: { type: string, format: Wikilink/Obsidian }
relationships:
  authors:
    select: [authors, { each: true }]
    target: { type: person.mdtype.yaml }
    cardinality: { min: 1 }
    embeds: forbid
    anchors: forbid
body: { requirements: [], recommendations: [] }
context: { requirements: [], recommendations: [] }
```

All relationship objects reject unknown fields. Their complete envelope is:

A definition containing `relationships` MUST declare `document-relationships` in
its top-level `requires` array, following RFC 0003's capability gate. If its loaded
schemas also contain wikilink policies, it MUST additionally declare
`wikilink-constraints`. Unsupported capabilities and missing gates fail compilation;
missing collection context during an otherwise supported assessment remains
unavailable. These are different conditions.

| Field | Contract and default |
| --- | --- |
| `select` | Required nonempty sequence of selector steps defined below |
| `target` | Required object containing exactly `type`, a definition resource reference |
| `cardinality` | Optional object with nonnegative integer `min` (default 0) and `max` (default unbounded); `max` MUST be at least `min` |
| `duplicates` | `allow` (default) or `forbid`, by resolved document identity |
| `nulls` | `forbid` (default) or `ignore` at terminal selected values |
| `embeds` | `allow` (default) or `forbid` |
| `anchors` | `allow` (default) or `forbid` |
| `severity` | `error` (default) or `advisory` for this relationship's checks |

`target.type` uses RFC 0002's explicit type-resource references, relative to the
host's types resource root, not the declaring file's directory. Require a recognized
mdtype suffix and confinement; do not search by basename. Portable hosts provide
equivalent explicit resource bindings. The referenced type may be v1 or v2 if
supported by the reader. Load all reachable definitions before assessment; absent
definitions, duplicate names, invalid references, and unsupported versions are
configuration errors. Type hints on destination records are not evidence of
structural conformance. No target expression or relationship-level negation is
introduced in this version.

### Property selection, shape, and cardinality

Selection starts at the frontmatter object. A string step selects an exact literal
object key, including keys containing periods or slashes. The object step
`{ each: true }` selects every array element in index order. No other step forms,
recursive descent, predicates, key wildcards, implicit flattening, coercion, or prose
scanning are supported. For example:

- `[spouse]` selects one scalar property.
- `[authors, { each: true }]` selects each author.
- `[contributors, { each: true }, person]` selects each contributor's `person` key.

A missing key yields no selections on that branch. An absent frontmatter block is
an empty object for selection; frontmatter presence constraints still apply.
An object-key step on a non-object or an `each` step on a non-array is a selection
shape failure, including intermediate nulls. Terminal null is a failure unless
`nulls: ignore`, in which case it contributes no assertion. Every other terminal
value contributes one occurrence; nonstrings and malformed strings remain failed
occurrences rather than disappearing through filtering.

Malformed or unreadable frontmatter is not an absent frontmatter block. Retain its
existing parse/read diagnostics and report unavailable selection; never substitute
an empty object to obtain a vacuous relationship pass.

JSON Schema owns ordinary object/array shape, key presence, and per-item
requirements. Relationships are additional conjunctive checks, never overrides:
`nulls: ignore` cannot make a schema-forbidden null valid. Use schema `required` to
require a key while allowing an empty array; use relationship `cardinality.min`
to require a number of selected occurrences across the selector. Optional missing
properties pass the default minimum of zero. Intermediate missing keys must be
required by the containing object schema if their absence is itself invalid.

Cardinality counts selected occurrences after explicit null removal, before syntax
validation or resolution. Two spellings of the same destination count twice.
`duplicates: forbid` separately rejects two uniquely resolved occurrences pointing
to the same document, irrespective of alias or fragment. Incomplete resolution
cannot prove destination uniqueness. An incomplete selection cannot establish a
passing minimum or maximum; a known excess over the maximum remains a failure.
Malformed values cannot satisfy the relationship merely by satisfying its count.

### Wikilink syntax, embeds, anchors, and identity

Every non-null selected value MUST contain exactly one whole
`Wikilink/Obsidian` scalar under RFC 0003. Reuse the existing Wikilink model and
Parsing-based grammar, not the scanner that finds links inside arbitrary prose.
Surrounding whitespace and trailing prose fail. Preserve original text, alias,
target spelling, embed flag, and heading/block fragment.

Aliases do not affect resolution or graph identity. Allowed embeds assert ordinary
directed document edges. Allowed anchors refer to the destination document for
type assessment and policy purposes; this RFC does not assert that the heading or
block exists. Forbidden anchors/embeds produce dedicated contract failures. An
anchor-only link targets the source document, which must belong to the snapshot.
Fragment existence and target-style spelling constraints are separate capabilities;
the latter remain owned by #176, whose anchor-only style is named `self-anchor`.

Those lexical constraints live in mdtype frontmatter schemas under RFC 0003,
not in a second relationship-style envelope. A relationship does not implicitly
require a target spelling. Explicit `links convert` operations remain available;
validation itself never converts. Filesystem absolute-path support is deferred.

Resolution preserves #170: slash-containing paths are root-relative unless prefixed
by `./` or `../`; explicit paths never fall back to basename lookup. Bare names use
the existing case-insensitive filename matching. Omitted extensions consider only
`.md` and `.markdown`; explicit attachment extensions remain exact. An attachment
may resolve, but an unsupported document representation yields unavailable target
assessment, not fabricated Markdown conformance.

A document identity is a host-supplied stable key within one collection snapshot,
normally a confined collection-relative path. It is not an alias, fragment, type
hint, or an assumed UUID. Duplicate UUID values do not merge vertices. Cross-snapshot
moves require host-confirmed identity evidence or invalidation, never guessing.

## Provenance and result contract

Extraction and queries MUST retain all selected occurrences, including invalid or
unresolved ones. Each occurrence carries:

- Collection/snapshot identity, source document identity and revision.
- Declaring type name, authored version, definition resource revision, relationship
  name, and declaration location.
- Concrete frontmatter property path and every array index; original value/text;
  source range when available, with its coordinate convention explicitly identified.
- Parsed target, alias, embed, and fragment when syntax permits.
- Resolution status, all known candidates, candidate-coverage evidence, and the
  unique destination identity/revision when established.
- Target type assessment, contributing causes, severity, and relevant dependency
  and coverage evidence. Unavailable byte ranges MUST NOT be fabricated.

These are declared-relationship selection requirements for #177. The #175 discovery
API finds syntactically recognized links in strings; it does not enumerate malformed
selected relationship values or establish conformance. Reuse its property/source
provenance without substituting scanner matches for whole-value selection. Decoded
frontmatter ranges are not raw-file byte ranges; frontmatter edits use structured
paths and codecs when raw ranges are unavailable.

Outgoing queries retain failed occurrences. Incoming queries use established
destination identities and retain the asserting source property and relationship;
ambiguous candidates MUST NOT be presented as confirmed incoming edges. A query
may expose candidate backlinks separately with their uncertainty explicit. Multiple
occurrences remain distinguishable even when graph algorithms collapse parallel
edges for reachability.

Results use `pass`, `fail`, or `unavailable`, separately from severity and reason.
`unavailable` never means ordinary nonconformance. A boolean convenience result
may report conformance only for `pass`; machine-readable output MUST retain the
three-way distinction. Configuration errors prevent valid compilation and are not
record failures. Evaluator errors remain distinct causes even when a final result
is already a definite failure.

| Stable diagnostic code | Meaning |
| --- | --- |
| `relationship.selection.shape` | A selector encountered the wrong container kind |
| `relationship.value.invalid` | Terminal nonstring, forbidden null, or invalid whole-value syntax; preserve RFC 0003 causes |
| `relationship.cardinality` | Proven occurrence-count violation |
| `relationship.embed.forbidden` / `relationship.anchor.forbidden` | Explicit authored restriction violated |
| `relationship.target.unresolved` | Complete relevant resolution scope proves no candidate |
| `relationship.target.ambiguous` | At least two candidates are established; candidate listing may be incomplete |
| `relationship.context.unavailable` | Required record, resolution coverage, capability, or context is unavailable |
| `relationship.target.nonconformance` | Destination required checks definitely fail |
| `relationship.target.duplicate` | Forbidden duplicate destination identity |
| `relationship.evaluator.failure` | Evaluator/host operation failed; never converted into nonconformance |
| `relationship.limit.exceeded` | A declared resource budget prevented completion |
| `relationship.policy.cycle` / `relationship.policy.self-link` | Explicit graph policy violation |
| `relationship.policy.reciprocity` / `relationship.policy.inverse` | Required return assertion is provably absent |
| `relationship.policy.conflict` | Incompatible policy obligations; include all policy origins and any witness |
| `relationship.definition.invalid` / `relationship.definition.capability` | Invalid or unsupported authored contract |

Required failures prevent conformance; required unavailable checks prevent a claim
of conformance without being reported as failures. Advisory outcomes remain visible
but do not prevent type conformance. Invalid declarations are never downgraded by
advisory severity. Report deterministic causes and cycle witnesses with participating
document/property paths, not only a summary count.

## Bounded collection context and coverage

A host supplies a coherent snapshot with a collection identity/root, record and
definition revisions, resolution semantics, coverage certificates, and explicit
finite budgets. Coverage must identify its scope and generation; it is not a single
unqualified boolean. At least distinguish source enumeration, candidate namespace
coverage, individual record availability/selection completeness, and policy graph
coverage. Access-denied, skipped, truncated, or stale portions remain unavailable
unless explicitly outside the declared universe.

Zero candidates establishes unresolved only with complete relevant candidate
coverage. One candidate establishes unique resolution only with that coverage.
Two established candidates prove ambiguity even if more might exist. For an exact
path the relevant coverage may be a bounded set of exact extension candidates; a
basename lookup requires coverage of its whole permitted candidate namespace.
Do not require an unrelated full-vault scan when narrower evidence is sufficient.

Partial source discovery may support individual results and witnessed violations.
It cannot establish absence of incoming links, collection-wide acyclicity,
uniqueness, or universal reciprocal consistency. A missing reciprocal can be proven
from complete extraction of the particular target relation and complete resolution
of its possible return links; it does not inherently require enumerating unrelated
documents. A return link with incomplete resolution evidence, or an ambiguous
candidate set that could include the source, can prevent that proof. A definitively
unresolved target under complete coverage is not a possible return to the source.

Hosts MUST bound records, bytes, occurrences, resolution candidates, loaded
definitions, dependency nodes/edges, policy traversal, and diagnostic output. Limits
and any truncation are observable. Exhaustion yields unavailable for dependent
checks; a known violation remains valid. Diagnostic truncation alone does not erase
an already established outcome, but MUST be disclosed. Cancellation aborts the
assessment and MUST NOT publish a completed result. Mixed snapshot generations or
revisions cannot be combined into a passing certificate; retry coherently or return
unavailable. Concrete default budgets require measurements in implementation work.

## Terminating recursive conformance

Document cycles and definition-resource cycles are different. Existing cyclic
JSON Schema resource rejection remains unchanged. Relationship target references
may form cyclic definition graphs: load each definition once and bind references
after discovery. They are not schema-resource expansion and MUST NOT be rejected
solely for revisiting a type.

The unit of recursive assessment is `(snapshot, document identity and revision,
type identity and definition revision, evaluator profile)`. Required relationships
create positive dependencies on the full required conformance of their destination
types. Local schema/body/context checks run with their normal semantics. Collection
policies do not feed back into type conformance. Advisory relationship checks are
evaluated separately against the completed required-assessment graph; they cannot
create required obligations or recursively demand other advisory results.
If an advisory references a destination/type not yet assessed, add it as a separate
root of required assessment and solve its reachable required graph by the same
algorithm. Do not recursively expand that destination's advisories. The advisory's
result never becomes a required dependency of its source.

For every required-assessment node, construct the equation:

```text
result(node) = ALL(local required checks,
                   selection/syntax/resolution/cardinality checks,
                   result(each required uniquely resolved destination/type))
```

`ALL` is conjunction over the order `fail < unavailable < pass`: a definite failure
dominates; otherwise unavailable dominates; an empty conjunction passes. Missing
context and evaluator failures contribute unavailable constants with distinct causes.
Unresolved or ambiguous resolution contributes a failure only when established as
specified above. Never create speculative dependency edges from ambiguity candidates.

Evaluate the **greatest fixed point** of these positive equations on the finite
reachable graph. Use strongly connected components or an equivalent worklist:
fully discover each component's obligations, initialize its internal assumptions
to pass, then lower values until stable, incorporating already evaluated external
dependencies. Internal assumptions are not observable assessment results. Each
node can lower at most twice; budgets also bound graph construction. A revisit
records an edge, neither success nor failure. An unexpanded obligation contributes
unavailable, not an omitted edge. Publish only after convergence.

This deliberately permits structurally valid mutually referencing documents:

| Required graph and local evidence | Fixed-point result |
| --- | --- |
| A → B → A, all local checks pass and coverage is sufficient | Both pass |
| Same cycle, B's required property fails | Both fail, preserving B's cause |
| Same cycle, B's required context is unavailable | Both unavailable |
| Same cycle, B has both a definite failure and unavailable evidence | Both fail; retain unavailable causes |
| A → A, local checks pass | Pass; an opted-in self-link/cycle policy may fail separately |
| A → B is advisory, B fails | A's required result is unaffected; advisory identifies B's failure |

Target declarations accept only a named type in this version, so recursive
dependencies are positive. Do not introduce `not`, `oneOf`, conditional target
selection, or other non-monotone cross-document dependencies through programmatic
APIs. Such declarations require a future contract and currently fail compilation.
Ordinary local JSON Schema composition remains supported. Existing rule type
expressions run after required type results converge: `allOf` fails on any fail;
`anyOf` passes on any pass; `not` swaps pass/fail and preserves unavailable;
`oneOf` fails for two or more passes, is unavailable if any remaining unknown could
change the answer, and otherwise passes exactly one pass. Evaluator failure never
becomes evidence for negation.

## mdrule extension and relation binding

Reserve explicit `md-utils-rule-schema: "1"` for the first independently versioned
rule language. It inherits current standalone `name`, `match`, `types`, `creation`,
and optional `$schema` fields and adds optional `relationshipPolicies`. `types`
remains required. Unknown fields are invalid. Omission of the version discriminator
continues to select legacy project-version semantics and rejects the new fields.
The discriminator, not `$schema`, selects execution semantics. No config version
bump is implied merely by referencing a supported new definition.

A relation reference is exactly `{ "type": "person.mdtype.yaml", "name": "spouse" }`.
Resolve the resource explicitly and bind to its declared type and relationship.
Unknown names/resources are configuration errors. Policy references load the
definitions they need independently of the rule's `types` expression. Policies do
not assign those types to records, nor silently require their conformance. Extraction
uses the referenced declaration even when its containing type does not conform;
otherwise violations could vanish by filtering out malformed records.

```json
{
  "md-utils-rule-schema": "1",
  "name": "people",
  "match": { "paths": ["People/**/*.md"] },
  "types": "person.mdtype.yaml",
  "relationshipPolicies": [
    {
      "id": "spouse-return",
      "kind": "reciprocity",
      "relation": { "type": "person.mdtype.yaml", "name": "spouse" },
      "scope": "selected",
      "severity": "error"
    }
  ]
}
```

Each policy has a required nonempty `id`, unique within its rule, a `kind`, and a
required `scope`. The full policy envelope is the common fields plus exactly the
kind-specific fields below; reject other fields and duplicate relation references.
There is no precedence by file order and no overriding another rule's policies.
Absent `relationshipPolicies` means no graph constraints.

The rule result combines its existing type-expression obligations on selected
records with all error-severity policy outcomes using `ALL`. Advisory policy
outcomes do not alter that result. Retain per-record type evidence separately from
collection policy evidence; a policy failure does not retroactively make a
destination fail its mdtype. Unknown source membership or incomplete source
enumeration prevents a passing collection-wide rule result unless the missing
portion is proven irrelevant to every obligation.

### Scope and graph construction

Rule `match` selects source seeds independently of type conformance. An unavailable
match is unknown membership, not a nonmember. Resolution always uses the explicitly
supplied collection universe; rule path filters MUST NOT silently shrink basename
resolution coverage.

- `scope: selected`: graph vertices are the matched source records. Only edges
  whose source and destination are both selected participate in graph policies.
- `scope: reachable`: start with matched sources and close over outgoing edges of
  the policy's bound relations, within the collection universe. A reached record
  need not itself match the source rule. Closure must be bounded and complete for
  a passing global result.

For reciprocity, the graph binds the one named relation; for inverse policies, it
binds both `from` and `to`; cycle and self-link policies bind their `relations` list.
Unknown membership, unreadable records, incomplete extraction, and resolution
uncertainty remain graph gaps. Graph construction retains all uniquely resolved
assertions regardless of destination-type failure or forbidden anchor/embed flags;
those failures are reported separately and do not hide witnessed policy violations.
Invalid syntax cannot establish an edge and remains a gap for proofs of absence.

Edges leaving a selected scope are reported as boundary edges and excluded from
that policy, including return obligations. They still undergo mdtype reference
assessment. Use reachable scope when obligations must include those destinations.
An empty, completely enumerated scope passes vacuously, with zero checked records
reported. An incompletely enumerated empty sample is unavailable, not global success.

### Policy kinds

| `kind` | Required kind-specific fields | Semantics |
| --- | --- | --- |
| `cycles` | Nonempty `relations` list; `mode: allowed`, `discouraged`, or `forbidden` | Directed cycles in the union of those labeled relations; discouraged produces advisories, forbidden errors, allowed imposes no cycle check |
| `selfLinks` | Nonempty `relations` list; `mode: allow` or `forbid`; optional `severity` | Checks document identity equality for each participating edge |
| `reciprocity` | `relation`; optional `severity` | Every participating A → B assertion requires at least one B → A assertion in the same qualified relation |
| `inverse` | `from` and `to` relation references; optional `severity` | Every participating A —from→ B requires B —to→ A |

`severity` defaults to `error` and accepts `error` or `advisory`; cycle policies
reject it because `mode` already fixes severity. `allowed` and `allow` are local
no-op declarations, not exemptions from other applicable policies. Cycle permission
does not request graph traversal or require complete graph coverage by itself. It
does not require reciprocity. Reciprocity does not forbid cycles. Inverse is
directional: require a second swapped policy to require every `to` edge to have a
corresponding `from` edge. No return assertions are written automatically.

A self-loop is a cycle of length one. `selfLinks: allow` cannot override a forbidden
cycle policy that includes the same edge. A self-loop satisfies reciprocity by
itself; an inverse obligation on a self-loop still requires the other qualified
relation unless both references are identical. Two different aliases/fragments
pointing to the same document do not constitute different policy vertices.

Parallel occurrences require existence of a return edge, not matching multiplicity;
one return assertion can satisfy multiple occurrences. Cardinality and duplicates
remain independent mdtype checks. A cycle may span several relations only when a
single cycle policy explicitly includes them in its union.

A proven return edge satisfies the particular return obligation even if unrelated
graph coverage is incomplete. Provably no return yields a policy failure; a possible
but uncertain return yields unavailable. A proven unresolved link remains a separate
resolution failure and is not itself evidence of a possible return. Report target contract failures
independently rather than treating a nonconforming but resolved return as absent.
Collection-wide pass requires all applicable obligations and scope coverage; known
violations can be reported without claiming the remaining scope is complete.

### Conflicting policies

Evaluate all applicable policies conjunctively. Emit a definition-level
`relationship.policy.conflict` advisory for provable potentially incompatible
combinations, such as forbidden cycles plus required reciprocity over the same
relation and scope. Empty graphs may satisfy both, so this combination alone is
not an invalid definition. Do not claim arbitrary matcher overlap or satisfiability
has been decided; absence of this advisory does not prove compatibility.

On observed overlapping scope, include a concrete conflict witness when satisfying
a required return would necessarily violate a forbidden cycle, or when existing
edges already witness both obligations' incompatibility. Include both rules/policies,
relations, records, and property paths. The conflict explanation does not invent a
new severity or override outcomes: the original policies determine errors/advisories.
Identical checks may share computation but retain all declaration provenance.
Conflicting suggestions MUST NOT yield an automatically applicable repair.

## Dependency tracking and indexed correctness

An assessment's dependency certificate MUST include, or conservatively cover:

- Source record revision and extracted property occurrences.
- Target revisions and transitive required type dependencies, including components
  of mutually dependent records.
- Type/schema resource identities, authored definitions, relationship declarations,
  policy declarations, and resolved definition bindings.
- Successful, ambiguous, and unsuccessful resolution query keys and their candidate
  namespaces, including extension rules, collection root, and source-relative base.
- Scope membership and incoming/outgoing graph dependencies, including nonmembers
  whose changed contents could make them members, and newly discovered records.
- Coverage/snapshot generation and extractor/resolver/evaluator profile versions.

A new duplicate basename invalidates previously unique resolution even when neither
the source nor the old target changed. Removing candidates can repair ambiguity.
Creation can repair a previously unresolved link. Moves change old/new candidate
namespaces and the relative base of links in moved sources. Deletion, target content
edits, definition edits, membership changes, and coverage changes propagate through
dependent components and policies. Negative lookups are dependencies too.

Implementations MAY invalidate a broader scope or the whole relationship generation
instead of maintaining minimal edges. They MUST NOT reuse source-only freshness as
proof of relationship freshness. Reuse existing bounded staging and generation-checked
publication; failed refreshes cannot advertise stale assessments as current. Direct
and indexed results must agree for equivalent records, coverage, profiles, and budgets.

Indexed-only results retain limited coverage and cannot certify global consistency
without the necessary independent coverage evidence. Rebuild discards derived graph
data and reassesses from documents while preserving durable drafts and receipts.
Mutation-triggered refresh, failure recovery, and stat-preserving changes follow
existing revision/hash verification contracts. Cached relationship validation MUST
remain disabled until #180 verifies these guarantees; uncached support may ship first.

## Fix-Its and mutations

Validation and queries remain read-only. #179 must reuse #70/RFC 0001's shared
`MarkdownDiagnostic`, `MarkdownFixIt`, safety classifications, record edits, preview,
and post-edit reassessment. A reciprocal/inverse requirement does not authorize
fabricating a real-world assertion: adding a return link requires explicit review
and is not an `automatic` fix accepted merely by `--yes`.

Suggestions must retain source/target revisions, originating policy, uncertainty,
and conflicting obligations. Advisory suggestions require explicit opt-in. Use
existing mutation policy, drafts, writer coordination, receipts, and recovery for
selected writes; do not introduce a second repair engine or promise multi-file
atomicity. Report partial completion and reassess affected relationships. This RFC
does not expand #70's initial missing-property repair implementation scope.

## Versioning, schemas, and migration

mdtype v2 contains the scalar contract in RFC 0003, #176's authored wikilink
constraints, and the relationship envelope above. No separate relationship mdtype
version is reserved. Reserve explicit mdrule
v1 as a new independent discriminator; it is not a renaming of legacy rule formats.
Partial v2 readers MUST reject unsupported declarations rather than silently
ignore them; verify this before activating the combined contract. Existing readers reject explicit
new rule fields; future readers preserve discriminator-free legacy behavior.

Reserve these immutable publication targets (not claims of live availability):

- `https://dandylyons.github.io/md-utils/schemas/mdtype/2/mdtype.schema.json`
- `https://dandylyons.github.io/md-utils/schemas/mdrule/1/mdrule.schema.json`

The schemas must encode the envelopes, enums, required fields, selector steps, and
policy discriminated forms in this RFC. Compilation additionally checks resource
binding, bounds, duplicate names, supported capabilities, and policy interactions.
Shape-valid JSON alone cannot prove semantic validity. A generic JSON Schema
validator does not evaluate cross-document relationships. The combined v2 contract
retains RFC 0003's semantic format registry/profile; relationships do not change scalar
defaults. New immutable bundled schemas and public copies are implementation work;
do not edit previously published versioned schemas to introduce these fields.

Migration is explicit and previewable. A supported v1 mdtype may opt into v2
without adding relationships, but must first pass RFC 0003's reserved
format-namespace compatibility checks. Adding declarations requires user authorship;
never infer them from existing wikilinks or property names. A supported standalone
legacy rule may explicitly adopt mdrule v1 with its existing fields unchanged.
Preserve legacy artifacts and reject unsupported features rather than dropping them.
Downgrade refuses relationships/policies unless the user explicitly removes them;
remaining v2 features still require their own downgrade checks.

Scalar-only v2 definitions need no version change to add relationships deliberately.
This does not make existing scalar-only binaries compatible with those declarations.
The approved top-level `requires` capability gate is specified in RFC 0003.
The combined release must document minimum reader support and test unsupported
capability rejection, including #176 keywords in referenced schemas. Reconcile any
already-published v2 artifacts with #184 without overwriting immutable publication
history. Implementation milestones and cache fingerprints are not substitutes for
this reader-compatibility work.

Coordinate migrations, canonical schema sources, DocC/help/skill updates, and
release activation with #135. #184 records planned versus implemented read/write
support, defaults, platform capabilities, and evaluator invalidation. Neither this
RFC nor publication advances package/config/server versions, schema aliases, or
initialization defaults. Unsupported host capabilities produce explicit capability
errors; absence of collection context at assessment time produces unavailable.

## Acceptance matrix and implementation handoff

These are normative future implementation cases, not claims of executed tests.

| Case | Required evidence/outcome | Owner |
| --- | --- | --- |
| `authors: ["[[Bob]]", "See [[Alice]]"]` | Index 1 syntax failure retained; index 0 assessed independently | #173/#175/#177 |
| Nested literal keys, arrays, missing intermediate key, wrong container, explicit null | Exact paths; specified selection/shape/null behavior; no filtering away malformed values | #175/#177 |
| Missing optional relation / present empty required array | Minimum zero can pass / schema or declared minimum fails as authored | #177 |
| Two aliases of the same document | Two occurrences; one graph vertex; duplicate policy independent | #177 |
| Anchor-only link, embed, alias, heading/block fragment | Original syntax preserved; explicit restrictions; document-level identity | #177 |
| Explicit path with same-basename file elsewhere | No fallback; #170 resolver behavior preserved | #177 |
| No context; zero/one candidates in partial namespace; two candidates | Unavailable; unavailable; ambiguous with coverage metadata | #177 |
| Target claims Person but violates its structure | Target nonconformance, not nominal success | #177 |
| Mutually recursive conforming records / one failing record / unavailable dependency | Pass / propagated failure / propagated unavailable after convergence | #177 |
| Cyclic definition references versus cyclic schema resources | Relationship graph supported; existing schema cycle restriction retained | #177 |
| Cycles allowed / discouraged / forbidden | No violation / advisory / error with witness | #178 |
| Self-loop; reciprocal pair; asymmetric inverse | Separate cycle/self checks; return existence; directional inverse semantics | #178 |
| Selected boundary edge versus reachable scope | Explicitly excluded boundary / included obligation and bounded closure | #178 |
| Partial graph with observed cycle / no observed cycle | Witnessed violation / unavailable acyclicity, never global success | #178 |
| Complete target relation with no return / uncertain possible return | Missing-return failure / unavailable | #178 |
| Reciprocity plus cycle prohibition | Potential conflict advisory; concrete overlapping witness; no automatic fix | #178/#179 |
| Required type result used in `not`/`oneOf` rule expressions | Unavailable stays distinct; exact composition after convergence | #177/#178 |
| Graph budget exhaustion, cancellation, revision change during fetch | Unavailable or aborted evaluation; no passing partial publication | #177/#178/#180 |
| Added duplicate basename; removed/moved target; new previously missing target | Candidate dependencies invalidate and direct/indexed outcomes agree | #180 |
| Target/definition/policy/membership changes and cyclic dependents | Transitive invalidation, coherent refresh, retained coverage | #180 |
| Indexed-only, failed refresh, rebuild with drafts/receipts | No stale/global success claim; durable user intent preserved | #180 |
| Existing v1/v2 types and legacy rules | Unchanged semantics; explicit unsupported-version/capability rejection | #177/#178/#184 |
| Selected reciprocal repair fails after one write | Revision-checked partial completion and recovery; no fabricated atomicity | #179 |

The issue #172 acceptance criteria map to: **mdtype declaration** and **Provenance**
(selectors, cardinality, anchors, targets); **Result contract** (distinct failures);
**Policy kinds/Conflicting policies** (cycles, reciprocity, inverse, self-links,
scope); **Terminating recursive conformance** (termination and propagation);
**Bounded collection context and coverage** (partial evidence); **Dependency tracking**
(invalidation); and **Versioning/Fix-Its** (schemas, compatibility, #135/#70).

Implementation order: #175 can deliver provenance independently; #177 uses #173,
#175, and the #170 resolver foundation; #178 adds policies; #179 adds reviewable
repairs; #180 is required before cached relationship assessments are enabled.
Verify portable Core/native parity, deterministic results under discovery-order
changes, and direct/indexed parity. macOS tests, Linux CI-only validation, and WASM
checks must substantiate advertised platform support. Public Swift API names,
concrete budget defaults, and CLI command spelling belong to implementation work
and cannot silently change this contract.
