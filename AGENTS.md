# AGENTS.md

md-utils is a Swift package for parsing and manipulating Markdown files. It consists of four layers, each built on the previous:

1. **`MarkdownUtilitiesCore`** — Portable Markdown parsing and transformations for Apple platforms and Linux.
2. **`MarkdownUtilities`** — Core plus native filesystem, path, and metadata integrations.
3. **`md-utils`** — A CLI tool built on `MarkdownUtilities`.
4. **`markdown-utilities`** — An Agent Skill for AI coding assistants, distributed from `skill/markdown-utilities/`, built on the `md-utils` CLI.

[`treedocs`](https://github.com/DandyLyons/treedocs) is a sister project of `md-utils`. Future integrations are planned between the two projects.

## Project Brief

- **Agent skill maintenance (#198, 2026-10-24)**: User-facing CLI changes update focused references, with `SKILL.md` reserved for introductions/routing. `agents skill --output-directory` exports the full bundled folder without replacing installations. Run `scripts/sync-agent-skill.py` after every canonical skill edit; CI checks all bundled files, routing, examples, and export. See `docs/agent-skill-audit.md` for coverage and validation limits.

- **mdstandard parser decisions (2026-10-23)**: RFC 0005 requires explicit `predecessor: null` on the initial release and a predecessor object thereafter; omission is invalid. Owner approved rejecting duplicate keys, unknown fields, missing resources, unsupported language versions, and invalid digests, with optional `$schema` as editor metadata only (no runtime selection or fetching authority). Other concrete field syntax remains proposed.

- **mdstandard language specification (2026-10-23)**: `docs/rfcs/0005-mdstandard.md` begins the definition-language draft spanning #192–#196; runtime implementation is not required for this phase. Owner directions include Markdown diff review reports, successful cleanup within the apply command, and provisional manual staged-file editing with renewed validation/review. Concrete fields and operation syntax remain proposals, not approved formats.

- **Declarative staged transformations (owner direction 2026-10-23)**: Standard migrations and user import/export strategies use JSON actions executed by md-utils, with no arbitrary code. Default execution writes reviewable files in a side directory; a separate apply installs staged contents and cleans staging after success. Manual staged-file editing is provisionally approved with renewed validation/review. Operation syntax, review mechanics, backup policy, and runtime implementation remain open; see RFC 0005 and `docs/mdstandards-design.md`.

- **Independent standard releases (approved 2026-10-22)**: Independently downloadable releases contain their own contract dependencies and destination-owned incoming migration definitions. Explicit predecessor references pin standard identity, version, location, and digest; releases do not bundle all history. Migration preparation obtains only required source/intermediate dependencies for offline execution. This supersedes earlier pending-placement notes below; identifier syntax, operation formats, and branch policy remain open.

- **Required standard-version migrations (owner clarification 2026-10-22)**: Every authored standard must be versioned; every release after the first must define migration from its preceding version, including patch/minor/major transitions. #195 owns migration definitions/execution; #194 owns versioning/publication. This differs from #193's definition-format migrations. Destination-owned placement is approved; operation syntax and predecessor branching details remain design work.

- **Standards publication layout (approved 2026-10-21, refined 2026-10-22)**: Independent releases contain separate `rules/`, `types/`, and `schemas/` resources, with incoming migration declarations in the destination standard and separate bundled operation files. The optional root discovery catalog, concrete formats, and remaining #192 semantics are still proposals. See RFC 0005 for the current working specification.

- **Standards adoption proposal (#192, 2026-10-21)**: `docs/mdstandard-adoption.md` proposes explicit role/resource identities, author-authorized population rebinding with preserved-selection defaults, union populations for multiple local rules, aggregate policy proof, and one mode per role binding with mixed adoptions. Worked cases distinguish declarations, structural proof, data findings, and execution. Owner agreement is pending; no runtime/schema changes or mdrule v2 decision are authorized.

- **Contract-aware wikilink conversion (#185)**: `links convert --type Name` selects declared whole-value frontmatter wikilinks, including nested literal keys/arrays. Explicit style/extension preferences only disambiguate permitted repairs; conforming values remain unchanged. Core shares semantic policy/reference evaluation and typed edits; native preview uses bounded read-only snapshots, shared Fix-It conformance preservation, combined reassessment, and authoritative pre-write checks. Unresolved repairs exit nonzero with partial-batch reports. Recommendations are opt-in. Ambiguous alternatives and negative/existential rewrite intent remain review-required. See `docs/wikilink-conversion.md`; tests: `swift test --filter 'Wikilink|ContractConvertLinksTests|ConvertLinksTests'`.

- **mdstandards roadmap (#191)**: Design issues #192–#196 track adoption, structural rule conformance/possible mdrule format changes, versioning/publication, user-owned strategies and standard-author migrations, and exchange primitives. They use the Standards interoperability design milestone. Coordinate #169/#184/#135/#186 without expanding mdtype v2 completion scope; no mdrule v2 is selected. See `docs/mdstandards-roadmap-proposal.md`.

- **Standards primitive ownership and relationships (2026-10-21)**: The concept stack now treats relationships as cross-cutting declarations/assertions constrained by types and rules, distinguishing implemented mdtype declarations from proposed standalone semantics. Standard authors own version migrations; adopters own import/export strategies, including gaps caused by stronger local requirements. Recipe examples explore primitives only, not a recipe specification; conformance does not promise universal import success.

- **Standards exchange exploration (2026-10-21)**: `docs/md-recipes-use-cases.md` explores recipes/cooking entries, at-rest structural adoption and in-transit import/export adapters. Interoperability is the goal; selector ownership, mode exclusivity, profiles, and exchange packaging remain open. Stronger local rules do not imply universal import acceptance. This is design only.

- **Concept stack and mdstandards (design draft, 2026-10-21)**: `CONCEPT_STACK.md` documents existing schema/type/rule composition separately from implementation layers. `docs/mdstandards-design.md` records standards referencing minimum rule contracts, explicit user adoption and bindings to supplied or structurally conforming local rules. Additional requirements and multiple conformance are allowed; selector compatibility, proof methods, versioning, and migrations remain open. Standards are not implemented and no definition format is approved.

- **Indexed relationship projection (#188)**: Explicit CLI indexing publishes normalized body/frontmatter occurrences, named assertions, applicability, selector facts and SQL reverse edges without enabling FTS or retaining full bodies. Publication is staged, generation/epoch/profile-bound, and atomic; single-file snapshot queries decode only relevant sources. JMESPath selectors still require unavailable full-body envelope evidence. Publication skips unrelated type validation; type selectors need stored type evidence. Tests: `swift test --filter 'CollectionRelationshipQueryTests|IndexCommandsTests|RulesIndexedValidationTests'`; see `docs/index-only-queries.md` and the planning contract/status in `docs/relationship-query-relevance.md`.

- **Outgoing query performance (#188)**: Ordinary outgoing queries plan source sets before reading contents, bypass whole-collection index refresh/cache verification, lazily load named target dependencies, and verify only consumed records and resolution evidence. Exact destinations use confined existence probes; bare names lazily discover filenames. Ordinary incoming/both retain the certified collection path; index-only instead reads SQLite snapshots without filesystem verification. Regression tests use strict budgets and unreadable unrelated contents; benchmark: `python3 scripts/benchmark-relationship-outgoing.py`. See `docs/relationship-query-design.md`.

- **Scoped relationship queries (#188, implemented 2026-10-15)**:
  `--detail summary|explain|evidence` applies equally to text, JSON and YAML;
  summary defaults to declared triples/ordinary links with brief concern hints.
  Detail never changes evaluation or exit status. Selection/applicability decisions
  and input contracts are in `docs/relationship-query-design.md`. Core owns
  selection/applicability and normalized evidence; native sessions reuse #180.
  File lists use LF/NUL with strict UTF-8; BOM policy remains deferred to #189.
  Tests: `swift test --filter 'CollectionRelationshipQueryTests|RelationshipCommandsTests|RelationshipCacheTests'`.

- **Verified relationship cache (#180)**: Native relationship queries and rule validation reuse whole-collection-certified evidence across unchanged refresh generations. Certificates cover source/context revisions, candidate namespaces (including negative/ambiguous lookups), definitions/bindings, scopes, coverage, profiles and budgets. Cache format 9 uses bounded SQLite staging, atomic publication, epoch/generation checks, four-request/64 MiB retention, and 256 KiB chunks. Limited coverage stays limited; transient failures and exhaustion are uncached. Rebuild preserves external drafts/receipts. See `docs/relationship-cache.md` and `docs/relationship-cache-benchmarks.md`; tests: `swift test --filter 'RelationshipCache|RelationshipPolicyCommands|RelationshipRegressionCommands|RelationshipCommands|MarkdownMutationTests|MarkdownDraftTests'`.

- **Claims-first graph direction (2026-10-14)**: Human-readable files remain authoritative; types/rules are optional structure and inconsistent claims remain queryable with provenance. Query scope determines the graph view; semantic definitions must be separable from conformance requirements. See `docs/claims-first-document-graph.md` for agreed principles, open decisions, and the proposed RDF-inspired Core/SQLite projection architecture. This is future design, not implemented behavior or an approved backend selection; existing #169 contracts require explicit compatibility work before changes.

- **Relationship Fix-Its (#179)**: `rules fix [rule]` previews by default; `--select 1,4,5` (also repeatable) chooses explicit assertions and `--apply` opts into persistence. Numbered noninteractive application requires the printed evidence-bound `--review` token. `--yes` selects only automatic shared schema fixes; advisory repairs need `--include-recommendations`. Portable proposals and typed key/index edits reuse the shared Fix-It model and codec, reassess combined changes and preserve existing required conformance. Native application rechecks authoritative supporting records, definitions, candidate namespace and scope; extends shared durable drafts/receipts and leased writes without requiring server configuration; and reports partial completion/recovery through `index draft`/`index apply`. Cached evidence never replaces final authoritative repair checks. Tests: `swift test --filter 'MarkdownFixItReview|MarkdownRelationshipFixTests|MarkdownRuleFixTests|RulesFixCommandsTests|MarkdownDraftTests|MarkdownMutationTests|ResourceCodecTests'`; see `docs/relationship-policies.md` and `docs/index-apply.md`.

- **WASM verification deferred**: The installed Swift 6.4 compiler cannot import modules from the installed Swift 6.3.1 WASI SDK. Skip WASM builds and smoke checks during ordinary development, including Core changes, until preparation for a real release begins. See the verification policy below.

- **Collection relationship policies (#178)**: Explicit independent mdrule v1 adds cycles, self-links, reciprocity and directional inverse policies with selected/reachable scopes. Portable bounded collection evaluation retains pass/fail/unavailable, policy origins, boundary edges and conflict witnesses. `rules validate --json|--yaml` exposes evidence; mutually exclusive `--cycle-witness-per-component` (default) and `--cycle-witness-first` control cycle reporting. Evaluator fingerprint v6 invalidates older per-record evidence; #180 adds verified persistent policy reuse. Existing schemas/defaults remain unchanged. See `docs/relationship-policies.md`; tests: `swift test --filter 'MarkdownRelationshipPolicyTests|RelationshipPolicyCommandsTests'`. Reviewable repairs are implemented in #179.

- **Relationship review regressions (#177)**: Unsupported target representations remain unavailable independently of type constraints; candidate truncation retains proven ambiguity; propagated diagnostics retain property/declaration provenance. Rule routing inspects selected type dependencies, and type-hint verification shares collection-aware assessment. Permanent regression suites: `swift test --filter 'MarkdownRelationshipRegressionTests|RelationshipRegressionCommandsTests'`.

- **Named relationships (#177)**: Explicit mdtype v2 `document-relationships` compiles literal selectors and target resource bindings. Portable bounded three-way recursive assessment and native/index snapshot adapters power `relationships` (`rel`) `outgoing` (`out`), `incoming` (`in`), and `both`, JSON/YAML output, separate self-links, and type/rule validation. User-authored assertions do not establish domain truth. Indexed-only retains limited coverage, including during #180 cache reuse. See `docs/relationships.md` and `docs/relationship-design.md`; tests: `swift test --filter 'MarkdownRelationshipTests|RelationshipCommandsTests'`. Defaults and existing immutable schemas remain unchanged.

- **Wikilink constraints (#176)**: Explicit mdtype v2 `requires: [wikilink-constraints]` enables branch-aware style arrays and independent Markdown suffix checks in required/recommended loaded schemas. Diagnostics retain policy and instance locations; evaluator fingerprint v4 invalidated earlier assessments (now v5 with #177). Capability-bearing schema has a separate publication path, preserving original v2 artifacts. Relationship capability is implemented by #177; conversion enhancements stay in #185. Tests: `swift test --filter 'WikilinkStylePolicyTests|MarkdownSemanticScalarTests|RulesIndexedValidationTests'`.

- **Wikilink policy boundaries (#176/#185)**: Strict vault paths cannot spell root-level destinations; absolute paths are deferred. `wikilink-constraints` and `document-relationships` are implemented with separate explicit gates. Contract-aware conversion is separately tracked in #185.

- **Unified mdtype v2 design (#169)**: Semantic scalars (RFC 0003), authored wikilink constraints (#176), and named relationships (RFC 0004) share mdtype v2; the earlier relationship-v3 reservation is superseded. Scalar runtime support is only a partial implementation. Relationship policies retain independent mdrule v1. Reader capability rejection and immutable schema publication require coordination with #184 before combined activation.

- **Wikilink provenance (#175)**: Core document/record occurrence APIs retain literal property keys, all array indices, duplicates, parsing context and decoded-text UTF-8 ranges. Record snapshots retain identity/revision/context and supply exact raw ranges for body matches only; frontmatter raw ranges are unavailable. Discovery remains separate from scalar/relationship validation. See `docs/wikilink-provenance.md`; tests: `swift test --filter 'Wikilink|MarkdownSemanticScalarTests|ConvertLinksTests'`.

- **Wikilink parsing contexts**: Discovery and whole-value parsing share syntax validity and escaping within explicit standard, Markdown table, or legacy contexts. Declared scalars use standard text; document discovery retains legacy defaults. Body occurrences do not automatically assert frontmatter contracts. Tests: `swift test --filter 'Wikilink|MarkdownSemanticScalarTests|ConvertLinksTests'`.

- **Declared semantic strings (#173/#174)**: Explicit mdtype v2 supports whole-value Wikilink, Date, LocalTime, DateTime and UUID profiles, schema-level recommendations, native temporal kind evidence, and branch-aware assertions through a finite-instance schema adapter. Defaults remain v1; evaluator fingerprint v3 invalidates cached assessments. See `docs/semantic-string-formats.md`; tests: `swift test --filter 'MarkdownSemanticScalarTests|RulesIndexedValidationTests'`. Linux verification remains CI-only.

- **Document relationships (specified #172)**: RFC 0004 shares mdtype v2 with semantic scalars and reserves explicit mdrule v1 for collection policies, covering named frontmatter references, bounded host-supplied collection evidence, positive recursive conformance, and separately declared cycle/reciprocal/inverse policies. Partial coverage cannot establish global consistency; candidate-set changes invalidate dependent assessments. Named relationship runtime is implemented by #177 with a separate schema artifact; policies and persistent relationship assessment reuse are implemented by #178/#180. Authoring defaults remain unchanged. See `docs/rfcs/0004-document-relationships.md`.

- **Semantic string formats (specified #171)**: RFC 0003 reserves mdtype v2 for `type: string` / `format: Subject/RawFormat`, Foundation-backed validation, schema-level advisories, nullable branches, and v4-only UUID generation with multi-version input. Implementation is #173/#174; publication/default activation remains separate, and #184 owns the broader compatibility matrix. See `docs/rfcs/0003-semantic-string-formats.md`; current mdtype v1 is unchanged.

- **Wikilink resolution (#170)**: Slash-containing targets are vault-root-relative;
  only `./` and `../` select source-relative paths. No cross-base or basename
  fallback is allowed. Bare-name ambiguity, omitted `.md`/`.markdown` support,
  exact attachment extensions, and snapshot confinement remain. List/check/backlinks
  share the resolver. Tests: `swift test --filter 'Wikilink|ConvertLinksTests'`.

- **Wikilink extension spelling**: `links convert --markdown-extension auto|include|omit` defaults to including actual Markdown extensions for `wiki-path` and omitting them for `wiki-link`. Other extensions are always preserved; ambiguous omission is skipped. Covered by `WikilinkConversionTests` and `ConvertLinksTests`.

- **Wikilink conversion**: `links convert --to wiki-path|wiki-link` requires explicit `--root`, previews by default, and writes with `--in-place`. Shared planning checks destination equivalence and preserves aliases/fragments/embeds, with body/frontmatter/key selection, revision-checked writes, no-op preservation, and partial batch reports. Explicit paths never fall back to basename matching; root-level ambiguity is skipped. See `docs/wikilink-conversion.md`; tests: `swift test --filter 'Wikilink|ConvertLinksTests'`. Markdown-link and server support remain separate (#182/#183).

- **Bulk instance creation**: `types new`/`rules new` accept `--values` JSON arrays or repeated `--value-file` objects, requiring JSONPath filenames. Shared preflight applies defaults/rendering/advisory conformance, collects failures and all collision participants, and bounds input/output at 64 MiB and 10,000 items. Atomic no-clobber publication stops on the first failure with complete partial-completion reporting. Dry run has no persistent side effects. See `docs/instance-creation.md`; tests: `swift test --filter 'CreationBatchTests|InstanceCreationTests'`.

- **Instance creation**: `types new` and `rules new` use mdtype Knap creation declarations. Document mode is default with upstream object-variable semantics; explicit body mode serializes frontmatter separately. Input defaults precede JSONPath filename selection and validation; type/rule nonconformance is advisory. Destinations must exist and atomic hard-link publication never overwrites. See `docs/instance-creation.md`; tests: `swift test --filter 'CreationTemplateTests|InstanceCreationTests|TemplateTests'`.

- **SQLite-only findings (corrected #165/#188)**: `--index-only` and `--indexed-only` are identical on relationship queries and rule validation. Read only published SQLite evidence; never load raw documents/configuration/schemas, stat sources, refresh, acquire writer leases, write the index or fall back. Reject `--verify-hashes`/`--no-index`. Rule output identifies its snapshot; missing relationship/body/selector evidence stays unavailable. Earlier known-candidate-refresh wording was a misunderstanding. See `docs/index-only-queries.md`; tests: `swift test --filter 'RulesIndexedValidationTests|CollectionRelationshipQueryTests'`.

- **Frontmatter string serialization and explicit null**: YAML serialization uses Yams' string representer to preserve empty strings and text resembling null, booleans, or numbers. `fm set --value ''` survives CLI write/read and string-schema validation in YAML and TOML; unrelated YAML null values and note bodies are preserved. `fm set --null` explicitly assigns null, requires exactly one of `--value`/`--null`, and rejects TOML unless explicitly converted to YAML. Tests: `swift test --filter 'SetStringRoundTripTests|SetTests'`.

- **Rule discovery performance**: Simple positive path globs and match leaves derive safe literal directory prefixes using Parsing. Direct validation and native CLI rule indexing scan only those prefixes, excluding symlink ancestors; missing prefixes prune old members, while recursive groups/broad globs retain full discovery. Markdown-only discovery avoids stat calls for unrelated file extensions. Evaluator runtime v2 invalidates older assessments. Tests: `swift test --filter 'MarkdownRuleDiscoveryTests|RulesIndexedValidationTests|MarkdownUtilitiesIndexTests|RulesCommandsTests|IndexCommandsTests'`.

- **Automatic indexed rule validation**: `rules validate` refreshes an existing project index's requested rule scopes and reads generation-checked assessments, preserving direct reporting. Index failures warn and fall back to source validation; cancellation stops. `--no-index` bypasses the cache; `--verify-hashes` detects stat-preserving edits. Uncached scans above 1,000 files suggest indexing. Shared source changes invalidate unrefreshed scopes. Both paths currently skip symlinks; future consistent symlink support is desired. See `docs/collection-index.md`; tests: `swift test --filter 'RulesIndexedValidationTests|SelectiveIndexRefreshTests|RulesCommandsTests|IndexCommandsTests'`.

- **Linux ARM64 server distribution**: The shared native release workflow packages `md-utils-server` independently of the CLI for Ubuntu 24.04/aarch64, with static Swift runtime, explicit resources, checksums and shared corresponding source. Host-driven installed-artifact tests use a clean runtime image and mounted collection to verify HTTP/OpenAPI, SQLite, Knap creation, replay and SIGTERM; offline rebuilds exercise both products. Linux validation remains CI-only and tagged server publication is pending. See `docs/linux-arm64-server-distribution.md`.

- **Empty frontmatter arrays**: `fm array init` creates a typed empty array for missing or null literal top-level keys; existing arrays are preserved and nonempty arrays are reported. `fm array clear` empties arrays while retaining keys, leaving missing keys unchanged and rejecting null. Both reject other non-array values, preserve bytes and modification time on no-op, and use existing frontmatter mutation/authorization conventions. Format conversion applies only on mutation. See `docs/common-use-cases.md`; tests: `swift test --filter 'ArrayEmptyTests|NonMDFrontmatterCLISemanticsTests'`.

- **Schema portability coverage**: Linux ARM64 release and offline rebuild scripts apply a revision-checked JSONSchema.swift 0.6.0 patch using native Swift container type checks; the first prerelease rejected valid arrays through `NSArray` checks. CI runs config/rules, container/scalar preservation, and type-checker suites. The installed archive smoke test loads generated empty configs and true/false fields, and rejects boolean/number substitutions in frontmatter. `JSONValue` checks Foundation number identity before conditional scalar casts. See `docs/linux-arm64-distribution.md`; tests: `swift test --filter 'ConfigScalarValidationTests|JSONValueTests|ConfigCommandsTests|RulesCommandsTests|MarkdownTypeCheckerTests'`.

- **Builds and distribution**: See `docs/building-and-platforms.md` for the platform/CI matrix and resource-preserving installation. Linux ARM64 CLI/server prereleases target Ubuntu 24.04 with static Swift runtime and system shared libraries; tagged publication is separate from verified CI artifacts. macOS uses source/Mint; WASM release packaging remains pending. Artifact and schema versions evolve independently; see `docs/release-procedures.md`.

- **Linux ARM64 distribution**: Prerelease CLI archives target Ubuntu 24.04/glibc/aarch64 with Swift 6.3.1, statically linked Swift runtime, system SQLite/JavaScriptCore, explicit resources, checksums, and companion dependency source/relinking archives. Native ARM64 CI validates archive installation in a toolchain-free runtime and offline source rebuilds. See `docs/linux-arm64-distribution.md` for CI verification commands. CLI artifact versions are independent of config/schema versions; the initial preview is `0.3.0-linux.1`.

- **Pending edits**: `MarkdownDraftService` persists versioned drafts outside SQLite, resolves configured UUIDs conservatively (following only retained coordinator-confirmed moves), and shares codec/policy/uniqueness planning with REST. `index draft` stages/inspects/discards/resolves intent; `index apply --dry-run` has no persistent side effects. Apply uses revision checks, pinned durable receipt linkage, sequential per-file commits, and explicit partial-completion recovery. Refresh, FTS changes, and rebuilds preserve actual drafts and conflict baselines. See `docs/index-apply.md`; tests: `swift test --filter 'MarkdownDraftTests|IndexApplyCommandsTests|MarkdownMutationTests|CollectionIndexerTests'`.

- **Managed copy/move**: Shared native mutation operations power REST and `md-utils copy`/`move`, with explicit resource opt-ins, revision checks, idempotency, no-clobber destinations and durable two-path recovery. Copy allocates a fresh configured UUID; move preserves bytes/UUIDs. See `docs/copy-move.md`; tests: `swift test --filter 'MarkdownMutationTests|MarkdownMutationOpenAPITests|TransferCommandsTests'`.

- **Document provenance**: Core owns portable observations and conservative UUID collision explanations; the native index retains bounded first/latest observations and confirmed receipt events. Rebuild discards history. `index provenance` exposes revision-verified evidence; native `explainUUIDCollision` remains read-only. See `docs/document-provenance.md`; tests: `swift test --filter 'DocumentProvenanceTests|IndexProvenanceTests|MarkdownMutationTests'`.

- **Language**: Swift 6.3+
- **REST mutations**: Explicit config v3 operation opt-ins use a derived `FileEditPolicy`, #90 codecs, source revision headers, collection writer leases, atomic native writes, and durable receipts outside SQLite. Creation supports expressive filenames, optional slug allocation, creation-only identifiers, and opted-in UUID generation. Identity edits and UUID repair are separate. OpenAPI includes enabled mutations, aliases, receipts, status/recovery, and codec-specific requests from the same endpoint plan. CLI drafts share native edit planning and coordinated persistence. See `docs/rest-mutations.md`; tests: `swift test --filter 'MarkdownMutationTests|MarkdownMutationOpenAPITests|MarkdownServerOpenAPITests'`.
- **Slug generation**: Core's `MarkdownSlugGenerator` provides pure generation and supplied-value validation; `md-utils slug` prints a candidate without changing files or guaranteeing uniqueness. Heading anchors retain historical behavior. See `docs/slug-generation.md`; tests: `swift test --filter 'MarkdownSlugGeneratorTests|SlugTests|HeadingTextExtractorTests'`.
- **Named server lookups**: Server config v2 adds explicit named aliases, resource/server uniqueness constraints, and optional shared UUID assessment, retaining v1 reads. Native aliases use bounded disk staging in the existing publication generation; portable snapshots share identity semantics. Lookup/protection/uniqueness are separate. No mutation routes are enabled by #153. See `docs/resource-lookups.md`; tests: `swift test --filter 'NamedLookupTests|IndexedMarkdownRepositoryTests'`.
- **Writable resource planning**: Core owns explicit top-level metadata/body codecs, revision-bound proposals, and mutation validation; Templates reuses the shared SwiftKnap renderer for creation. Server resources may declare `writable` without enabling HTTP write routes. Validation preserves all currently passing loaded types/rules by default, with an explicit endpoint-only override. Metadata edits preserve values and body bytes, not frontmatter comments/formatting; body-only edits retain frontmatter bytes. See `docs/resource-mutations.md`; tests: `swift test --filter 'ResourceCodecTests|ResourceMutationValidatorTests|TemplateResourceCreationCodecTests|ResourceMutationPlannerTests'`. No persistence or REST mutations are implemented by #90.
- **Knap templates**: `MarkdownUtilitiesTemplates` uses SwiftKnap through its public Swift API, outside Core/WASM. `template render` defaults to a complete document with named object variables and creation input defaults; explicit body mode combines a Knap body with JSON frontmatter serialized by Yams. Server creation retains its explicit envelope and validation policy. SwiftKnap owns execution and portability. Linux builds require its documented native development/runtime packages; see `docs/template-rendering.md`. Tests: `swift test --filter 'MarkdownUtilitiesTemplatesTests|TemplateTests|MarkdownMutationTests'`.
- **Native indexing**: `MarkdownUtilitiesIndex` uses upstream GRDB with system SQLite, Swift Crypto SHA-256, and Swift System for bounded native file reads and metadata. Directory traversal uses a Swift adapter over Foundation's incremental enumerator with explicit error propagation. Index JSON uses typed `Encodable` payloads and `JSONEncoder`, without autorelease pools. The CLI's `index update/type/rule` commands cache persisted scopes in `.md-utils/index.sqlite`; see `docs/collection-index.md`. JSON and expression indexes are baseline probes; FTS5 is probed only for opt-in FTS caches. New caches choose and record JSONB or JSON text from the linked runtime. Refresh and SQL output use bounded streaming/staging. Core, WASM, and `MarkdownUtilitiesServer` have no GRDB/SQLite dependency. `MarkdownUtilitiesIndexNative` shares native evaluation with the CLI; `MarkdownUtilitiesServerNative` supplies bounded indexed reads and macOS watching to the native server executable. See `docs/indexed-server-reads.md` for pagination, publication, and source-revision guarantees. See `docs/sqlite-index-packaging.md` for runtime requirements. Xcode-based database integration is rejected.
- **Frameworks/Libraries**: Foundation, MarkdownSyntax, PathKit, Yams, swift-toml, JMESPath, DynamicJSON, JSONSchema.swift, swift-argument-parser, Noora (interactive CLI authoring), Rainbow, Hummingbird 2, Swift Logging
  - **parsing**: Any code that involves parsing text must use the `Parsing` library like the rest of the codebase.
- **Package Manager / Build Tool**: Swift Package Manager
- **Index lifecycle**: `.md-utils/md-utils.indexconfig.json` owns index settings. Full rebuilds create fresh caches from files, discard history, and restore managed declarations. Cache format checks replace historical migrations. Legacy development settings are not imported. Pending user edits must live outside the disposable index; rebuild refuses legacy pending-edit tables. `index update --rebuild --metadata-encoding text` uses this same lifecycle under exclusive writer access. Durable receipts remain separate.
- **Executable Targets**: `md-utils`, `md-utils-server`
- **Index watching**: `index watch` uses a bounded `AsyncStream`, actor-isolated debounce state, `ContinuousClock`/`Duration`, and structured concurrency with Swift Service Lifecycle's `UnixSignalsSequence`. The isolated macOS FSEvents adapter is a justified C API exception: recursive hierarchy notifications and event-loss reporting avoid per-file open descriptors. Refresh reuses the staged update service and persisted storage mode. Other platforms explicitly require `index update`; see `docs/collection-index.md`.
- **Library Targets**: `MarkdownUtilitiesCore`, `MarkdownUtilities`, `MarkdownUtilitiesServer`, `MarkdownUtilitiesIndex`, `MarkdownUtilitiesIndexNative`, `MarkdownUtilitiesServerNative`
- **Test Framework**: Swift Testing, not XCTest
- **Build Command**: `swift build`
- **Test Command**: `swift test`; native Linux server route smoke test with `swift run MarkdownUtilitiesServerLinuxSmoke`
- **Formatter/Linter**: No dedicated formatter or linter is configured in-package
- **Documentation**: README.md, AGENTS.md, docs/*.md, generated CLI help, and bundled Agent Skill docs
- **Security**: Avoid unsafe optional force unwraps; treat filesystem and YAML/TOML/JSON parsing failures as user-visible errors
- **CI/Coverage**: Schema publication, Pages, WebAssembly, native Linux server, native SQLite, and Linux ARM64 CLI distribution workflows are configured; Linux builds run in CI only. The ARM64 workflow verifies clean runtime installation and offline corresponding-source rebuilding. No coverage command is documented. Refresh scale measurements use `scripts/benchmark-index-refresh.py`; see `docs/index-refresh-benchmarks.md` for corpus characteristics and resource budgets.

## Requirements

- **Swift 6.3** or later
- **Package Manager**: Swift Package Manager (SPM)
- **Test Framework**: Swift Testing (NOT XCTest)

## Build and Test Commands

```bash
# Build
swift build

# Test
swift test

# Run CLI
swift run md-utils <command>
```

Linux Docker builds and validation run in CI only.

### WASM verification policy

Skip WASM builds and smoke checks until we begin preparing for a real release,
including when changing `MarkdownUtilitiesCore` or its dependencies. This overrides
the routine WASM verification requirements in `docs/development-workflow.md` and
other project documentation. Continue normal native builds and tests.

The installed Swift 6.4 compiler cannot import the Swift 6.3.1 modules supplied by
the installed `swift-6.3.1-RELEASE_wasm` SDK. Do not repeatedly retry this known
toolchain/SDK mismatch or install replacement tooling as part of ordinary work.
Record WASM verification as deferred, not passed.

When preparation for a real release begins, revisit the blocker, use an exactly
matching Swift toolchain and WASI SDK, and run the WASM build and smoke checks
before claiming verified WASM support. Any tooling installation still requires
the user's explicit permission.

> [!Note] 
> If no `.build/` directory exists, run `swift build` first to create. Do not use the `.build/` directory from another worktree or branch. 

## Critical Rules

**Modern Swift APIs**: Prefer modern Swift APIs. Do not introduce Objective-C or
C APIs when a suitable Swift API exists. Any necessary exception must have a
documented technical reason and stay behind an isolated adapter.

**STRICTLY FORBIDDEN: Force Unwrapping with `!`**

Force unwrapping optionals with `!` is absolutely prohibited. Use safe alternatives:
- Optional binding (`if let`, `guard let`)
- `try #require()` in tests
- Nil coalescing (`??`)
- Optional chaining (`?.`)

## Text Encoding

- UTF-8 is the only supported text encoding. Reject invalid UTF-8 with a
  user-visible error; do not guess legacy encodings or silently replace invalid
  bytes while decoding authoritative input.
- Encoding validity and BOM handling are separate. Follow the specific input
  contract rather than adding a blanket BOM rule: fm-var sources explicitly
  accept one leading UTF-8 BOM, while canonical Markdown frontmatter mutation
  envelopes reject BOM-prefixed blocks.
- Existing references: `docs/collection-index.md` (non-UTF-8 read failures),
  `Sources/MarkdownUtilitiesCore/Documentation.docc/ResolvingFMVarSources.md`
  (strict UTF-8 and BOM handling), and `docs/resource-mutations.md`.

## Line Endings and CRLF

- **LF is the only supported newline format for Markdown document processing.
  CRLF and mixed-line-ending documents are unsupported; do not silently normalize
  them or claim reliable parsing. Operations promising byte preservation must
  still preserve untouched bytes.**
- Unsupported input does not imply that every existing command detects or rejects
  it. This support policy is not a claim of uniform runtime enforcement.
- Follow the existing LF-only **frontmatter delimiter** policy. Do not normalize
  CRLF delimiter blocks to LF to make them recognizable. Frontmatter parser tests
  must explicitly verify CRLF delimiter non-recognition; mutation codecs reject
  unsupported delimiter forms rather than silently repairing them.
- Preserving existing CRLF body bytes is a preservation safeguard, not a guarantee
  of supported body parsing. Standalone YAML decoding follows its supported YAML
  line endings. Preserve all original bytes on semantic no-ops.
- New line-oriented inputs (for example file lists) need their own documented
  delimiter contract. Do not infer it from the frontmatter rule or introduce
  global newline normalization. Include relevant LF/CRLF regression cases.
- Authoritative guidance: `docs/testing-standards.md` (Regression Tests),
  `docs/resource-mutations.md` (byte preservation and canonical LF delimiters),
  and `FMVarMarkdownYAMLExtractor`'s documented standalone-YAML distinction.

## Path Conventions

- Use explicit trailing slashes for all paths that refer to directories, including examples, documentation, config snippets, and CLI help text. Bare `.`, `..`, and `~` are exceptions and do not need trailing slashes.

## OKF Support

- OKF tooling currently targets the Open Knowledge Format v0.1 draft.
- The OKF v0.1 draft spec is readable at https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md.
- Do not make OKF behavior stricter than the draft conformance rules unless the command clearly labels checks as advisory.
- Do not guess OKF `type` values. Apply a `type` only when the user provides the value explicitly.

## Documentation

### CLI help verification before committing

Any time an `AsyncParsableCommand` is edited, view its `--help` page from the
actual executable before committing and verify that the help is up to date with
the implementation. Check descriptions, defaults, aliases, options, examples,
output formats, input scope/recursion, frontmatter support, and index behavior
where applicable. Verify affected parent/group help for discoverability and any
other help pages changed through shared options or command configuration. Rebuild
first when needed; record the verification in the task's review notes.

Detailed guidance organized by topic:

- **[Architecture](docs/architecture.md)** - Project structure, core types, dependencies, features
- **[Portability Audit](docs/portability-audit.md)** - Target boundary, Linux validation, and WebAssembly blockers
- **[Testing Standards](docs/testing-standards.md)** - Swift Testing conventions and patterns
- **[Swift Coding Standards](docs/swift-coding-standards.md)** - Language-specific rules and safe practices
- **[CLI Patterns](docs/cli-patterns.md)** - Command structure and argument parsing
- **[Development Workflow](docs/development-workflow.md)** - Feature addition process and commit checklist
- **[Building and Platforms](docs/building-and-platforms.md)** - Toolchains, platform support, CI coverage, resources, and distributions
- **[Common Use Cases](docs/common-use-cases.md)** - CLI usage examples and recipes
- **[Release Procedures](docs/release-procedures.md)** - Versioning and release process

## Maintaining the Agent Skill

For every user-facing CLI change, review and update the canonical skill at
`skill/markdown-utilities/skills/markdown-utilities/` in the same change. This
includes new or removed commands and changes to flags, defaults, aliases, output,
exit status, selection, supported formats, version/capability gates, persistence,
or recovery. Changes in shared libraries that affect CLI behavior also count.

Keep `SKILL.md` focused on introductions, task routing, and essential shared
constraints. Put detailed syntax, examples, workflows, limitations, and recovery
instructions in the relevant `references/` file. Update the entrypoint only when
its introduction, routing, or shared guidance changes; do not append every feature
detail there. Add a focused reference and a discoverable link when no existing
reference fits. Keep guidance self-contained for installed skill users.

Contract authoring belongs in `references/rules.md`, `types.md`, and `schemas.md`.
Keep `references/standards.md` a short upcoming-feature notice linked to
[#191](https://github.com/DandyLyons/md-utils/issues/191) until supported standards
authoring is ready. Other features use their relevant document-operation reference;
do not load or duplicate unrelated guidance.

Before completing a CLI change:

1. Compare affected skill guidance with implementation and actual executable help,
   including parent/group help when discoverability changes.
2. Run representative changed examples against isolated project-local fixtures,
   checking expected success/failure and preview/write behavior as applicable.
   Rebuild first when the executable would otherwise be stale.
3. Check added or changed reference links resolve from their containing file and
   that detailed guidance is reachable from `SKILL.md` or another routed reference.
4. Synchronize the complete bundled skill after any canonical skill change,
   including reference-only edits, using the procedure below.
5. Record the skill files updated and verification performed in review notes. If
   no skill update is needed, record the concrete reason (for example, an internal
   refactor with no user-visible behavior change).

### Synchronizing the complete bundled skill

`Sources/md-utils/Resources/AgentSkill/` is generated from the complete canonical
`skill/markdown-utilities/skills/markdown-utilities/` folder. SwiftPM preserves this
directory in the CLI bundle. Do not edit the generated copy directly.

After editing any canonical skill file, run:
```bash
# Synchronize all files, then check routing, built resources, and examples.
python3 scripts/sync-agent-skill.py
python3 scripts/check-agent-skill.py
swift test --filter AgentCommandsTests
python3 scripts/check-agent-skill.py --cli .build/debug/md-utils
python3 scripts/verify-agent-skill-examples.py --cli .build/debug/md-utils
```
Include canonical and generated changes together. Agent Skill CI checks added and
deleted references as well as bytes. Update [the coverage matrix](docs/agent-skill-audit.md)
for new command groups and extend representative workflows for changed behavior.
Automated checks cannot prove all prose correct: review implementation and help.
Linux release smoke exports the folder too; local Linux verification remains CI-only.
`agents skill` prints only the entrypoint; `--output-directory` exports the full skill.

## Refreshing Official fm-var Fixtures

The conformance fixtures are owned by [`DandyLyons/fm-var-tag`](https://github.com/DandyLyons/fm-var-tag). Do not add or edit consumer-specific cases under `Tests/MarkdownUtilitiesCoreTests/Fixtures/FMVar/cases/`; refresh the checked-in copy from the upstream repository instead. The upstream `fixtures/` directory is copied to `Tests/MarkdownUtilitiesCoreTests/Fixtures/FMVar/official-fixtures/`.

To fetch the latest upstream fixtures, use a project-local temporary directory (the temporary directory must not be committed):

```bash
fixture_tmp="$(mktemp -d ./tmp/fm-var-tag-fixtures.XXXXXX)"
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/DandyLyons/fm-var-tag.git "$fixture_tmp/repo"
git -C "$fixture_tmp/repo" sparse-checkout set fixtures
rm -rf Tests/MarkdownUtilitiesCoreTests/Fixtures/FMVar/official-fixtures
mkdir -p Tests/MarkdownUtilitiesCoreTests/Fixtures/FMVar/official-fixtures
cp -R "$fixture_tmp/repo/fixtures/." \
  Tests/MarkdownUtilitiesCoreTests/Fixtures/FMVar/official-fixtures/
rm -rf "$fixture_tmp"
```

Review the resulting diff, then run `swift test --filter MarkdownUtilitiesCoreTests` (or `swift test`) before committing. The upstream fixture README defines the fixture contract; diagnostic wording and host-specific behavior remain the consumer's responsibility.

## Status

This project is on a `0.x.x` release and is not yet API stable. Breaking changes will be documented in release notes.
