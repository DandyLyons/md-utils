# md-utils
[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

A collection of utilities for working with Markdown files — from portable Swift library, to native integrations, CLI tool, and Agent Skill. Each layer is built on top of the previous one.

1. **`MarkdownUtilitiesCore`** — Portable Markdown parsing and transformations for Apple platforms and Linux.
2. **`MarkdownUtilities`** — Core plus native filesystem, path, and metadata integrations.
3. **`md-utils`** — A command-line tool built on `MarkdownUtilities`.
4. **`markdown-utilities`** — An Agent Skill for AI coding assistants built on the `md-utils` CLI.

[`treedocs`](https://github.com/DandyLyons/treedocs) is a sister project of `md-utils`. Future integrations are planned between the two projects.

## Agent Skill Installation

The `markdown-utilities` Agent Skill teaches AI coding assistants how to use `md-utils` for Markdown operations. It provides commands, examples, and reference documentation that are loaded on demand.

> **Prerequisite:** Install the `md-utils` CLI first (see [CLI Installation](#cli-installation) below).

### Install from skills.sh

```bash
npx skills add https://github.com/DandyLyons/md-utils --skill markdown-utilities
```

Visit the [skills.sh page](https://skills.sh/dandylyons/md-utils/markdown-utilities) for more details.

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

Add `MarkdownUtilitiesCore` when the target only needs content operations:

```swift
.target(
    name: "PortableTarget",
    dependencies: [
        .product(name: "MarkdownUtilitiesCore", package: "md-utils"),
    ]
)
```

Add both products when the target combines portable content operations with filesystem, path, CSV path-metadata, or file-metadata APIs:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "MarkdownUtilitiesCore", package: "md-utils"),
        .product(name: "MarkdownUtilities", package: "md-utils"),
    ]
),
```

Import each module explicitly where its APIs are used:

```swift
import MarkdownUtilitiesCore
import MarkdownUtilities
```

### Linux Validation

Core is tested with Swift 6.2 on Linux in Docker:

```bash
docker build --file Dockerfile.core-linux --tag md-utils-core-linux .
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

Project-level md-utils settings live in `.md-utils/md-utils.json`. The rules command group creates and uses this folder to validate Markdown files. JSON Schema validation is one supported rule check, alongside document checks such as required headings and body length limits.

The md-utils CLI version and md-utils config schema version are independent. `md-utils --version` reports the installed CLI version. The `configVersion` field in `.md-utils/md-utils.json` selects the config schema version used for parsing, validation, and behavior. Existing unversioned configs are treated as legacy config schema `0.1.0`.

Check the config schema versions supported by the installed CLI with:

```bash
md-utils config info
md-utils config info --format json
```

Compatibility:

| CLI version | Supported config schema versions | Default generated config schema version |
| --- | --- | --- |
| 0.1.0-alpha | 0.1.0, 0.2.0 | 0.2.0 |

The config schema is published at `https://dandylyons.github.io/md-utils/schemas/0.2.0/md-utils.schema.json` for editor integration and IDE IntelliSense. The moving `https://dandylyons.github.io/md-utils/schemas/latest/md-utils.schema.json` alias points to the latest published schema, and `https://dandylyons.github.io/md-utils/md-utils.schema.json` is maintained as a root compatibility alias. Runtime config validation does not fetch these URLs; the CLI validates configs against bundled schemas selected by `configVersion`.

Treat the directory containing `.md-utils/` as the md-utils project root. Commands that use project configuration read `.md-utils/md-utils.json` relative to the current working directory; md-utils does not search parent directories for project configuration. Run rules/config commands from the directory that contains `.md-utils/`:

```bash
cd /path/to/project/
md-utils rules validate
```

Paths in `rules[].match.paths` and the default `schemaDirectory` are interpreted relative to that same working directory. If you run md-utils from a subdirectory, it will look for `.md-utils/md-utils.json` in that subdirectory. Existing `0.1.0` configs using `schemaRules` still load as legacy configs.

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
  "$schema": "https://dandylyons.github.io/md-utils/schemas/0.2.0/md-utils.schema.json",
  "configVersion": "0.2.0",
  "schemaDirectory": ".md-utils/schemas/",
  "rules": [
    {
      "name": "books",
      "match": {
        "paths": ["Books/**/*.md"],
        "file": {
          "extensionIn": ["md", "markdown"]
        },
        "frontmatter": {
          "tags": { "includes": "Book" },
          "publish": { "equals": true },
          "date": { "between": { "from": "2000-01-01", "to": "2015-04-01" } }
        },
        "frontmatterQuery": {
          "jmespath": "author.name"
        },
        "document": {
          "hasHeading": "Summary",
          "wordCount": { "max": 2000 }
        }
      },
      "checks": [
        {
          "type": "frontmatterSchema",
          "schema": "book.schema.json",
          "frontmatterRequired": true
        },
        {
          "type": "requiredHeading",
          "heading": "Footnotes"
        },
        {
          "type": "maxBodyLines",
          "max": 250
        },
        {
          "type": "maxBodyWords",
          "max": 2000
        }
      ]
    }
  ]
}
```

Config fields:

- `$schema`: Optional editor hint for autocomplete, validation, and IDE IntelliSense. Runtime behavior is not driven by this URL.
- `configVersion`: md-utils config schema version. This is independent from the md-utils CLI version.
- `schemaDirectory`: Directory for JSON Schema files. Defaults to `.md-utils/schemas/`.
- `rules`: Rules that map Markdown files to one or more checks.
- `rules[].name`: Unique rule name for `md-utils rules validate <rule-name>`.
- `rules[].match.paths`: Glob patterns matched against project-relative Markdown paths.
- `rules[].match.excludePaths`: Glob patterns excluded after paths match.
- `rules[].match.file`: File metadata predicates. Supported operators are `pathRegex`, `filenameEquals`, `extensionIn`, `modifiedAfter`, and `modifiedBefore`.
- `rules[].match.frontmatter`: Frontmatter field predicates. Supported operators are `equals`, `doesntEqual`, `includes`, `notIncludes`, `hasKey`, `doesntHaveKey`, `regex`, `startsWith`, `endsWith`, `contains`, `empty`, `emptyString`, `emptyArray`, `emptyObject`, `notEmpty`, `in`, `notIn`, numeric comparisons, date/time comparisons, inclusive `between`, and `typeIs`.
- `rules[].match.frontmatterQuery`: Whole-frontmatter predicates. `jmespath` is supported in `0.2.0`.
- `rules[].match.document`: Document predicates. Supported operators are `hasHeading`, `headingRegex`, `hasHeadingAtLevel`, `hasSection`, `bodyContains`, `bodyRegex`, `hasWikilink`, `lineCount`, and `wordCount`.
- `rules[].checks`: Checks to run after a file matches. Supported checks are `frontmatterSchema`, `requiredHeading`, `maxBodyLines`, and `maxBodyWords`.
- `rules[].checks[].schema`: For `frontmatterSchema`, schema file resolved relative to `schemaDirectory`.
- `rules[].checks[].frontmatterRequired`: For `frontmatterSchema`, if `true`, matched files without frontmatter fail; if `false`, frontmatter schema validation is skipped.

Predicate semantics:

- Predicate namespaces are all-of. Multiple operators on one frontmatter key are implicit AND.
- Missing keys are not value inequality. A missing key does not match `doesntEqual`, `notIncludes`, or `notIn`; only `doesntHaveKey` intentionally matches absence.
- `contains` is string containment. `includes` is array membership.
- Date/time predicates support `YYYY-MM-DD` and RFC 3339 timestamps with `Z` or numeric offsets. Date-only operands compare at date precision. Date-time operands compare at date-time precision. A value with more precision can match a less precise rule; a value with less precision does not match a more precise rule.
- Regex predicates use Swift `NSRegularExpression` syntax.
- Logical grouping predicates `all`, `any`, and `not` are deferred to config schema `0.3.0`. `hasBrokenWikilink` is also deferred.

Rules commands:

```bash
md-utils rules init books --path "Books/**/*.md" --tag Book
md-utils rules add published --path "Books/**/*.md" --no-frontmatter-required
md-utils rules list
md-utils rules describe books
md-utils rules describe books --format markdown
md-utils rules describe books --format json
md-utils rules validate
md-utils rules validate books
md-utils rules remove books
md-utils rules remove books --delete-schema
```

`rules init` bootstraps `.md-utils/` and adds an initial frontmatter schema rule. `rules add` adds another frontmatter schema rule to existing config. `rules describe` explains which files a rule affects and summarizes every field in the referenced JSON Schema when the rule has one; `--format markdown` emits a docs-friendly summary and `--format json` emits the rule configuration with the embedded schema definition. `rules remove` removes a rule; `--delete-schema` also deletes that rule's schema file when it is not shared by another rule.

If a file matches multiple rules, all matching checks apply. Files matching no rules are ignored. Invalid YAML frontmatter is reported as an error for matched rules because frontmatter predicates and schema checks cannot proceed.

## GitHub Pages

The static project site lives in `site/` and deploys to `https://dandylyons.github.io/md-utils/` through `.github/workflows/pages.yml`. GitHub Pages should be configured to use GitHub Actions as its deployment source.

Schema publishing layout:

```text
site/
  index.html
  styles.css
  schemas/
    0.1.0/
      md-utils.schema.json
      md-utils-0.1.0.schema.json
    0.2.0/
      md-utils.schema.json
      md-utils-0.2.0.schema.json
```

The bundled CLI schema in `Sources/md-utils/Resources/0.2.0_md-utils.schema.json` remains canonical for CLI behavior for config schema `0.2.0`. Public schema copies must match it exactly, so run `python3 scripts/validate-schema-publication.py` before publishing schema changes.

When the Pages workflow prepares its artifact, it copies `site/schemas/$CURRENT_MD_UTILS_JSONSCHEMA_VERSION/md-utils.schema.json` to both `md-utils.schema.json` at the site root and `schemas/latest/md-utils.schema.json`. Versioned schema URLs are immutable after release. For future schema releases, add a new versioned folder under `site/schemas/`, update `CURRENT_MD_UTILS_JSONSCHEMA_VERSION` in `.github/workflows/pages.yml`, and keep the canonical bundled schema synchronized with the new published copy. Do not edit already-published versioned schema files; publish a new version instead.

## Architecture

- **Swift 6.2** or later
- **MarkdownUtilitiesCore** for portable content operations on Apple platforms, Linux, and WebAssembly
- **MarkdownUtilities** for native filesystem and metadata integrations
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
**macOS** is the primary development and testing platform. Core, native integrations, and the CLI are covered by the full Swift test suite.

**Linux**: `MarkdownUtilitiesCore` is supported and verified with Swift 6.2 using `Dockerfile.core-linux`. The container builds Core and runs an isolated parsing, AST, frontmatter, and rendering smoke executable. The complete native `MarkdownUtilities` and `md-utils` CLI layers are not covered by this Core guarantee.

**WebAssembly**: `MarkdownUtilitiesCore` is supported with the official Swift 6.3.1 WASI SDK. Run `scripts/build-wasm.sh` to compile Core and execute the root-package smoke target under WasmKit. See [WebAssembly Support](docs/webassembly.md) for SDK installation, dependency compatibility patches, artifact location, and current scope.

**Windows**: Not currently tested or verified. Compatibility is unknown.

See the [portability audit](docs/portability-audit.md) for the source boundary and dependency assessment.

## Contributing

The project is still in its early stages and is not yet open for contributions. If you have a suggestion, please open an issue to discuss it.
