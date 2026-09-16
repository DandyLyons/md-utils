# GRDB and StructuredQueries evaluation

Reviewed September 16, 2026 for the indexing phase of #93. The selected approach
is now upstream GRDB with system SQLite through SwiftPM (option 1). The GRDB
integration and measurements are described in [SQLite packaging](sqlite-index-packaging.md).
StructuredQueries remains deferred; its evaluation below is a source review,
not an integration benchmark.

| Candidate | Benefit here | Cost | Decision |
| --- | --- | --- | --- |
| GRDB | Bindings, decoding, transactions, migrations, serialized access and pools | System-runtime prerequisites, Linux validation, Swift compilation | Adopted through upstream SwiftPM packaging |
| StructuredQueries | Typed, composable internal queries | Macros, driver integration, another API to maintain | Revisit after schema and queries stabilize |
| SQLiteData | GRDB/StructuredQueries integration and observation | Broader application-state dependency graph | Do not adopt solely to connect the other two |

## GRDB decision

GRDB's infrastructure maps to transactional document/assessment/FTS updates in
#138 and consistent reads in #139/#141. It also supplies its own query builder.
Its observation features do not replace filesystem watching/reconciliation in
#140. The prior C bridge was only a capability prototype; retaining it would
have meant implementing production statement lifetimes, bindings, decoding,
concurrency, cancellation, and error propagation ourselves.
[GRDB README](https://github.com/groue/GRDB.swift/blob/v7.11.1/README.md).

GRDB v7.11.1 requires Swift 6.1 and uses a system SQLite target. It has no normal
external Swift package dependency (its documentation plugin is conditional).
Linux snapshot APIs are disabled by its manifest. Upstream describes Linux
support as contributor-maintained, so this repository owns Linux validation.
[Manifest](https://github.com/groue/GRDB.swift/blob/v7.11.1/Package.swift).

Option 1 accepts OS/distribution SQLite version and capability variation, guarded
by executable probes and documented prerequisites. No bundled runtime remains.
If this becomes unsuitable, option 3 is a fallback: adapt GRDB's C module and
SwiftPM packaging to a controlled bundle, retaining symbol isolation and Linux
support. That work is not selected automatically or included here. Option 2,
GRDB's Xcode custom-framework workflow, is explicitly rejected.
[Custom SQLite workflow](https://github.com/groue/GRDB.swift/blob/v7.11.1/Documentation/CustomSQLiteBuilds.md).

## StructuredQueries assessment

StructuredQueries builds typed SQL and requires a driver. Its documented custom
integration needs `QueryDecoder` and statement execution helpers; GRDB is not
technically mandatory. Adding it does not replace connection/transaction work.
[Driver integration](https://github.com/pointfreeco/swift-structured-queries/blob/0.39.2/Sources/StructuredQueriesCore/Documentation.docc/Articles/Integration.md).

The best fit is the fixed internal schema: files, documents, memberships,
assessments, and joins. User-defined metadata, JSON paths, configured views, and
arbitrary SQL in #139 remain runtime concerns. A typed builder cannot prove user
SQL is read-only or guarantee expression-index usage. We still need read-only
enforcement and query-plan tests; raw SQL escape hatches reduce compile-time
protection for dynamic pieces.

Release 0.39.2 has a Swift 6.1-specific manifest compatible with our toolchain
minimum despite its default manifest declaring Swift 6.4. Macro products use
SwiftSyntax; the basic core uses IssueReporting, with optional CasePaths/Tagged
traits. Test dependencies are not all runtime dependencies. Our lockfile already
contains SwiftSyntax, CasePaths, and xctest-dynamic-overlay: measure incremental
cost rather than charging the entire graph again. Macro compilation still
matters for an otherwise small native target.
[Versioned manifest](https://github.com/pointfreeco/swift-structured-queries/blob/0.39.2/Package%40swift-6.1.swift).

The README mentions `StructuredQueriesGRDB`, but inspected SQLiteData manifests
expose `SQLiteData` and `SQLiteDataTestSupport`, not a separately selectable GRDB
adapter. Its main target also uses Sharing, Perception, Dependencies, and
ConcurrencyExtras. Verify the chosen release's products before assuming the
adapter can be consumed alone.
[Driver overview](https://github.com/pointfreeco/swift-structured-queries#database-drivers),
[SQLiteData manifest](https://github.com/pointfreeco/sqlite-data/blob/main/Package%40swift-6.1.swift).

## Revisit during #139

Compare several actual queries implemented with bound SQL, GRDB's own builder,
and StructuredQueries. Include optional values, joins, dynamic JSON fields, and
expression-index plans. Measure clean builds, query-edit build latency, stripped
binary size, and representative refresh/query performance with identical SQLite
versions, schemas, and transaction boundaries. Use multiple runs and separate
dependency downloads and host macro compilation from target compilation.

Adopt StructuredQueries only if examples show a meaningful safety/maintenance
gain that outweighs those costs. Keep it in the native indexing target; neither
GRDB nor StructuredQueries belongs in portable Core. There are no measured
StructuredQueries overhead figures yet.
