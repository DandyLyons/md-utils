# Relationship cache measurements

Measured locally on 2026-10-14 with Apple Swift 6.4, macOS 27.0 (26A428), arm64,
and the debug `md-utils` executable. These are exploratory implementation
measurements, not release performance guarantees or Linux/WASM verification.

## Method

`scripts/benchmark-relationship-cache.py` generates even-sized collections of
paired cyclic Person records. Every record has a required name and one named
frontmatter reference. An explicit reciprocity policy checks return assertions.
This exercises structural recursion, extraction, policy evaluation and persistence
without inventing reciprocal data. Sources are small; this is not a dense graph,
large-body, or maximum-diagnostic stress corpus.

The script first measures direct validation, initializes an ordinary directory
index, then measures the first cached assessment, unchanged invocations, a target
edit that breaks conformance, and a file move introducing a duplicate basename.
Unchanged failures and ambiguity are measured too. The move keeps the source count
within the 10,000-record default. A miss must persist a new certificate/generation;
a verified hit leaves that stored manifest unchanged while returning current
generation evidence. Native tests separately assert the service's `cacheHit`
result and round-trip complete evidence.

Elapsed time includes source discovery, index refresh, authoritative rereads,
definition compilation, certificate checks, evaluation or decoding, and JSON
serialization. macOS `/usr/bin/time -l` reports peak resident memory for each CLI
process. Persistent bytes measure relationship payloads, not all SQLite pages.

## Interpretation and budgets

| Records | Direct (s) | First indexed assessment (s) | Unchanged indexed (s) | Maximum RSS (MiB) | Retained payload (MiB) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 | 0.230 | 0.420 | 0.339 | 30.1 | 0.322 |
| 1,000 | 1.321 | 3.823 | 3.132 | 71.6 | 3.102 |
| 10,000 | 13.625 | 44.631 | 41.012 | 413.9 | 30.903 |

Unchanged times are medians of three runs at 100 and 1,000 records and one final
sample at 10,000. Maximum RSS is the maximum across all scenarios at that size,
including cached failures/ambiguity. At 10,000 records, target editing took 53.623 s,
the namespace change 67.087 s, cached failure 41.684 s and cached ambiguity 42.204 s.
The resulting database occupied 80.016 MiB, including source/index data and reusable
SQLite pages. All samples verified misses after changes, hits on unchanged inputs,
256 KiB maximum chunks, and zero remaining relationship staging rows.

Raw results: [100 records](benchmarks/relationship-cache-100.json),
[1,000 records](benchmarks/relationship-cache-1000.json), and
[10,000 records](benchmarks/relationship-cache-10000.json).

Verified hits skip graph evaluation but still perform source refresh and repeated
authoritative verification. On this sparse workload they remain slower than direct
validation. Do not promise faster end-to-end queries merely because a cache hit
occurred. Timings also vary with filesystem caches and background system activity;
repeat measurements before making optimization decisions.

The existing 10,000-record bound accommodates this corpus. Relationship persistence
has an independent 64 MiB payload cap and four-request retention cap; at the large
sample, one policy result occupies roughly half that byte budget. It is reasonable
to retain this conservative ceiling without increasing the existing graph budgets.
The service skips persistence when evidence exceeds the cap. Small-budget tests
verify explicit unavailable outcomes and that exhausted/truncated results are not
cached. Storage tests verify byte eviction and oversized payload rejection.

Chunks are at most 262,144 bytes. Completed runs must leave zero relationship
staging rows. SQLite can retain freed pages for reuse, so total database size can
exceed the live payload cap. Process memory also includes parsed records, graphs,
decoded evidence and serialization; the payload cap is not a resident-memory limit.
Dense graphs, large individual values and heavily repeated diagnostics need separate
measurements before increasing any evaluator or persistence budget.

## Reproduction

```bash
swift build
python3 scripts/benchmark-relationship-cache.py --files 100 --runs 3
python3 scripts/benchmark-relationship-cache.py --files 1000 --runs 3
python3 scripts/benchmark-relationship-cache.py --files 10000 --runs 1
```

Supply `--binary` to measure a release build. The script requires access to macOS
resource measurements; it fails rather than silently recording missing RSS data.
Corpora are retained under project `tmp/` for inspection and are not committed.

## Correctness verification

The full native suite passed 1,828 tests across eight test runs. Subsequent final
checks passed all six cache-storage tests (including corrupt chunk bounds) and the
additional malformed-assertion round-trip test. Native tests verify persistent hits
and invalidation separately from timing; benchmark observations do not substitute
for those assertions. Linux remains CI-only and WASM verification remains deferred
under the project's release-preparation policy.
