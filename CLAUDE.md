# CLAUDE.md

md-utils is a Swift package for parsing and manipulating Markdown files. It consists of three layers, each built on the previous:

1. **`MarkdownUtilities`** — A Swift library for parsing and manipulating Markdown content.
2. **`md-utils`** — A CLI tool built on `MarkdownUtilities`.
3. **`markdown-utilities`** — An Agent Skill for AI coding assistants, distributed from `skill/markdown-utilities/`, built on the `md-utils` CLI.

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

# Run CLI
swift run md-utils <command>
```

> [!Note] 
> If no `.build` directory exists, run `swift build` first to create. Do not use the `.build` directory from another worktree or branch. 

## Critical Rules

**STRICTLY FORBIDDEN: Force Unwrapping with `!`**

Force unwrapping optionals with `!` is absolutely prohibited. Use safe alternatives:
- Optional binding (`if let`, `guard let`)
- `try #require()` in tests
- Nil coalescing (`??`)
- Optional chaining (`?.`)

## Documentation

Detailed guidance organized by topic:

- **[Architecture](docs/architecture.md)** - Project structure, core types, dependencies, features
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

## Status

This project is on a `0.x.x` release and is not yet API stable. Breaking changes will be documented in release notes.
