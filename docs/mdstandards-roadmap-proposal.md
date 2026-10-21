# mdstandards GitHub roadmap proposal

Status: issue organization approved and published on 2026-10-21. Design choices
remain subject to the individual issues' design gates.

## Published tracking

- [Epic #191](https://github.com/DandyLyons/md-utils/issues/191): mdstandards — structural interoperability and data exchange.
- [Design milestone](https://github.com/DandyLyons/md-utils/milestone/3): Standards interoperability design; no release number or due date.
- [#192](https://github.com/DandyLyons/md-utils/issues/192): adoption, rule bindings, and conformance modes.
- [#193](https://github.com/DandyLyons/md-utils/issues/193): structural rule conformance and mdrule format impact.
- [#194](https://github.com/DandyLyons/md-utils/issues/194): versioning, publication, and dependency resolution.
- [#195](https://github.com/DandyLyons/md-utils/issues/195): deterministic migrations and user-owned import/export strategies.
- [#196](https://github.com/DandyLyons/md-utils/issues/196): minimal standards exchange contract.

The five design issues are native sub-issues of #191 and belong to the design
milestone. The delivery epic is not assigned to that design-only milestone.
Coordination sections were added to #169, #184, #135, and #186. Existing acceptance
checkboxes and release scope are preserved; no blanket blocking dependencies
were added. The proposal below records the rationale and design-issue scope.

## Recommendation and current roadmap

Create **EPIC: mdstandards — structural interoperability and data exchange** as
a separate follow-on to [#169](https://github.com/DandyLyons/md-utils/issues/169).
Design can proceed alongside mdtype v2 completion. Do not add all standards work
to the current mdtype v2 completion criteria or make it part of the server epic.

| Existing work | Verified state and proposed relationship |
| --- | --- |
| [#169: semantic scalars and relationships](https://github.com/DandyLyons/md-utils/issues/169) | Open; unified mdtype v2 plus independent mdrule v1. Foundation for standards, not its parent scope. |
| [#188: scoped relationship queries](https://github.com/DandyLyons/md-utils/issues/188) | Open and explicitly required by #169. Reuse evidence/selection semantics where applicable. |
| [#171–#180](https://github.com/DandyLyons/md-utils/issues/169) | All closed; specification, scalar, relationship, policy, repair, and cache foundations. #169 still has #180 unchecked, so its checklist is stale. |
| [#184: compatibility matrix](https://github.com/DandyLyons/md-utils/issues/184) | Open; owns cross-format reader/writer/version coordination. Extend its inventory rather than create a second compatibility system. |
| [#135: config 0.3 roadmap](https://github.com/DandyLyons/md-utils/issues/135) | Open; coordinate adoption storage and resource resolution. Explicitly classify standards as follow-on work rather than implicitly expanding its completion scope. |
| [#186: claims-first graph](https://github.com/DandyLyons/md-utils/issues/186) | Open, design gate incomplete. Owns standalone semantics, identities and query bindings; coordinate those boundaries without absorbing standards or blocking on the entire graph epic. |
| [#93: server platform](https://github.com/DandyLyons/md-utils/issues/93) | Host integration reference only; no server standards endpoints are required by this proposal. |

The repository currently has two open milestones: **Semantic metadata foundations**
and **Document relationship validation**. The closed #171–#180 foundation issues
are assigned across them; #169, #184, #186 and #188 have no milestone assignment.
No existing mdstandards issue was found in the open inventory or all-state
standards search. Actual issue state takes precedence over older progress prose.

## Proposed epic body

### Goal

Design and deliver an opt-in standards layer above schemas, types, and rules for
interoperability between collections and external systems. Standards reference
one or more minimum rule contracts. Users explicitly bind supplied or local rules
and adopt at rest or in transit. Preserve existing rule/type semantics and the
separation between authored relationships, conformance, and domain truth.

### Established design intent

- At-rest rule conformance is structural: local obligations may strengthen, but
  cannot weaken, standard obligations within the applicable scope. Multiple
  conformance is allowed; names do not establish it.
- Rule-to-rule conformance and actual document/collection conformance are separate.
- Users may violate a standard; report nonconformance without suppressing claims
  or blocking unrelated operations.
- In-transit adoption uses a user-authored import strategy, export strategy, or
  both. Users own gaps between standard data and their local requirements,
  including stronger requirements in at-rest adoption.
- Standard authors own migrations between standard versions. md-utils executes
  supplied definitions and reports results; neither adoption nor having a strategy
  guarantees universal import or migration success.
- Standards are published JSON/YAML resources with authored release versions.
  Preserve the proposed `0.1.0` starting point and enforcement-invariant patches
  as design inputs; minor/major transition policy still requires resolution.
- Relationships participate through type/rule contracts; standards do not create
  a second graph or relationship evaluator.

### Design gate and scope

The basic direction is agreed; selector ownership, binding cardinality, proof
limits, format versions, mode exclusivity, migration operations, publication,
identity, and exchange boundaries are not settled. Complete the design tasks
below and record project-owner agreement before runtime implementation. This
epic does not authorize a particular mdrule v2 format, remote transport protocol,
graph backend, or recipe/journal standard.

### Acceptance criteria

- [ ] Publish a normative mdstandard/adoption specification and worked examples,
  distinguishing established intent from resolved and deferred choices.
- [ ] Define structural rule conformance, scope, diagnostic evidence, and cases
  the checker cannot establish; do not confuse sample validation with proof.
- [ ] Resolve format impact with #184/#135, including whether mdrule v2 is needed.
- [ ] Specify destination-owned version migrations and user-owned directional
  strategies, their operation semantics, validation, and recovery boundaries.
- [ ] Specify versioned publication/resource binding and minimal exchange identity,
  reference, and preservation requirements.
- [ ] After design approval, create implementation issues with concrete tests,
  milestones and blockers; implement and verify the agreed slices.
- [ ] Document legacy compatibility, unsupported capabilities, schemas, CLI/library
  behavior, and relevant platform verification before claiming support.

Design references: [concept stack](../CONCEPT_STACK.md),
[mdstandards design](mdstandards-design.md), and
[illustrative recipe use cases](md-recipes-use-cases.md). These were local drafts
when the issues were created; publication is tracked in epic #191.

## Proposed design children

Create these as design issues, not pre-approved implementation tickets. Each has
the new epic as parent and retains a design-before-implementation requirement.

| Draft issue title | Concrete completion criteria | Coordination/dependencies |
| --- | --- | --- |
| **Specify mdstandard adoption, rule bindings, and conformance modes** | Define reference identities, multiple required rules, explicit adoption, selection ownership, one/many bindings, at-rest/in-transit exclusivity, and separate rule/data findings. Work examples include different local folders and stronger local requirements. | Uses current #169 contracts; shared identity/semantic boundary with #186. |
| **Design structural rule conformance and determine mdrule format impact** | Define implication direction, supported schema/type/expression/relationship comparisons, collection scope and cardinality, counterexamples, unknown outcomes, contradictions, and regression fixtures. Record an explicit existing-format versus mdrule-v2 decision and any mdtype/config impacts. | Builds on adoption/scope decisions; coordinates #184/#135/#186. |
| **Specify mdstandard versioning, publication, and dependency resolution** | Resolve patch/minor/major meanings, migration graph ownership and paths, immutable publication, transitive resource identities, local installation/resolution, reader capabilities, and independently versioned surfaces. | Extends #184's inventory; coordinates #135. Does not require waiting for all #184 tooling to begin design. |
| **Specify deterministic migrations and user-owned import/export strategies** | Define endpoints and ownership, operation/path semantics, missing/null/conflict behavior, local additional requirements, definition changes, previews, destination assessment, revision checks, partial completion and retries. Distinguish version upgrades from local adapters. | Requires endpoint/binding and version-policy decisions; reuses existing codec/draft/receipt foundations without assuming their preservation rules fit migrations unchanged. |
| **Define the minimal standards exchange contract** | Decide single-record versus collection scope, role identification, stable identity, references/closure, attachments, repeated import and conflicts, unknown extensions and loss reporting. Explicitly defer unnecessary transport/network features. Use small recipe/journal fixtures solely to test general primitives. | Coordinates strategy design and #186's identities; no dependency on a full graph backend or server rollout. |

## Roadmap sequencing

1. **Now:** create the epic and design children. Proposed new milestone:
   **Standards interoperability design**, with no release number or due date.
   Preserve both existing #169 milestones and their meaning.
2. **Alongside mdtype v2 finalization:** complete the conformance/format-impact
   investigation early. Feed concrete compatibility requirements into #184 and
   configuration placement into #135. Keep v2 completion moving; only an explicitly
   identified compatibility defect should become a current-release blocker.
3. **After standards design approval:** create implementation slices for format
   loading/resource resolution; portable structural assessment; at-rest adoption
   and diagnostics; transformation planning; version migrations; in-transit
   import/export and exchange integration; schema/docs/compatibility verification.
   Choose implementation milestone boundaries from the settled dependency graph.
   Do not call an at-rest-only slice complete mdstandards delivery.

At present, relationships to #169/#186 are foundation/coordination links, not
blanket hard blockers on whole epics. Configure hard dependencies on specific
deliverables once their necessity is established. #186's existing gate prohibits
its implementation decomposition before design approval; this proposal neither
creates its implementation children nor bypasses that gate.

## Why mdrule v2 is a decision, not a prerequisite assumption

New behavior does not always require a new rule file format. A checker can compare
existing immutable rule definitions, while adoption bindings and user strategies
could live in separate configuration. That may leave mdrule v1 semantics intact.

New rule-local syntax for structural references, parameterized matchers,
relationship bindings, or changed enforcement semantics would require an explicit
version/capability decision. If v2 is selected, preserve v1, define unsupported
reader rejection, publish a new immutable schema, and specify migration/refusal
behavior. Do not simply reinterpret old matchers or overload mdtype v2 with
rule-to-rule semantics. mdstandard format versions, authored standard versions,
rule versions, and executable versions remain independent.

## Proposed updates to existing issues

- **#169:** add a follow-on link explaining standards reuse mdtype v2/mdrule v1
  without expanding this epic's completion criteria. Separately reconcile stale
  progress prose/#180 checkbox against its actual closure evidence before editing.
- **#184:** add mdstandard definitions, adoption configuration, strategy/operation
  language, authored standard versions, and their reader/writer support to the
  version inventory, marked planned rather than implemented. Keep migration
  compatibility distinct from standard contract compatibility.
- **#135:** add explicit follow-on coordination for adoption/resource configuration;
  decide whether the storage design needs a later config version. Do not silently
  make standards a precondition for config 0.3 completion.
- **#186:** link the new epic for semantic identity/relationship binding coordination;
  clarify that its existing standards-interoperability criterion concerns graph
  boundaries, not ownership of mdstandards adoption and migrations.

No existing issues were closed or acceptance boxes checked merely to record
this plan. The authorized publication is recorded above.
