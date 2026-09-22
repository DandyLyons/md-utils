# AGENTS.md

md-utils is a Swift package for parsing and manipulating Markdown files. It consists of four layers, each built on the previous:

1. **`MarkdownUtilitiesCore`** — Portable Markdown parsing and transformations for Apple platforms and Linux.
2. **`MarkdownUtilities`** — Core plus native filesystem, path, and metadata integrations.
3. **`md-utils`** — A CLI tool built on `MarkdownUtilities`.
4. **`markdown-utilities`** — An Agent Skill for AI coding assistants, distributed from `skill/markdown-utilities/`, built on the `md-utils` CLI.

[`treedocs`](https://github.com/DandyLyons/treedocs) is a sister project of `md-utils`. Future integrations are planned between the two projects.

## Project Brief

- **Language**: Swift 6.2+
- **Slug generation**: Core's `MarkdownSlugGenerator` provides pure generation and supplied-value validation; `md-utils slug` prints a candidate without changing files or guaranteeing uniqueness. Heading anchors retain historical behavior. See `docs/slug-generation.md`; tests: `swift test --filter 'MarkdownSlugGeneratorTests|SlugTests|HeadingTextExtractorTests'`.
- **Named server lookups**: Server config v2 adds explicit named aliases, resource/server uniqueness constraints, and optional shared UUID assessment, retaining v1 reads. Native aliases use bounded disk staging in the existing publication generation; portable snapshots share identity semantics. Lookup/protection/uniqueness are separate. No mutation routes are enabled by #153. See `docs/resource-lookups.md`; tests: `swift test --filter 'NamedLookupTests|IndexedMarkdownRepositoryTests'`.
- **Writable resource planning**: Core owns explicit top-level metadata/body codecs, revision-bound proposals, and mutation validation; Templates reuses the shared Stencil renderer for creation. Server resources may declare `writable` without enabling HTTP write routes. Validation preserves all currently passing loaded types/rules by default, with an explicit endpoint-only override. Metadata edits preserve values and body bytes, not frontmatter comments/formatting; body-only edits retain frontmatter bytes. See `docs/resource-mutations.md`; tests: `swift test --filter 'ResourceCodecTests|ResourceMutationValidatorTests|TemplateResourceCreationCodecTests|ResourceMutationPlannerTests'`. No persistence or REST mutations are implemented by #90.
- **Template prototype**: `MarkdownUtilitiesTemplates` isolates Stencil from Core/WASM. `template render` combines a self-contained Stencil body with an explicit JSON frontmatter object serialized by Yams. JSON input/schema validation and size guardrails are shared library behavior; includes tooling, TOML output, formatting helpers, and strict missing-value diagnostics are deferred. See `docs/template-rendering.md`; focused tests: `swift test --filter MarkdownTemplateRendererTests` and `swift test --filter TemplateTests`.
- **Native indexing**: `MarkdownUtilitiesIndex` uses upstream GRDB with system SQLite, Swift Crypto SHA-256, and Swift System for bounded native file reads and metadata. Directory traversal uses a Swift adapter over Foundation's incremental enumerator with explicit error propagation. Index JSON uses typed `Encodable` payloads and `JSONEncoder`, without autorelease pools. The CLI's `index update/type/rule` commands cache persisted scopes in `.md-utils/index.sqlite`; see `docs/collection-index.md`. JSON and expression indexes are baseline probes; FTS5 is probed only for opt-in FTS caches. New caches choose and record JSONB or JSON text from the linked runtime. Refresh and SQL output use bounded streaming/staging. Core, WASM, and `MarkdownUtilitiesServer` have no GRDB/SQLite dependency. `MarkdownUtilitiesIndexNative` shares native evaluation with the CLI; `MarkdownUtilitiesServerNative` supplies bounded indexed reads and macOS watching to the native server executable. See `docs/indexed-server-reads.md` for pagination, publication, and source-revision guarantees. See `docs/sqlite-index-packaging.md` for runtime requirements. Xcode-based database integration is rejected.
- **Frameworks/Libraries**: Foundation, MarkdownSyntax, PathKit, Yams, swift-toml, JMESPath, DynamicJSON, JSONSchema.swift, swift-argument-parser, Noora (interactive CLI authoring), Rainbow, Hummingbird 2, Swift Logging
  - **parsing**: Any code that involves parsing text must use the `Parsing` library like the rest of the codebase.
- **Package Manager / Build Tool**: Swift Package Manager
- **Index compatibility recovery**: `index update --rebuild --metadata-encoding text` rebuilds authoritative files in a private disk copy, retaining declarations and independent pending-edit tables before publication. Recovery requires exclusive writer access. Existing text caches retain their encoding.
- **Executable Targets**: `md-utils`, `md-utils-server`
- **Index watching**: `index watch` uses a bounded `AsyncStream`, actor-isolated debounce state, `ContinuousClock`/`Duration`, and structured concurrency with Swift Service Lifecycle's `UnixSignalsSequence`. The isolated macOS FSEvents adapter is a justified C API exception: recursive hierarchy notifications and event-loss reporting avoid per-file open descriptors. Refresh reuses the staged update service and persisted storage mode. Other platforms explicitly require `index update`; see `docs/collection-index.md`.
- **Library Targets**: `MarkdownUtilitiesCore`, `MarkdownUtilities`, `MarkdownUtilitiesServer`, `MarkdownUtilitiesIndex`, `MarkdownUtilitiesIndexNative`, `MarkdownUtilitiesServerNative`
- **Test Framework**: Swift Testing, not XCTest
- **Build Command**: `swift build`
- **Test Command**: `swift test`; native Linux server route smoke test with `swift run MarkdownUtilitiesServerLinuxSmoke`
- **Formatter/Linter**: No dedicated formatter or linter is configured in-package
- **Documentation**: README.md, AGENTS.md, docs/*.md, generated CLI help, and bundled Agent Skill docs
- **Security**: Avoid unsafe optional force unwraps; treat filesystem and YAML/TOML/JSON parsing failures as user-visible errors
- **CI/Coverage**: Schema publication, Pages, WebAssembly, native Linux server, and native SQLite workflows are configured; local verification uses `Dockerfile.server-linux` and `Dockerfile.sqlite-index`; no coverage command is documented. Refresh scale measurements use `scripts/benchmark-index-refresh.py`; see `docs/index-refresh-benchmarks.md` for corpus characteristics and resource budgets.

## Requirements

- **Swift 6.2** or later
- **Package Manager**: Swift Package Manager (SPM)
- **Test Framework**: Swift Testing (NOT XCTest)

## Build and Test Commands

```bash
# Build
swift build

# Test
swift test

# Build and test Core on Linux
docker build --file Dockerfile.core-linux --tag md-utils-core-linux .

# Build and test the native server on Linux
docker build --file Dockerfile.server-linux --tag md-utils-server-linux .

# Run CLI
swift run md-utils <command>
```

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

## Path Conventions

- Use explicit trailing slashes for all paths that refer to directories, including examples, documentation, config snippets, and CLI help text. Bare `.`, `..`, and `~` are exceptions and do not need trailing slashes.

## OKF Support

- OKF tooling currently targets the Open Knowledge Format v0.1 draft.
- The OKF v0.1 draft spec is readable at https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md.
- Do not make OKF behavior stricter than the draft conformance rules unless the command clearly labels checks as advisory.
- Do not guess OKF `type` values. Apply a `type` only when the user provides the value explicitly.

## Documentation

Detailed guidance organized by topic:

- **[Architecture](docs/architecture.md)** - Project structure, core types, dependencies, features
- **[Portability Audit](docs/portability-audit.md)** - Target boundary, Linux validation, and WebAssembly blockers
- **[Testing Standards](docs/testing-standards.md)** - Swift Testing conventions and patterns
- **[Swift Coding Standards](docs/swift-coding-standards.md)** - Language-specific rules and safe practices
- **[CLI Patterns](docs/cli-patterns.md)** - Command structure and argument parsing
- **[Development Workflow](docs/development-workflow.md)** - Feature addition process and commit checklist
- **[Common Use Cases](docs/common-use-cases.md)** - CLI usage examples and recipes
- **[Release Procedures](docs/release-procedures.md)** - Versioning and release process

## Syncing SKILL.md

`Sources/md-utils/Resources/SKILL.md` is a copy of the canonical file at
`skill/markdown-utilities/skills/markdown-utilities/SKILL.md`. Both must be kept in sync.

After editing the canonical SKILL.md, run:
```bash
cp skill/markdown-utilities/skills/markdown-utilities/SKILL.md \
   Sources/md-utils/Resources/SKILL.md
```
Then commit both files. A Swift test enforces this and will fail if they drift.

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
