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
not decided. No repairs are generated.

Existing indexes refresh automatically; `--no-index` uses source files.
`--indexed-only` refreshes recorded candidates without discovery or fallback and
cannot certify global consistency. `--verify-hashes` detects stat-preserving edits.
Policy assessments are recomputed per request. Evaluator fingerprint v6 invalidates
older per-record evidence; persistent cross-document reuse remains disabled pending
#180. Drafts and durable receipts are unchanged.

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

Canonical schema: `Sources/md-utils/Resources/1_mdrule.schema.json`. Public copy:
`site/schemas/mdrule/1/mdrule.schema.json`. These are publication inputs, not a claim
of live deployment. Existing immutable schemas and latest/default aliases remain
unchanged. JSON Schema checks shape; the md-utils compiler checks bindings and the
evaluator checks graphs. Interactive policy authoring, new server endpoints,
reviewable repairs (#179), and persistent assessment reuse (#180) remain separate.

Tests: `swift test --filter 'MarkdownRelationshipPolicyTests|RelationshipPolicyCommandsTests'`.
Linux validation runs in CI only. WASM verification requires an exactly matching
Swift toolchain and WASI SDK; native tests do not establish WASM compatibility.
Local verification passed 1,761 native tests. The WASM attempt could not compile
dependencies because the installed Swift 6.4 compiler cannot import the installed
Swift 6.3.1 WASI SDK modules; no WASM pass is claimed.
