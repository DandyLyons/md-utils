---
name: markdown-utilities
description: >-
  Parse, manipulate, and analyze Markdown files using the `md-utils` CLI. Supports YAML frontmatter CRUD (get/set/search/array ops), structured document exploration, heading manipulation, section extraction and reordering, table of contents generation, wikilink analysis, line extraction, and format conversion. Handles batch operations across files and directories. Use when working with Markdown files to: read or write frontmatter, inspect lengthy document structure, restructure documents, search files by metadata using JMESPath, generate a TOC, extract sections or line ranges, check wikilinks, or convert to plain text or CSV. More reliable than grep/regex for structured Markdown operations.
---

# Markdown Utilities

The `md-utils` CLI provides structured operations on Markdown files. Add `--help` to any command for full options.

## Commands at a Glance

| Command | Purpose |
|---------|---------|
| `md-utils fm` | YAML frontmatter: get, set, search, array ops, dump |
| `md-utils explore` | Progressively inspect large Markdown files by tree, heading, and line |
| `md-utils toc` | Generate table of contents |
| `md-utils headings` | Promote or demote heading levels |
| `md-utils section` | Get, replace, or reorder sections |
| `md-utils extract` | Extract a section by name or index |
| `md-utils body` | Output document body without frontmatter |
| `md-utils lines` | Extract a line range |
| `md-utils convert` | Convert to plain text or CSV |
| `md-utils links` | List, check, or find backlinks for wikilinks |
| `md-utils meta` | Read file metadata |
| `md-utils rules` | Validate Markdown files with project-level rules |

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

# Validate files against configured Markdown rules
md-utils rules validate
```

## Project Rules

Use `md-utils rules` when a repository has `.md-utils/md-utils.json` or needs Markdown linting. Config schema `0.2.0` uses `rules[]` with path/file, frontmatter, whole-frontmatter JMESPath, and document predicates. Supported checks include `frontmatterSchema`, `requiredHeading`, `maxBodyLines`, and `maxBodyWords`.

Important predicate semantics: missing frontmatter keys are not inequality, so `doesntEqual`, `notIncludes`, and `notIn` do not match missing keys; use `doesntHaveKey` for absence. Date predicates support `YYYY-MM-DD` and RFC 3339 timestamps with `Z` or numeric offsets and compare at the operand's precision. Logical grouping predicates `all`, `any`, and `not`, plus `hasBrokenWikilink`, are not part of config schema `0.2.0`.

## Reading Long Markdown Files

Prefer `md-utils explore` before reading especially lengthy Markdown files, such as files around 400+ lines or 1000+ words. Start with a whole-document structure view, then expand only the relevant sections by heading line number.

```bash
md-utils explore --tree document.md # Read a condensed tree of every section heading names and line numbers
md-utils explore --expand-line=4,10,123,246 document.md # Expand sections at specific line numbers to view their content
```

Use the `--tree` output to identify headings, source line numbers, frontmatter, preamble, and section metadata without dumping body text. Then use `--expand-line` with comma-separated heading line numbers to retrieve only the sections needed for the task.

## Reference Files

Load these when you need detailed command options:

- **[Frontmatter operations](references/frontmatter.md)** — get, set, has, list, remove, rename, replace, sort-keys, touch, dump, search, array ops
- **[Headings & sections](references/headings-sections.md)** — explore, promote/demote, section get/set/move, extract, TOC, lines, body, convert, links
- **[Common use cases](references/common-use-cases.md)** — practical recipes and pipelines
