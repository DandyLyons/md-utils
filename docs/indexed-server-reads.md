# Indexed native server reads

The native executable shares `.md-utils/index.sqlite` with `md-utils index`.
Files remain authoritative. `MarkdownUtilitiesIndexNative` owns native evaluation
and fingerprints; `MarkdownUtilitiesServerNative` provides `IndexedMarkdownRepository`
behind `RecordStore` and `MarkdownServerReadRepository`. `MarkdownUtilitiesServer`,
Core, and WASM retain their database-independent dependencies.

## Release note: collection responses changed

Collection routes now return an object rather than an unbounded JSON array:

```json
{"records":[],"generation":"opaque-generation","nextCursor":null}
```

Clients must read `records` and follow `nextCursor` until it is null. Keep all query
parameters identical when continuing. A `409 request.generation-changed` means a
new publication replaced the cursor's generation; restart from the first page.
Revisions now use the authoritative file's SHA-256 content hash, shared across
resource memberships. Do not interpret revisions or generation strings.

| Parameter | Meaning |
| --- | --- |
| `limit` | 1–1,000 records; default 100. The response byte budget can shorten a page. |
| `cursor` | Opaque continuation bound to resource, query, and generation. |
| `pathPrefix` | Collection-relative directory, such as `books/`; `.` means the root. |
| `valid` | `true` or `false`, filtering aggregate record validity. |
| `filter` | URL-encoded JSON object of top-level frontmatter scalar equality tests, combined with AND. |
| `q` | FTS5 expression; available only on explicitly enabled resources. |

Results use binary logical-path ordering, including search results. Equality
preserves JSON types: `true` differs from `"true"`; missing keys differ from null.
Arrays and objects are not scalar filter values. Unknown or repeated parameters,
invalid limits, and mismatched cursors return `400`.
Combined filter/search/path values are limited to 4,096 bytes, cursors to 16,384
bytes, and request URIs to 32,768 bytes.

Enable FTS in the cache with `md-utils index search enable`, then set
`searchEnabled: true` on each resource that should expose `q`. Startup refreshes
the enabled cache. A configured searchable resource refuses to start with a
metadata-only cache. Disabled resources reject `q` with
`400 request.search-unavailable`. Offline and served OpenAPI derive capability
and query parameters from the same endpoint plan.

## Publication and refresh

Startup refreshes the shared index before accepting requests. On macOS, the
existing filesystem watcher uses its 300 ms debounce and 30 second reconciliation
interval. Other platforms require explicit `md-utils index update`; requests
adopt published index generations without discovering source files or launching
the CLI. A new rule or index scope never creates an HTTP resource.

Index refresh attempts and committed source generations are distinct. Server
projections are staged on disk in bounded batches, then published in one
transaction with their source generation. Each page or lookup runs in a read
transaction. Old and new memberships cannot be mixed within a response.
Unchanged source hashes and modification times reuse body-free projections.

Operational refresh failures retain the last successful server publication.
Responses expose `X-Md-Utils-Stale`; collection responses also expose
`X-Md-Utils-Generation`. Watcher failures are logged and retried. Initial refresh
failure stops startup. Syntax and validation diagnostics remain visible for
rule-selected records instead of silently removing those records.

Changes to server resource configuration, rule/type definitions, resolved schemas,
or an enabled search capability require restart. Resource reads return
`503 server.restart-required`; the existing OpenAPI document stays fixed.

## Body and memory bounds

Server projections contain no bodies. Both storage modes materialize authoritative
source files only for the requested records, using bounded reads and checking
SHA-256 against indexed revisions. A missing, replaced, or modified file returns
`503 record.source-changed` until a successful refresh. A concurrent change cannot
combine an old indexed frontmatter value with a different body version.

Single-file reads are limited to 64 MiB; encoded responses are limited to 64 MiB.
An individually oversized representation returns `413 record.response-too-large`.
Collision lookups remain `409`; their errors include `totalCandidates` and
`truncated`, with at most 1,000 body-bearing candidates within the byte budget.
Collision status is calculated before filtering or pagination, across the complete
resource membership. Diagnostic path lists are bounded to 1,000 paths; diagnostic
messages retain the total collision count.

The filesystem `RecordStore` rejects create, replace, and delete with
`RecordStoreError.unsupportedOperation`. Mutation APIs and canonical SQLite storage
are outside this implementation.

## Validation

```sh
swift test
docker build --file Dockerfile.server-linux --tag md-utils-server-linux .
python3 scripts/benchmark-server-reads.py --count 1000
python3 scripts/benchmark-server-reads.py --count 100000
```

The benchmark generates its corpus under `tmp/`, starts the real server, verifies
a body-bearing page, and reports child peak RSS and page latency. Run corpus sizes
in separate invocations so RSS measurements are independent. It deletes fixtures
unless `--keep` is supplied.

On macOS arm64 with the Swift 6.3.1 debug executable (September 18, 2026), 4 KiB
bodies produced the following measurements. Startup includes indexing, projection
publication, and the first page; the 100,000-document run overlapped Linux build
validation on the same machine, so its timing is not an isolated throughput result.

| Documents | Total body size | Peak server RSS | Startup + first page | Warm 1,000-record page |
| --- | --- | --- | --- | --- |
| 1,000 | 3.9 MiB | 63.3 MiB | 2.932 s | 0.335 s |
| 100,000 | 390.6 MiB | 101.6 MiB | 214.205 s | 0.342 s |

Both responses were about 4.37 MiB. The corpus grew by 100× without a corresponding
body-sized increase in resident memory. Raw measurements are in
[server read benchmarks](benchmarks/server-reads.json). Million-document validation
is outside this issue.
