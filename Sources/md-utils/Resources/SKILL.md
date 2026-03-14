---
name: markdown-utilities
description: Parse, manipulate, and analyze Markdown files using the `md-utils` CLI. Supports YAML frontmatter CRUD (get/set/search/array ops), heading manipulation, section extraction and reordering, table of contents generation, wikilink analysis, line extraction, and format conversion. Handles batch operations across files and directories. Use when working with Markdown files to: read or write frontmatter, restructure documents, search files by metadata using JMESPath, generate a TOC, extract sections or line ranges, check wikilinks, or convert to plain text or CSV. More reliable than grep/regex for structured Markdown operations.
---

# Markdown Utilities

The `md-utils` CLI provides structured operations on Markdown files. Add `--help` to any command for full options.

## Commands at a Glance

| Command | Purpose |
|---------|---------|
| `md-utils fm` | YAML frontmatter: get, set, search, array ops, dump |
| `md-utils toc` | Generate table of contents |
| `md-utils headings` | Promote or demote heading levels |
| `md-utils section` | Get, replace, or reorder sections |
| `md-utils extract` | Extract a section by name or index |
| `md-utils body` | Output document body without frontmatter |
| `md-utils lines` | Extract a line range |
| `md-utils convert` | Convert to plain text or CSV |
| `md-utils links` | List, check, or find backlinks for wikilinks |
| `md-utils meta` | Read file metadata |

## Batch Operations

All commands accept multiple files and directories. Directories are processed recursively by default (`--no-recursive` to disable).

```bash
md-utils fm set --key author --value "Jane Doe" posts/
md-utils toc docs/*.md
```

## Quick Examples

```bash
# Get a frontmatter value
md-utils fm get --key title post.md

# Find files with a specific tag
md-utils fm array contains --key tags --value swift posts/

# Generate a table of contents
md-utils toc document.md

# Extract a named section
md-utils extract --name "Introduction" document.md
```

## Reference Files

Load these when you need detailed command options:

- **[Frontmatter operations](references/frontmatter.md)** — get, set, has, list, remove, rename, replace, sort-keys, touch, dump, search, array ops
- **[Headings & sections](references/headings-sections.md)** — promote/demote, section get/set/move, extract, TOC, lines, body, convert, links
- **[Common use cases](references/common-use-cases.md)** — practical recipes and pipelines
