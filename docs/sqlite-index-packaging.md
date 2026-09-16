# Native SQLite packaging

Issue #137 establishes the database dependency for the indexing phase of #93.
`MarkdownUtilitiesIndex` is an opt-in native library using upstream GRDB through
SwiftPM and the operating system's SQLite runtime. It provides a checked
connection foundation and the incremental collection cache from #138. The CLI
links the index target; queries and server integration remain follow-up work.
See [collection indexing](collection-index.md). Files remain authoritative.

## Decision and alternatives

**Selected: option 1, GRDB with system SQLite.** No amalgamation, custom SQLite
build, or second runtime is shipped. SwiftPM currently resolves GRDB 7.11.1.
GRDB owns connection serialization and provides statement, transaction, and
migration infrastructure for later indexing work.

**Fallback: option 3, a source-based SwiftPM adaptation of GRDB with bundled
SQLite.** Reconsider only if system SQLite cannot meet supported deployment
requirements. That would require a maintainable C-module/package adaptation,
matched compile flags, consumer symbol-isolation checks, and macOS/Linux tests.
It is not implemented or selected automatically on a failed probe.

**Rejected: option 2, the Xcode-based custom SQLite framework workflow.** Database
integration must preserve ordinary SwiftPM builds and Linux support. GRDB's
[documented custom-build workflow](https://github.com/groue/GRDB.swift/blob/v7.11.1/Documentation/CustomSQLiteBuilds.md)
does not provide that integration.

The earlier bundled prototype and C bridge have been removed. Their measurements
are not estimates of GRDB overhead. See [the library evaluation](sqlite-library-evaluation.md)
for the rationale and the separate, deferred StructuredQueries decision.

## Runtime requirements and supported targets

The linked SQLite must support JSON functions, JSON expression indexes, and
FTS5. A version string or GRDB Swift compilation flag does not establish those
capabilities. Modern SQLite includes JSON unless omitted; FTS5 must be enabled
in the runtime build. [SQLite JSON](https://sqlite.org/json1.html#compiling_in_json_support),
[SQLite FTS5](https://sqlite.org/fts5.html).

| Platform or product | Policy |
| --- | --- |
| Native index, macOS 13+ | Use system SQLite with mandatory capability probes. Local validation uses macOS 27 arm64, not every older OS. |
| Native index, Linux | Use distribution SQLite. Ubuntu Noble with Swift 6.2 is the reference container; CI covers x86_64 and local Docker validation covers arm64. Other distributions require validation. |
| iOS 16+, tvOS 16+, watchOS 9+, Mac Catalyst 16+ | Package minimums are unchanged. The prototype has not validated these SDKs/runtimes; do not infer index support from the manifest alone. |
| Windows, Android | Not supported by this prototype. |
| `MarkdownUtilitiesCore` and Core WASM smoke | No dependency path to GRDB or SQLite. |
| `MarkdownUtilities`, server | Do not depend on the index target. |
| CLI | Links the index target; only index commands open databases or run capability probes. |

Linux source builds require SQLite development headers and a linker library
(Ubuntu/Debian: `libsqlite3-dev`); deployment requires the runtime library
(`libsqlite3-0` on Ubuntu/Debian). The measurement script additionally uses
Python 3 and binutils. A missing shared library is an installation error that
can prevent a linked executable from launching; capability checks cover a
present runtime with missing or incompatible features.

GRDB's [package](https://github.com/groue/GRDB.swift/blob/v7.11.1/Package.swift)
uses system SQLite. Upstream describes Linux support as contributor-maintained;
this repository owns its Linux validation. Consumer smoke tests exercise direct
SQLite C access and GRDB in one process. Binary inspection verifies dynamic
`libsqlite3` linkage and absence of embedded `sqlite3_*` definitions. This checks
ordinary system-runtime coexistence, not arbitrary third-party bundled builds
or process-global SQLite reconfiguration.

## Capability and failure contract

`SQLiteIndexDatabase(path:)` first opens an in-memory GRDB `DatabaseQueue`.
It creates and queries a JSON expression index and creates, writes, and searches
an FTS5 table. SQL CHECK assertions validate query results. Only after those
operations succeed does it open the requested index file. No migration or schema
change is attempted before the probe succeeds.

On failure, `SQLiteIndexError` identifies the system runtime version, failed
capability, SQLite error, and OS/distribution remediation. Updating GRDB alone
does not update SQLite. There is no silent reduced-functionality mode or bundled
fallback. Tests use real failing statements and check incorrect query results,
preservation of existing file bytes, and absence of newly created files. Open
errors identify the path and suggest checking parent directories and permissions.
Existing non-index commands remain usable when index capabilities are missing.

All future index mutations must use the checked initializer. Do not open a
separate unchecked GRDB connection before probing. Keep public schemas based on
JSON text, standard expression indexes, and FTS5, without GRDB-only SQL functions
or custom extensions. External tools use their own SQLite runtime and must
independently support those facilities; installing md-utils does not upgrade
GUI browsers or the `sqlite3` command.

## Verification and measurements

Run from the repository root:

```sh
swift run SQLiteIndexSmoke
swift test --filter MarkdownUtilitiesIndexTests
python3 scripts/measure-sqlite.py
docker build --file Dockerfile.sqlite-index --tag md-utils-sqlite .
scripts/build-wasm.sh
```

The measurement script creates a fresh package under `tmp/`, copies the actual
index/smoke/test sources, and uses the root lockfile's GRDB version. It does not
reuse build products. This isolates native overhead from the CLI/server graph;
the Docker recipe also builds the real root-package smoke target.

The baseline is a Swift executable calling system SQLite directly. The index
smoke adds GRDB and the checked connection facade. Download/resolution time is
reported separately. The baseline compiles first; GRDB has not been compiled
when the index release build starts. Both original release and stripped sizes
are reported; both executables are run, followed by linkage/symbol checks. Tests
run in the isolated package as well as the host's full suite.

Measurements are single-run observations, not statistical benchmarks or final
CLI/server size predictions. No indexing throughput claim is made. Reports are
saved as `report.json` in each workspace and printed in CI. Existing CLI/server
products acquire no GRDB linkage until they explicitly depend on the index.
Package resolution still sees GRDB even when building unrelated products.

Local measurements (September 16, 2026, GRDB 7.11.1): macOS 27 arm64 uses
system SQLite 3.54.0 and Swift 6.4 with its matching SDK 27; Ubuntu Noble arm64
in Docker uses system SQLite 3.45.1 and Swift 6.2.4.

| Measurement | macOS | Linux |
| --- | --- | --- |
| Dependency resolution, separately timed | 5.861 s | 3.163 s |
| Clean direct-SQLite baseline build | 8.398 s | 0.333 s |
| First GRDB/index release build | 25.193 s | 20.411 s |
| Warm no-op index build | 1.032 s | 0.173 s |
| Baseline release / stripped size | 51,928 / 50,768 bytes | 78,640 / 69,456 bytes |
| Index smoke release / stripped size | 5,385,008 / 2,751,352 bytes | 12,668,768 / 2,993,656 bytes |

The stripped executable deltas are 2,700,584 bytes on macOS and 2,924,200 bytes
on Linux. Timings include SwiftPM planning; the first baseline also warms SDK
module caches. The index build still compiles GRDB from scratch. Linux validation
used downloaded source repository caches after a network fetch stalled, not
host build products. Both the root release smoke and the isolated measurements,
seven tests, stripped executables, and linkage checks passed on Linux.

The standalone Swift 6.3.1 compiler crashed in release IR generation for GRDB's
`NSUUID.fromDatabaseValue` when paired with the installed SDK 27 beta. Debug
builds and all 1,350 host tests passed with that compiler. Repeating the release
measurement using the matching SDK compiler succeeded, including the seven
focused tests and both stripped executables. This is a toolchain compatibility
limitation, not a GRDB source patch or adoption of the rejected Xcode-framework
workflow: all builds still use SwiftPM. Use a matching compiler/SDK for macOS
release builds and revalidate new combinations.

## Maintenance

Before each md-utils release, review GRDB releases and applicable SQLite fixes.
Update the GRDB constraint through SwiftPM, allow SwiftPM to generate
`Package.resolved`, and rerun native tests, release measurements, linkage checks,
and the Core WASM smoke. Never manually edit the lockfile.

SQLite security/correctness updates come from the OS or distribution. Document
unsupported environments and known runtime defects even if basic probes pass;
these probes are not a complete SQLite conformance test. macOS remediation may
require an OS update. Linux users need a supported distribution/runtime package,
with appropriate development headers for source builds. If those requirements
become unacceptable, explicitly evaluate option 3.
