# Collection relationship policies

Issue #178 implements RFC 0004 collection consistency checks over explicitly named
frontmatter assertions. Validation is read-only and establishes consistency of
stored assertions, not truth about people or other domain entities.

## Opt in with an independently versioned rule

Standalone `.mdrule.json` files may explicitly adopt `md-utils-rule-schema: "1"`.
This preserves the existing `name`, `match`, `types`, `creation`, and `$schema`
fields and enables `relationshipPolicies`. `types` remains required. Omission of
the discriminator retains legacy project-version semantics and rejects policies.
Older readers reject the new fields. Project/config versions and authoring defaults
do not change. Relationships remain mdtype v2 with `requires: [document-relationships]`.

```json
{
  "$schema": "https://dandylyons.github.io/md-utils/schemas/mdrule/1/mdrule.schema.json",
  "md-utils-rule-schema": "1",
  "name": "people",
  "match": {"paths": ["People/**/*.md"]},
  "types": "person.mdtype.yaml",
  "relationshipPolicies": [
    {
      "id": "spouse-return",
      "kind": "reciprocity",
      "relation": {"type": "person.mdtype.yaml", "name": "spouse"},
      "scope": "reachable",
      "severity": "error"
    }
  ]
}
```

Each policy requires a unique nonempty `id`, a `kind`, and an explicit `scope`.
Type resources are relative to `.md-utils/types/`. References bind to the actual
declared type and local relationship, independently of the rule's `types`
expression. Unknown fields, versions, resources, names, modes, and duplicate
relation-list entries are configuration errors, including for advisory policies.
An inverse may intentionally use the same relation for `from` and `to`.

| Kind | Fields | Meaning |
| --- | --- | --- |
| `cycles` | Nonempty `relations`, `mode` | `allowed` performs no cycle check; `discouraged` reports advisories; `forbidden` reports errors |
| `selfLinks` | Nonempty `relations`, `mode` | `allow` performs no check; `forbid` rejects identity-equal endpoints |
| `reciprocity` | `relation` | Every participating A → B requires B → A in that relation |
| `inverse` | `from`, `to` | Every participating A —from→ B requires B —to→ A |

Except for cycles, `severity` is `error` by default and may be `advisory`. Cycles
reject `severity` because their mode determines it. Permission is a local no-op;
it does not override another policy. Inverse checks are directional: add a second,
swapped policy to constrain every `to` assertion as well.

Aliases and fragments do not create separate vertices. A self-loop is a cycle and
satisfies reciprocity; an inverse self-loop still needs the other relation.
Parallel assertions require one return, not matching multiplicity. Cardinality,
duplicates, scalar syntax and target conformance remain independent mdtype checks.
Cycle unions include several relations only when one policy explicitly lists them.

## Selection and coverage

`selected` checks edges with both endpoints selected by the rule's `match`. Known
outgoing boundary edges are reported but excluded from return obligations.
`reachable` closes over the policy's bound outgoing relations from selected seeds,
including records that do not match. Inverse closure includes both relations.
Resolution uses the full supplied collection universe, independent of source filters.

Policies do not implicitly require their declaring types. Extraction retains
malformed selected values, and resolved edges remain visible even when other
contract checks fail. Frontmatter parse/shape errors and uncertain resolutions
remain graph gaps. A completely enumerated empty scope passes with zero records;
an incomplete empty sample does not prove consistency.

A proven return satisfies its edge obligation even if unrelated coverage is
incomplete. Missing-return errors require complete evidence for that destination's
return relation. Malformed or ambiguous possible returns yield `unavailable`;
definitively unresolved links cannot serve as possible returns. Witnessed cycles
and missing returns remain failures even when other graph regions are unavailable.

Collection outcomes combine selected-record obligations and error-severity policies.
Advisory outcomes are visible without changing required conformance. Required
`fail` and `unavailable` both return a nonzero CLI status; structured output keeps
the distinction. Unknown source membership/enumeration prevents global success.

## CLI and cycle witnesses

```bash
md-utils rules validate people --config ./vault/.md-utils/md-utils.json --project-root ./vault/ --json
md-utils rules validate people --config ./vault/.md-utils/md-utils.json --cycle-witness-per-component
md-utils rules validate people --config ./vault/.md-utils/md-utils.json --cycle-witness-first --yaml
```

`--json` and `--yaml` are mutually exclusive. Both serialize the same evidence:
collection and snapshot identity, per-rule/per-record outcomes, type assessments,
policy origins, graph coverage, boundary edges, conflicts, and occurrence witnesses.
Witness indices address `collectionAssessment.extraction.occurrences`, retaining
source/target revisions, literal property paths, array indices, original values,
type declarations and resolution evidence. Decoded frontmatter coordinates are
never presented as raw-file byte ranges.

The mutually exclusive cycle flags are:

- `--cycle-witness-per-component` (default): iterative strongly connected component
  discovery and one deterministic witness per cyclic component. Other cycles within
  the component are not enumerated.
- `--cycle-witness-first`: stop each cycle policy's cycle search after its first
  deterministic witness; report `cycleSearchStoppedEarly`. This usually does less
  cycle-search work. Other policies and shared extraction still run.

No-cycle success still requires complete relevant graph evidence in either mode.
Neither mode enumerates every simple cycle. A known violation is retained if later
work exceeds a budget. Cancellation aborts the assessment instead of publishing a
completed partial result.

## Conflicts and index behavior

All policies are conjunctive. Forbidden cycles plus reciprocal/inverse returns
within that cycle union can produce `relationship.policy.conflict` advisories.
Within one rule and matching scope kind, declarations receive a potential-conflict
advisory even on an empty graph. Across rules, observed overlapping edges provide
concrete witnesses. Diagnostics retain both policy origins; they never override the
original severities. Only rules included in the request participate. Absence of a
conflict advisory does not prove compatibility, and arbitrary matcher overlap is
not decided. Validation does not apply repairs; use the explicit Fix-It workflow below.

Existing indexes refresh automatically; `--no-index` uses source files.
`--index-only`/`--indexed-only` returns only published SQLite findings without raw
files, refresh or fallback; absent policy evidence cannot certify consistency.
`--verify-hashes` detects stat-preserving edits in ordinary mode and is incompatible
with snapshot-only mode. See [snapshot-only queries](index-only-queries.md).
Policy assessments can reuse persisted evidence after whole-collection verification;
see [relationship cache](relationship-cache.md). Evaluator fingerprint v6 continues
to identify per-record semantics; cache format 9 adds separate relationship storage.
Fix-Its retain authoritative review checks, drafts and durable receipts outside SQLite.

## Portable API, bounds, and compatibility

Compile `MarkdownRuleDefinition` values with `ruleSchemaVersion: "1"`, explicit
`typeBindings`, and `relationshipPolicies`. Call `MarkdownRuleCollectionEvaluator`
with the registry, host-supplied `MarkdownRelationshipCollection`, optional requested
rule names, and `MarkdownCycleWitnessMode`. Single-record `MarkdownRuleChecker`
reports collection-policy unavailability instead of certifying required graph checks.

`MarkdownRelationshipLimits` retains the 10,000-record, 64 MiB, 100,000-occurrence,
100,000-candidate, 1,000-definition, 100,000-node/edge and 10,000-diagnostic limits.
Policies add a 1,000-policy limit and a shared 5,000,000-step graph-work limit.
Type assessment and relation extraction each retain their own existing budgets;
policy diagnostics and conflict diagnostics share a separate 10,000-item budget.
All limits are configurable through Core. A 1,000-record cycle is covered by the
permanent regression suite; limits are safety bounds rather than throughput guarantees.

## Review and apply Fix-Its (#179)

`rules fix` previews by default. Selecting fixes also only previews; `--apply` is
the explicit opt-in to persistence. No server resource configuration is required.

```bash
md-utils rules fix people
md-utils rules fix people --select 1,4,5
md-utils rules fix people --select 1,4 --select 5
md-utils rules fix people --select 1,4,5 --review '<printed-token>' --apply
md-utils rules fix people --include-recommendations --json
md-utils rules fix people --yes
md-utils rules fix people --yes --apply
```

Use `--config ./vault/.md-utils/md-utils.json --project-root ./vault/` for another
project. Printed commands retain these actual paths and recommendation opt-in.
`--json` includes the review token, numbered proposals, decoded property changes,
source before/after, candidate or combined assessments, blockers, and write reports.
Text shows `ERROR`/`WARNING`, rule/policy, exact source properties/links, proposed
changes and complete commands. It describes declared technical constraints, never
domain truth. A reciprocal policy is distinct from a cycle policy.

Numbered noninteractive application requires the token printed by the preview.
Any changed proposal, supporting record, definition, candidate namespace or scope
invalidates that token, including a newly added duplicate filename. Tokens are
computed without saving a review. Interactive `--apply` may show the current review,
collect numbers, and request final confirmation. Noninteractive `--apply` with no
selection fails. `--yes --apply` selects only deterministic automatic fixes emitted
by shared schema diagnostics; known defaults and relationship assertions still
require explicit numbered selection. Missing unknown values are reported as
blocked, not fabricated. Advisory repairs additionally need
`--include-recommendations`; explanatory-only Fix-Its cannot be applied.

Proven missing reciprocal/inverse links can add a scalar property or append to a
declared array. Existing scalar assertions are explicit replacement alternatives;
removing the originating assertion is another alternative. Array capacity and all
other loaded constraints are reassessed. Nested selectors use actual literal keys
and array indices; the planner does not invent object rows for missing array
branches. Cycle/self-link diagnostics offer explicit occurrence removals. Removing
one cycle witness does not claim that every cycle is repaired. Missing, ambiguous,
malformed, or incomplete evidence never authorizes an inferred return assertion.

Link spelling is checked against the destination declaration and resolved back to
the intended source. Bare-name ambiguity, exact path semantics, extension policies
and source-relative bases match ordinary link resolution. Unrelated links are not
normalized. Unsupported/contradictory declarations yield blockers, not guessed edits.

Default previews assess candidates separately; `--select` assesses their combined
effects. Mutually exclusive alternatives and overlapping edits are rejected.
Preview and application also preflight intermediate states in path order: a batch that needs
a temporarily invalid intermediate state is blocked. Every previously passing
loaded required type/rule is preserved; new required failures in already-failing
types are also blocked. Remaining required failures/unavailability produce a
nonzero exit status even when selected file changes completed.

Previews do not create locks, refresh/create an index, stage drafts, recover
mutations, or write receipts. Typed edits share the resource codec's round-trip
checks: unrelated native metadata values and body bytes are preserved, but changed
frontmatter may be reserialized, including comments, quoting and key order. Exact
source previews expose this. No-op edits preserve bytes and do not stage writes.

Application holds the shared writer lease, stages evidence-bound drafts outside
SQLite, and rechecks all supporting evidence before each atomic per-file write.
It updates expected revisions only from matching confirmed receipts. Native source
context is retained where possible; receipts record the observed post-write context
so filesystem timestamp rounding does not masquerade as an external edit. Loaded
server identity/protection constraints are respected when server configuration exists.
Existing indexes and server publications are refreshed after confirmed writes.
Failure stops later writes and reports completed, publication-pending,
recovery-required and unattempted drafts. Files are not rolled back and multiple
files are never claimed to commit atomically. External editors can still race
final filesystem checks; managed writer leases do not lock arbitrary applications.

Use `index draft show`, `index draft resolve`, and `index apply` to inspect and
recover the printed draft IDs. Resume an entire Fix-It batch, including its
completed IDs; confirmed commits are not rewritten. See [pending edits and
recovery](index-apply.md). No new repair store or receipt format family is introduced.

### Portable review API

`MarkdownFixItReview` in Core wraps existing `MarkdownFixIt` values with record
paths, diagnostic origins, and optional mutually exclusive alternative groups.
Producers supply a deterministic proposal order; it becomes the displayed
one-based numbering. Explicit selection is separate from automatic selection and
advisory opt-in. Explanatory suggestions cannot be selected. Overlapping property
edits and mutually exclusive alternatives fail selection rather than being merged.
Literal dotted keys remain distinct from nested key paths. Typed occurrence setters
and removals extend `MarkdownRecordEdit`; array removals use descending original
indices so one removal never retargets another selected occurrence.

The host must provide content revisions for edited and supporting records plus
fingerprints of loaded definitions/configuration, resolution candidates and their
completeness, requested rules, membership, policy scopes, and coverage. These are
host assertions, not evidence discovered or verified by Core. A snapshot generation
or file timestamp alone is insufficient. Native hosts must hash authoritative
source content and rediscover candidate sets when reconstructing a review.

`MarkdownFixItReviewToken` in the native library hashes canonical review data with
SHA-256, using the existing Swift Crypto dependency. The token includes ordered
proposals as well as evidence. Its `select` method verifies the token against a
fresh review before interpreting short numbers, so changed or reordered proposals
cannot reuse an earlier numbered selection. Selection does not authorize writes,
establish conformance, or replace final revision checks. Tokens are not stored and
are not cryptographic proof that the caller supplied complete evidence.

The portable review APIs perform no filesystem/index/draft operations. Evidence is
bounded to 10,000 records and proposals, 100,000 edits, 128 property-path components,
and 64 MiB of encoded review data. Relationship planning emits at most 1,000
proposals, and all-type reassessment is bounded to 100,000 roots. Native batches
retain at most 64 MiB of draft envelopes and use the shared 8 MiB per-file mutation
limit. Large selections may require smaller batches. Persistent assessment reuse
remains disabled; discovery/reassessment is intentionally conservative. Existing
`types fix` CLI behavior is unchanged.

Tests: `swift test --filter 'MarkdownFixItReview|MarkdownRelationshipFixTests|MarkdownRuleFixTests|RulesFixCommandsTests|MarkdownDraftTests|MarkdownMutationTests|ResourceCodecTests'`.

## Schema and verification

Canonical schema: `Sources/md-utils/Resources/1_mdrule.schema.json`. Public copy:
`site/schemas/mdrule/1/mdrule.schema.json`. These are publication inputs, not a claim
of live deployment. Existing immutable schemas and latest/default aliases remain
unchanged. JSON Schema checks shape; the md-utils compiler checks bindings and the
evaluator checks graphs. Interactive policy authoring and new server endpoints
remain separate from policy evaluation. Verified assessment reuse is implemented by #180.

Tests: `swift test --filter 'MarkdownRelationshipPolicyTests|RelationshipPolicyCommandsTests'`.
Linux validation runs in CI only. WASM verification requires an exactly matching
Swift toolchain and WASI SDK; native tests do not establish WASM compatibility.
Local verification passed 1,761 native tests. The WASM attempt could not compile
dependencies because the installed Swift 6.4 compiler cannot import the installed
Swift 6.3.1 WASI SDK modules; no WASM pass is claimed.
