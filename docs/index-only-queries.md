# SQLite-only findings

`--index-only` and `--indexed-only` mean the same thing on `rel` and
`rules validate`: base findings exclusively on the last published SQLite snapshot.
This corrects the earlier misinterpretation in #165/#169/#177/#180/#188; it is not
a new filesystem-validation mode. Explicit file lists are invocation inputs, not
permission to read the selected documents.

The reader opens SQLite read-only, checks its persisted format/publication metadata,
and reads a consistent transaction. It performs no raw document, configuration,
schema or index-settings reads; no source stats/hashes; no discovery, refresh,
writer lease or fallback. `--verify-hashes` and `--no-index` are incompatible.
Run an ordinary index update separately when current filesystem evidence is wanted.

Rule validation returns stored statuses and diagnostics for registered rule scopes.
An omitted name selects stored scopes, not today's configured rules. Missing scopes
fail explicitly. JSON/YAML report `snapshotGeneration`; text labels the snapshot.
Collection-policy findings absent from per-record assessments are not recomputed
from raw files or promoted to successful validation.

Explicit CLI indexing (`index update`, `index type`, and `index rule`) now publishes
a dedicated relationship projection after the document refresh. It stores ordinary
body/frontmatter link occurrences with their original ranges, named assertions,
type outcomes, rule requirements/alternatives, hint and conformance applicability,
and reverse destination edges. Metadata-only indexes support this projection;
full body storage and FTS are not required. The publisher checks each source against
its indexed hash and uses the same portable scanners and evaluators as live queries.

Projection facts and reverse edges are staged in bounded batches and replaced in
one transaction, with an exact publication generation, epoch, and evaluator profile.
An intervening refresh invalidates the projection; cancellation cannot publish a
mixture. Readers use SQL destination lookups for incoming sources before decoding
evidence, so a one-document query is not limited by the number of unrelated indexed
documents. Evidence exceeding query budgets remains explicitly incomplete.

Files, folders, types, rule membership, required types, and tags use published facts.
JMESPath selectors currently remain unavailable in this projection: their envelope
includes body text, which this projection deliberately does not retain. No raw reads
fill that gap. Publication is bounded to 100,000 records/candidates, 256 MiB of source
content and encoded evidence, and one million graph nodes/occurrences/edges. Partial
source or evaluation evidence is reported; the projection never promises freshness
relative to the current filesystem. Named graph roots include only declaring types;
target types are assessed through dependencies. Other type selection outcomes reuse
compatible indexed type assessments; publication does not speculatively validate
every document against every unrelated type. Register a type scope with `index type`
when complete selection by that type is needed. Missing type facts remain unavailable.

Indexes without a compatible projection use indexed paths, metadata, optional cached bodies, and
compatible graph evidence from the exact published generation/epoch. Cached graph
payload hashes and bounds are checked inside the transaction, without filesystem
certification. Older-generation caches are not silently reused. The largest usable
graph payload supplies available named assertions supported by stored conformance
or explicit `--type`; missing applicability/interpretation coverage remains explicit.
The generic graph cache is not a complete indexed relationship projection.

Older metadata-only indexes do not contain body links. The fallback reader can discover
ordinary frontmatter links from stored metadata; it never interprets an absent body
as proof of no links. Reconstructed metadata supplies no raw source offsets/lines.
Files/folders and persisted type/rule memberships support selection. Historical
rows lack authored frontmatter-format and compiled requirement bindings: tag,
JMESPath-envelope and required-type selectors therefore report unknown membership
when that evidence is unavailable. No raw definitions are loaded to fill gaps.

All detail levels and formats retain available results. Missing evidence produces
`query.incomplete` and exit 1 with brief summary hints or detailed reasons. Snapshot
generation is exposed even at summary detail. Snapshot scope alone does not assert
current filesystem freshness. Run `md-utils index update` explicitly to publish the
new projection; enabling a query flag never creates or refreshes it.

Tests remove documents, schemas, rules and configuration after indexing, replace a
selected file with a directory, and query both aliases. They verify stored results,
unchanged database bytes/mtime and snapshot generation, and reject refresh options.
Projection regressions also remove all raw sources, preserve body ranges and named
evidence, exercise incoming queries with budgets smaller than the collection, and
check edge replacement and generation invalidation.

## Native verification (2026-10-15)

The release build refreshed a 25,947-document metadata-only Notes index in 78.29
seconds, retaining 382,595 cached scope assessments and publishing 68,922 reverse
edges. No full bodies were stored. The requested single-document `rel both --detail
explain --index-only` query completed in 0.815 seconds. SQLite size, modification
time, publication generation and scope states were unchanged by the query.

That query still exits 1: two unsupported leading-`/` Markdown destinations prevent
proving complete incoming candidate coverage without a publishing-root contract.
Source, selection and interpretation coverage are complete. These are observations
from one release run, not a benchmark guarantee. Regression tests separately prove
that such unrelated uncertainty does not make an outgoing-only query incomplete.
