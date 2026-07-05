# md-utils
[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

A collection of utilities for working with Markdown files — from Swift library, to CLI tool, to Agent Skill. Each layer is built on top of the previous one.

1. **`MarkdownUtilities`** — A Swift library for parsing and manipulating Markdown content.
2. **`md-utils`** — A command-line tool, built on top of `MarkdownUtilities`, for performing operations on Markdown files.
3. **`markdown-utilities`** — An Agent Skill for AI coding assistants, built on top of the `md-utils` CLI.

[`treedocs`](https://github.com/DandyLyons/treedocs) is a sister project of `md-utils`. Future integrations are planned between the two projects.

## Agent Skill Installation

The `markdown-utilities` Agent Skill teaches AI coding assistants how to use `md-utils` for Markdown operations. It provides commands, examples, and reference documentation that are loaded on demand.

> **Prerequisite:** Install the `md-utils` CLI first (see [CLI Installation](#cli-installation) below).

### Option A: skills.sh (Recommended)

```bash
npx skills add https://github.com/DandyLyons/md-utils --skill markdown-utilities
```

Visit the [skills.sh page](https://skills.sh/dandylyons/md-utils/markdown-utilities) for more details.

### Option B: Claude Code Plugin

**Personal usage** — install the skill just for yourself:

```
/plugin marketplace add DandyLyons/md-utils
/plugin install markdown-utilities@md-utils
```

**Project-wide** — share the skill with your whole team automatically:

Add to `.claude/settings.json` in your project:

```json
{
  "enabledPlugins": {
    "markdown-utilities@md-utils": true
  },
  "extraKnownMarketplaces": {
    "md-utils": {
      "source": {
        "source": "github",
        "repo": "DandyLyons/md-utils"
      }
    }
  }
}
```

Team members will be prompted to install the skill when they open the project in Claude Code.

---

## CLI Installation

### Using [Mint](https://github.com/yonaskolb/Mint)

```bash
# Install mint (if you haven't done so already)
brew install mint

# Install
mint install DandyLyons/md-utils

# Run without installing
mint run DandyLyons/md-utils <command>
```

### From Source

```bash
git clone https://github.com/DandyLyons/md-utils.git
cd md-utils
swift build -c release
# Binary will be at .build/release/md-utils
```

---

## Library Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/DandyLyons/md-utils.git", from: "0.1.0")
```

Then add `"MarkdownUtilities"` to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "MarkdownUtilities", package: "md-utils"),
    ]
),
```

---

## Status

This project is on a `0.x.x` release and is **not yet API stable**. The API and CLI may change between releases. Breaking changes will be documented in release notes.

## Features

### Implemented

- **Table of Contents** — Generate TOC with multiple output formats (Markdown, JSON, plain text, HTML)
- **Heading Manipulation** — Promote/demote headings while maintaining nested structure
- **Section Operations** — Extract sections by name or index; reorder sections (move up/down/to position)
- **Content Selection** — Extract body without frontmatter, select by line range, extract by section
- **YAML Front Matter** — Full CRUD operations with 12+ subcommands including get, set, remove, rename, search (JMESPath), sort keys, array manipulation, and multi-format dump (JSON, YAML, raw, PropertyList)
- **Format Conversion** — Convert Markdown to plain text or CSV
- **File Metadata** — Read file metadata including standard and extended attributes (xattr)
- **Wikilink Parsing & Resolution** — Parse Obsidian-flavored wikilinks, resolve against a vault directory, detect broken/ambiguous links, find backlinks
- **OKF v0.1 Draft Tooling** — Initialize, validate, report on, doctor, and batch-update Open Knowledge Format bundles

### Planned

- Link validation (URL/reference link checking)
- Markdown flavor validation (CommonMark, GFM, Obsidian)
- Additional format conversions (HTML, RTF, XML)
- File metadata writing
- Integration with the sister project [`treedocs`](https://github.com/DandyLyons/treedocs)

## CLI Usage

Build and run with Swift Package Manager:

```bash
swift run md-utils <command> [options]
```

### Examples

```bash
# Generate a table of contents
swift run md-utils toc README.md

# Get a frontmatter value (JSON by default)
swift run md-utils fm get --key title document.md
# => [{"path":"...","value":"My Title"}]
swift run md-utils fm get --key title posts/ | jq '.[] | select(has("value")) | .value'

# Set a frontmatter value
swift run md-utils fm set --key tags --value "[swift, cli]" document.md

# Dump frontmatter as JSON
swift run md-utils fm dump document.md

# Search frontmatter with JMESPath
swift run md-utils fm search --query "tags[?contains(@, 'swift')]" docs/

# Convert Markdown to plain text
swift run md-utils convert to-text document.md

# Extract a section by name
swift run md-utils extract --name "Installation" README.md

# Promote all headings by one level
swift run md-utils headings promote document.md

# List wikilinks with resolution status
swift run md-utils links list --vault ~/notes/ note.md

# Check for broken wikilinks
swift run md-utils links check --vault ~/notes/ docs/

# Find backlinks to a file
swift run md-utils links backlinks --vault ~/notes/ --target "My Note"

# Validate an OKF v0.1 draft bundle
swift run md-utils okf validate ./knowledge/

# Initialize an OKF bundle and install OKF schema config
swift run md-utils okf init ./knowledge/

# Initialize with optional log.md
swift run md-utils okf init ./knowledge/ --with-log

# Report bundle inventory and advisory diagnostics
swift run md-utils okf report ./knowledge/

# Run hard validation plus advisory health checks
swift run md-utils okf doctor ./knowledge/

# Set an explicit OKF type on matching concept files under the current directory
swift run md-utils okf type set --type=Book --array-key=tags --array-contains=Books

# Set an explicit OKF type under a specific directory
swift run md-utils okf type set --type=BigQueryTable --dir=./knowledge/tables/

# Read file metadata
swift run md-utils meta read document.md

# Extract lines 10-20
swift run md-utils lines --start 10 --end 20 document.md
```

Run `swift run md-utils --help` or `swift run md-utils <command> --help` for full usage details.

### ANSI Color

Human-facing CLI output may use ANSI color to distinguish status, errors, warnings, paths, and metadata from Markdown content. Machine-readable output such as JSON, YAML, PropertyList, raw path lists, and extracted Markdown content remains unstyled. Color handling is provided by Rainbow, which automatically emits plain text when output is redirected; use `NO_COLOR=1` to disable color or `FORCE_COLOR=1` to force color when supported by Rainbow.

## Open Knowledge Format

`md-utils okf` currently targets the Open Knowledge Format (OKF) v0.1 draft. The draft spec is readable at https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md.

OKF v0.1 draft bundles are directories of Markdown files with YAML frontmatter. `md-utils` validates the hard conformance rules from the draft without rejecting intentionally permitted content such as unknown `type` values, unknown frontmatter keys, broken links, or missing optional fields.

OKF commands:

```bash
md-utils okf validate ./knowledge/
md-utils okf init ./knowledge/
md-utils okf init ./knowledge/ --with-log
md-utils okf report ./knowledge/
md-utils okf report ./knowledge/ --format json
md-utils okf doctor ./knowledge/
md-utils okf type set --type=Book
md-utils okf type set --type=Book --array-key=tags --array-contains=Books
md-utils okf type set --type=BigQueryTable --dir=./knowledge/tables/
```

`okf validate` is the conformance gate for hard OKF v0.1 draft rules. `okf doctor` runs validation plus advisory diagnostics for agent usefulness and exits non-zero only for hard conformance errors. `okf report` is inventory and analytics; it does not fail because issues are present.

`okf init` creates a minimal bundle scaffold and installs `.md-utils/` schema configuration. It preserves existing files. Because `log.md` is optional in OKF, it is created only when `--with-log` is passed.

`okf type set` never guesses concept types. It writes only the explicit `--type` value supplied by the user. If `--dir` is omitted, it scans the current directory recursively. Use `--array-key` and `--array-contains` together to update only files whose YAML frontmatter array includes a specific string, such as files whose `tags` array contains `Books`.

The package also bundles `OKF-concept.schema.json` for OKF v0.1 draft concept frontmatter. The schema requires a non-empty string `type` and allows additional frontmatter keys, matching the draft's permissive consumption model. `okf init` installs this schema with an `okf-concepts` rule that excludes reserved `index.md` and `log.md` files.

## Project Configuration

Project-level md-utils settings live in `.md-utils/md-utils.json`. The schema command group creates and uses this folder to validate Markdown YAML frontmatter against JSON Schema files. Schemas only apply to frontmatter, not Markdown body content.

Treat the directory containing `.md-utils/` as the md-utils project root. Commands that use project configuration read `.md-utils/md-utils.json` relative to the current working directory; md-utils does not search parent directories for project configuration. Run schema/config commands from the directory that contains `.md-utils/`:

```bash
cd /path/to/project/
md-utils schema validate
```

Paths in `schemaRules[].match.paths` and the default `schemaDirectory` are interpreted relative to that same working directory. If you run md-utils from a subdirectory, it will look for `.md-utils/md-utils.json` in that subdirectory.

Default layout:

```text
.md-utils/
  md-utils.json
  md-utils.schema.json
  schemas/
    book.schema.json
```

Example config:

```json
{
  "$schema": "md-utils.schema.json",
  "schemaDirectory": ".md-utils/schemas/",
  "schemaRules": [
    {
      "name": "books",
      "schema": "book.schema.json",
      "frontmatterRequired": true,
      "match": {
        "paths": ["Books/**/*.md"],
        "frontmatter": {
          "tags": { "includes": "Book" }
        }
      }
    }
  ]
}
```

Config fields:

- `$schema`: Optional editor hint for autocomplete and validation.
- `schemaDirectory`: Directory for JSON Schema files. Defaults to `.md-utils/schemas/`.
- `schemaRules`: Rules that map schemas to Markdown files.
- `schemaRules[].name`: Unique rule name for `md-utils schema validate <rule-name>`.
- `schemaRules[].schema`: Schema file, resolved relative to `schemaDirectory`.
- `schemaRules[].frontmatterRequired`: If `true`, matched files without frontmatter fail; if `false`, they are skipped.
- `schemaRules[].match.paths`: Glob patterns matched against project-relative Markdown paths.
- `schemaRules[].match.frontmatter`: Frontmatter matchers. Initially supports `{ "includes": value }` for array values.

Schema commands:

```bash
md-utils schema init books --path "Books/**/*.md" --tag Book
md-utils schema add published --path "Books/**/*.md" --no-frontmatter-required
md-utils schema list
md-utils schema describe books
md-utils schema describe books --format markdown
md-utils schema describe books --format json
md-utils schema validate
md-utils schema validate books
md-utils schema remove books
md-utils schema remove books --delete-schema
```

`schema init` bootstraps `.md-utils/` and adds an initial rule. `schema add` adds another rule to existing config. `schema describe` explains which files a rule affects and summarizes every field in the referenced JSON Schema; `--format markdown` emits a docs-friendly summary and `--format json` emits the rule configuration with the embedded schema definition. `schema remove` removes a rule; `--delete-schema` also deletes that rule's schema file when it is not shared by another rule.

If a file matches multiple rules, all matching schemas apply. Files matching no rules are ignored. Invalid YAML frontmatter is always reported as an error because schema validation cannot proceed.

## Architecture

- **Swift 6.2** or later
- All testing uses the native Swift Testing framework

### Dependencies

- [MarkdownSyntax](https://github.com/hebertialmeida/MarkdownSyntax) — Swift Markdown parsing and syntax tree
- [swift-parsing](https://github.com/pointfreeco/swift-parsing) — Parser combinators
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing
- [PathKit](https://github.com/kylef/PathKit) — File path handling
- [JSONSchema.swift](https://github.com/kylef/JSONSchema.swift) — JSON Schema validation
- [Yams](https://github.com/jpsim/Yams) — YAML parsing and serialization
- [jmespath.swift](https://github.com/nicktmro/jmespath.swift) — JMESPath query language for JSON

## Platform Compatibility

**macOS** is the primary development and testing platform. All features are fully supported on macOS.

**Linux**: All dependencies are reported as buildable on Linux ([Swift Package Index](https://swiftpackageindex.com)). The code avoids Apple-only frameworks and the one Darwin-specific feature (extended attributes) is cleanly stubbed out on non-Darwin platforms via `#if canImport(Darwin)`. Some `FileMetadata` fields (e.g. creation date, access date, owner) may return `nil` on Linux due to differences in `swift-corelibs-foundation`. The project has **not been tested on Linux**.

**Windows**: Not currently tested or verified. Compatibility is unknown.

I don't have a Linux or Windows machine to test on, but I'm happy to accept PRs that improve compatibility on other platforms.

## Contributing

The project is still in its early stages and is not yet open for contributions. If you have a suggestion, please open an issue to discuss it.
