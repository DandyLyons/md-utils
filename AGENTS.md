# AGENTS.md

md-utils is a Swift package for parsing and manipulating Markdown files. It consists of four layers, each built on the previous:

1. **`MarkdownUtilitiesCore`** — Portable Markdown parsing and transformations for Apple platforms and Linux.
2. **`MarkdownUtilities`** — Core plus native filesystem, path, and metadata integrations.
3. **`md-utils`** — A CLI tool built on `MarkdownUtilities`.
4. **`markdown-utilities`** — An Agent Skill for AI coding assistants, distributed from `skill/markdown-utilities/`, built on the `md-utils` CLI.

[`treedocs`](https://github.com/DandyLyons/treedocs) is a sister project of `md-utils`. Future integrations are planned between the two projects.

## Project Brief

- **Language**: Swift 6.2+
- **Frameworks/Libraries**: Foundation, MarkdownSyntax, PathKit, Yams, swift-toml, JMESPath, DynamicJSON, JSONSchema.swift, swift-argument-parser, Rainbow, Hummingbird 2, Swift Logging
  - **parsing**: Any code that involves parsing text must use the `Parsing` library like the rest of the codebase.
- **Package Manager / Build Tool**: Swift Package Manager
- **Executable Targets**: `md-utils`, `md-utils-server`
- **Library Targets**: `MarkdownUtilitiesCore`, `MarkdownUtilities`
- **Test Framework**: Swift Testing, not XCTest
- **Build Command**: `swift build`
- **Test Command**: `swift test`; native Linux server route smoke test with `swift run MarkdownUtilitiesServerLinuxSmoke`
- **Formatter/Linter**: No dedicated formatter or linter is configured in-package
- **Documentation**: README.md, AGENTS.md, docs/*.md, generated CLI help, and bundled Agent Skill docs
- **Security**: Avoid unsafe optional force unwraps; treat filesystem and YAML/TOML/JSON parsing failures as user-visible errors
- **CI/Coverage**: Schema publication, Pages, WebAssembly, and native Linux server workflows are configured; local Linux server verification uses `Dockerfile.server-linux`; no coverage command is documented

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
