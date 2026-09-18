# Collection refresh resource measurements

Issue #147 measures the complete CLI refresh path, including directory discovery,
source reads, SHA-256, frontmatter/Markdown analysis, independent assessments,
disk staging, transactional publication, and optional external-content FTS5.
This is not an in-memory or SQLite-only insert benchmark.
The accepted scope is 100,000 documents. The maintainer explicitly deferred the
one-million-document requirement to future improvement before closing #147.

## Reproduce

```sh
swift build -c release --product md-utils
python3 scripts/benchmark-index-refresh.py --counts 100000
```

The script creates disposable corpora under `tmp/index-refresh-benchmark/`, saves
JSON results and per-phase `time(1)` logs there, and removes each corpus after
both modes finish. `--output <directory>/` selects another results directory;
`--reuse-corpus` resets a previously generated corpus after an interrupted run.
`--binary` and `--build-description` explicitly identify alternative builds.

The synthetic distribution is 90% 1 KiB, 9% 8 KiB, and 1% 64 KiB files, spread
over directories of 1,000 files. Each file has distinct YAML title/ordinal fields,
a status, a Markdown heading, and repeated prose. Source totals are 231,424,000
bytes for 100,000 files. Repeated vocabulary
makes these reproducible indexing measurements, not a worst-case FTS vocabulary
or large-document stress test. File sizes, body mode, directory fanout, and
evaluator cost matter independently of document count.
Each small update appends 14 bytes; the FTS initial run includes the preceding
metadata-mode updates to 0.1% of files.

Each mode starts from a fresh database and runs initial indexing, full rebuild,
unchanged refresh, a 0.1% update, and a rebuild over two fully overlapping scopes
(`notes/` and the project root). All phases use new CLI processes. The filesystem
cache is warm from corpus generation; elapsed times are not cold-disk claims.
`time(1)` supplies peak RSS. Database plus journal sizes are sampled every 250 ms
and at process exit; short-lived peaks between samples may be missed. Database
size includes staging pages, which SQLite keeps on its freelist after cleanup.
The report verifies the final document count and that staged file rows are gone.

## Budgets

The implementation's default changed-payload budget is 128 records or 4 MiB,
plus one file's input/extraction/evaluator output. A larger result stages alone;
input files exceeding 64 MiB become persisted failures without being read.
Discovery batches hold 1,024 paths or 256 KiB (a larger individual path stages
alone), and candidate reads fetch 256 paths at a time. Metadata-only batching
drops bodies immediately. SQLite and host evaluator memory are additional to
these payload limits.

The process-level targets selected before measurement are **256 MiB peak RSS**
and **600 seconds per 100,000 documents per phase**. These targets apply to this corpus and
machine; they are not promises for arbitrary evaluator output or input near the
64 MiB file limit. Disk staging grows with changed data and scope memberships;
it is deliberately not bounded to an in-memory-sized constant.

## Implementation findings

Scale profiling found a quadratic scope lookup: SQLite preferred the
`(generation, scope_id, path)` primary key to satisfy scope ordering, scanning
the generation for each path. The lookup now explicitly uses `refresh_seen_path`.
Publication uses correlated assessment lookups instead of materializing the
entire changed set of scope/path pairs.

Heap inspection also identified retained Foundation JSON writer and source-read
buffers. Typed `JSONEncoder` payloads and Swift System reads into owned buffers
replace those paths. The Swift directory adapter reports enumeration errors and
feeds bounded discovery batches. It uses Foundation's incremental enumerator,
without direct C calls or explicit autorelease pools. Underlying framework
allocations are included in the measured process RSS rather than assumed bounded
from the application batching policy alone.

## Measured results

Measured on an Apple M4 Pro with 24 GiB RAM, macOS 27.0 arm64, using an
optimized Swift 6.4 build (swiftlang-6.4.0.30.4, Xcode 27 beta 5). The CLI links
system SQLite 3.54.0 and selected JSONB storage; the Python 3.14.5 disk observer
uses SQLite 3.53.4. All phases ran without concurrent build/test workloads.
These are warm-filesystem-cache measurements, not cold-disk throughput results.

The measured build used:

```sh
xcrun --toolchain XcodeDefault swift build -c release --product md-utils
python3 scripts/benchmark-index-refresh.py --counts 100000 \
  --swift "$(xcrun --toolchain XcodeDefault --find swift)" \
  --build-description "release; XcodeDefault Swift 6.4; issue-147 final Swift enumerator"
```

The local standalone Swift 6.3.1 compiler crashed while compiling GRDB in release
mode, so the measured release executable used the XcodeDefault toolchain.
The standalone compiler successfully built and tested the debug configuration.

| Mode | Phase | Seconds | Peak RSS (MiB) | Final database (MiB) | Peak database + journals (MiB) |
| --- | --- | ---: | ---: | ---: | ---: |
| Metadata-only | initial | 36.58 | 99.27 | 114.26 | 114.26 |
| Metadata-only | rebuild | 38.37 | 47.41 | 114.96 | 139.31 |
| Metadata-only | unchanged | 7.88 | 42.72 | 114.96 | 114.97 |
| Metadata-only | small-update | 8.13 | 45.88 | 114.96 | 115.16 |
| Metadata-only | overlap | 46.48 | 73.48 | 182.96 | 182.96 |
| FTS | initial | 39.61 | 191.89 | 631.85 | 631.85 |
| FTS | rebuild | 39.33 | 134.09 | 631.85 | 656.20 |
| FTS | unchanged | 8.13 | 42.84 | 631.85 | 632.01 |
| FTS | small-update | 7.88 | 46.89 | 631.85 | 632.01 |
| FTS | overlap | 47.53 | 160.33 | 698.09 | 698.09 |

All ten phases meet the 256 MiB RSS and 600-second budgets. Each published exactly
100,000 documents and left zero staged file rows. Unchanged refreshes performed
zero hashes/evaluations; the small updates processed 100 files. Overlap runs
hashed 100,000 files for 200,000 independent scope assessments. Unit tests
separately verify one extraction and one content write per shared file.

The database includes reusable staging pages after cleanup; its retained size is
not the size of live staging payload. Peak disk figures include the cache and
journals observed at 250 ms intervals. See the [raw measurements](benchmarks/index-refresh-100000.json)
for exact byte counts, corpus size, counters, and machine/toolchain provenance.

## Further improvement

Million-document validation is deliberately outside #147's revised acceptance
criteria. The benchmark accepts `--counts 1000000` for future investigation, but
the final implementation makes no measured million-document memory or runtime
claim. Future work should measure all phases in both modes, inspect Foundation
enumerator retention and SQLite publication memory, and include wider directory
fanout, larger documents, and more varied FTS vocabulary. Application batch bounds
do not impose a fixed bound on host evaluator or underlying framework allocations.
