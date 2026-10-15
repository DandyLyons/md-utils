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

Relationship queries use indexed paths, metadata, optional cached bodies, and
compatible graph evidence from the exact published generation/epoch. Cached graph
payload hashes and bounds are checked inside the transaction, without filesystem
certification. Older-generation caches are not silently reused. The largest usable
graph payload supplies available named assertions supported by stored conformance
or explicit `--type`; missing applicability/interpretation coverage remains explicit.
The generic graph cache is not a complete indexed relationship projection.

Existing metadata-only indexes do not contain body links. The reader can discover
ordinary frontmatter links from stored metadata; it never interprets an absent body
as proof of no links. Reconstructed metadata supplies no raw source offsets/lines.
Files/folders and persisted type/rule memberships support selection. Historical
rows lack authored frontmatter-format and compiled requirement bindings: tag,
JMESPath-envelope and required-type selectors therefore report unknown membership
when that evidence is unavailable. No raw definitions are loaded to fill gaps.

All detail levels and formats retain available results. Missing evidence produces
`query.incomplete` and exit 1 with brief summary hints or detailed reasons. Snapshot
generation is exposed even at summary detail. Snapshot scope alone does not assert
current filesystem freshness. A dedicated complete link/interpretation projection
at indexing time remains necessary for full relationship answers from metadata-only
indexes; enabling this flag does not create or refresh one.

Tests remove documents, schemas, rules and configuration after indexing, replace a
selected file with a directory, and query both aliases. They verify stored results,
unchanged database bytes/mtime and snapshot generation, and reject refresh options.
