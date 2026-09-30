# Explaining Document Provenance

Explain UUID collisions using bounded evidence while retaining uncertainty about ownership.

## Supply current holders

``UUIDCollisionAssessor`` is portable and performs no filesystem or database work.
The host supplies two to 256 distinct ``UUIDCollisionCandidate`` values for one
normalized UUID, with source revisions verified from current file bytes. Set
`completeHolderSet` only after finding all holders, including documents outside
the resource exposed to a client.

``DocumentProvenanceEvidence`` combines observations and explicit managed events
from one cache epoch. ``DocumentObservation`` records first and latest observations,
not a document's creation time. Its timestamps are seconds since the Unix epoch.
Stat-cached observations, incomplete scans, missing revisions, and gaps in history
cannot establish continuous ownership.

## Interpret an explanation

The assessor recommends an original only when current observations are complete,
verified, continuous, and connected by a single rooted graph of confirmed managed
copies. Each copy must match both candidates' current revisions. An event confirmed
by an operator, a managed move, or matching content can explain a possible
relationship but cannot independently establish copy ownership.

``UUIDCollisionExplanation/relationships`` may contain useful evidence while
``UUIDCollisionExplanation/ambiguous`` remains `true`. Pruned history, a truncated
query, an incomplete holder set, or missing observations prevents a recommendation.
Discovery order, timestamps, and equal content never select an original.

Even a non-ambiguous explanation is advisory. Repair tooling must select a target,
validate the current revision, and use its authorized mutation mechanism. Core
does not authorize writes or rewrite references.

## Treat history as disposable

Native hosts retain provenance with their disposable index. A full rebuild starts
a new epoch and loses prior observation and event history. Lost evidence is unknown;
hosts must not replay old receipts into the new epoch to manufacture continuity.
Durable pending operations and recovery receipts belong outside this disposable
history and continue to govern unfinished mutations.
