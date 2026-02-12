# md-utils

A collection of utilities for working with Markdown files.

1. **`MarkdownUtilities`** — A Swift library for parsing and manipulating Markdown content.
2. **`md-utils`** — A command-line tool, built on top of `MarkdownUtilities`, for performing various operations on Markdown files.
3. **`markdown-utilities`** — An Agent Skill for LLMs (planned, not yet implemented).

## Installation

### Using [Mint](https://github.com/yonaskolb/Mint)

```bash
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

### As a Swift Package Dependency

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/DandyLyons/md-utils.git", from: "0.1.0")
```

Then add `"MarkdownUtilities"` to your target's dependencies.

## Status

This project is currently in early development. Features and APIs may change.

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

## Installation

### Swift Package Manager

Add md-utils as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/DandyLyons/md-utils.git", branch: "main"),
]
```

Then add `MarkdownUtilities` to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "MarkdownUtilities", package: "md-utils"),
    ]
),
```

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

## Contributing

The project is still in its early stages and is not yet open for contributions. If you have a suggestion, please open an issue to discuss it.
