# Partial document provenance

The disposable native index retains bounded evidence to explain UUID collisions.
Markdown files remain canonical. Provenance is neither a backup nor version history,
and no provenance API rewrites files or authorizes a repair.

`md-utils index provenance books/one.md books/two.md` performs a hash-verified refresh
and prints bounded JSON evidence. The native repository's `explainUUIDCollision`
assesses all current holders of a configured UUID, including unexposed records.
Core's `UUIDCollisionAssessor` is database-independent and accepts current candidates,
evidence, and an explicit holder-set completeness flag.

## Evidence and uncertainty

Each observed path has first/latest generations, timestamps and source SHA-256
revisions, latest scan completeness, presence, verification and gap flags. Cached
mtime/size observations are explicitly unverified. First observation is not creation
time. Simultaneous discovery and earlier discovery do not establish ownership.
Equal revisions suggest a possible copy or restore without establishing direction.
An external disappearance followed by appearance elsewhere does not prove a move.
Restoring a removed path marks a gap; external edits replace the latest revision.
Edits or an exact backup restore entirely between scans can be undetectable.

Managed events are separate records with receipt identifiers, operation kinds,
paths/revisions, and coordinator versus operator-confirmed origin. Only confirmed,
published mutations supply events. Prepared and indeterminate intents do not.
Replay is idempotent and restricted to the receipt's original cache epoch. Old
receipts cannot reconstruct history lost during rebuild. UUID fields are configured
by the host; observation storage does not guess a UUID field or invent identifiers.

A directed copy relationship can recommend an original only when confirmed by the
coordinator, both current revisions match, every holder is explained by one acyclic
copy tree, and observations/holder coverage are complete without gaps or truncation.
Operator-confirmed recovery, managed moves, cached observations, incomplete evidence,
and unexplained additional holders remain ambiguous. Recommendations never bypass
the mutation service's current source checks or replace explicit write opt-ins.

## Publication and retention

Observations publish in the existing refresh transaction. Interrupted staging is
discarded. Failed scans can retain positive observations but mark them incomplete;
they cannot establish absence. Absence means no longer represented by retained scope
coverage, not proof of deletion. First/latest summaries occupy O(current paths).
At most 10,000 absent-path summaries and 10,000 managed events survive. Pruning sets
an epoch-wide uncertainty flag; removing evidence never increases confidence.
Reads accept at most 256 paths and 1,000 events, reporting truncated evidence.

Full rebuilds, incompatible-cache replacement and deleted indexes start a new epoch
and lose history. No historical schema migration or provenance restoration occurs.
JSON index settings survive independently. Pending user edits and durable receipts
are not observation data and must never be pruned with it. There are no new repair
routes in this change; existing UUID repair still requires an explicitly selected
document and never rewrites references.
