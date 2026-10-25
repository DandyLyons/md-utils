# Shared index cache policy

This codifies the existing ordinary rule-validation and incoming/bidirectional
relationship-query pattern for future index-aware read commands, including the
proposed `survey`. It does not make every command index-aware or change runtime
behavior. Files remain authoritative; SQLite is a disposable optimization.

## Ordinary reads

- Use an existing compatible project index when the command supports it. Do not
  create an absent index implicitly; use direct source evaluation instead.
- Register missing requested scopes and refresh the evidence needed by the query,
  preserving selection and non-Markdown inclusion semantics. Avoid refreshing
  unrelated scopes. An index's existence does not establish coverage.
- Reuse unchanged evidence under the command's validity checks. Ordinary indexed
  refresh uses size/mtime followed by reading and hashing changed candidates;
  `--verify-hashes` additionally detects stat-preserving edits. Definition and
  evaluator changes invalidate dependent assessments.
- Read consistent committed evidence, with generation and dependency checks as
  required by the consumer. Never silently substitute stale findings for a failed
  ordinary refresh.
- On cache failure, warn on stderr and fall back to authoritative source
  evaluation. The fallback determines the result and exit status. Cancellation
  aborts rather than triggering fallback.
- `--no-index` bypasses cache use. Cache use must preserve the command's findings,
  coverage semantics, and exit behavior relative to direct evaluation.

This is not a mandate for whole-collection refresh. Ordinary outgoing relationship
queries deliberately use source-directed reads and verify consumed evidence;
retain that optimization. Cache invalidation requirements follow actual query
dependencies, including collection-wide dependencies when needed.

## Explicit snapshot reads

`--index-only` and `--indexed-only` are exact aliases where supported. They read
only a compatible published SQLite snapshot, without source/configuration/schema
reads, filesystem freshness checks, discovery, refresh, writer leases, writes, or
fallback. They reject `--no-index` and `--verify-hashes`.

Identify the snapshot generation and retain coverage limitations. Missing required
scopes or evidence must be explicit errors or unavailable findings according to
the query contract; never interpret absence of evidence as an empty successful
answer or fill gaps from raw files. See [SQLite-only findings](index-only-queries.md).

## Findings versus execution failure

Exit status belongs to the consuming command. Validation can fail because a
contract is violated. For the proposed survey, finding malformed frontmatter is a
successful query result, not itself an execution failure (owner approved
2026-10-25). Inability to complete the requested survey must remain distinguishable
from discovered malformed files. Exact partial-result exit behavior remains design
work. Do not change the existing `index update` or validation exit contracts to
implement this distinction.

## Implementation evidence

- [RulesIndexedValidation.swift](../Sources/md-utils/RulesCommands/RulesIndexedValidation.swift):
  existing-index detection, direct fallback, cancellation, and snapshot routing.
- [Collection index](collection-index.md#automatic-rule-validation): requested
  scope registration/refresh, generation checks, and absent-index behavior.
- [Relationship queries](relationships.md#existing-index-behavior): collection
  cache reuse and the source-directed outgoing exception.

Future survey-specific projections and queries are not implemented by this policy.
Agent Skill changes are unnecessary for this documentation-only codification:
no executable behavior, flags, or installed user guidance have changed.
