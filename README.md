# md-utils
[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

A collection of utilities for working with Markdown files — from Swift library, to CLI tool, to Agent Skill. Each layer is built on top of the previous one.

1. **`MarkdownUtilities`** — A Swift library for parsing and manipulating Markdown content.
2. **`md-utils`** — A command-line tool, built on top of `MarkdownUtilities`, for performing operations on Markdown files.
3. **`markdown-utilities`** — An Agent Skill for AI coding assistants, built on top of the `md-utils` CLI.

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

### Planned

- Link validation (URL/reference link checking)
- Markdown flavor validation (CommonMark, GFM, Obsidian)
- Additional format conversions (HTML, RTF, XML)
- File metadata writing

## CLI Usage

Build and run with Swift Package Manager:

```bash
swift run md-utils <command> [options]
```

### Examples

```bash
# Generate a table of contents
swift run md-utils toc README.md

# Get a frontmatter value
swift run md-utils fm get --key title document.md

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
swift run md-utils links list --vault ~/notes note.md

# Check for broken wikilinks
swift run md-utils links check --vault ~/notes docs/

# Find backlinks to a file
swift run md-utils links backlinks --vault ~/notes --target "My Note"

# Read file metadata
swift run md-utils meta read document.md

# Extract lines 10-20
swift run md-utils lines --start 10 --end 20 document.md
```

Run `swift run md-utils --help` or `swift run md-utils <command> --help` for full usage details.

## Architecture

- **Swift 6.2** or later
- All testing uses the native Swift Testing framework

### Dependencies

- [MarkdownSyntax](https://github.com/hebertialmeida/MarkdownSyntax) — Swift Markdown parsing and syntax tree
- [swift-parsing](https://github.com/pointfreeco/swift-parsing) — Parser combinators
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing
- [PathKit](https://github.com/kylef/PathKit) — File path handling
- [Yams](https://github.com/jpsim/Yams) — YAML parsing and serialization
- [jmespath.swift](https://github.com/nicktmro/jmespath.swift) — JMESPath query language for JSON

## Platform Compatibility

**macOS** is the primary development and testing platform. All features are fully supported on macOS.

**Linux**: All dependencies are reported as buildable on Linux ([Swift Package Index](https://swiftpackageindex.com)). The code avoids Apple-only frameworks and the one Darwin-specific feature (extended attributes) is cleanly stubbed out on non-Darwin platforms via `#if canImport(Darwin)`. Some `FileMetadata` fields (e.g. creation date, access date, owner) may return `nil` on Linux due to differences in `swift-corelibs-foundation`. The project has **not been tested on Linux**.

**Windows**: Not currently tested or verified. Compatibility is unknown.

I don't have a Linux or Windows machine to test on, but I'm happy to accept PRs that improve compatibility on other platforms.

## Contributing

The project is still in its early stages and is not yet open for contributions. If you have a suggestion, please open an issue to discuss it.
