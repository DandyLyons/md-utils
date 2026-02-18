# Headings, Sections & Document Structure Reference

## Table of Contents

Generate a TOC from headings in a Markdown document:

```bash
md-utils toc document.md
md-utils toc document.md --min-level 2 --max-level 4
md-utils toc document.md --format md-bullet-links > toc.md
```

Use `md-utils toc --help` for all available output formats (plain text, markdown bullet links, HTML, tree, JSON).

## Heading Manipulation

Headings are 1-based indexed. `promote` decreases level (H2→H1), `demote` increases level (H2→H3). Child headings are adjusted to maintain relative structure unless `--target-only` is used.

```bash
# Promote heading at index 3 (modifies file in place)
md-utils headings promote --index 3 document.md --in-place

# Demote heading at index 2 (prints to stdout)
md-utils headings demote --index 2 document.md

# Promote only the specified heading, not its children
md-utils headings promote --index 2 document.md --target-only --in-place
```

## Section Operations

A "section" is a heading plus all its nested content (including sub-headings).

### Get a section
```bash
md-utils section get --name "Introduction" document.md
md-utils section get --index 2 document.md
```

### Replace a section's body
```bash
md-utils section set --name "Introduction" --content "New content here." document.md --in-place
```

### Reorder sections (among siblings)
```bash
md-utils section move-up --name "Background" document.md --in-place
md-utils section move-down --index 3 document.md --in-place

# Move to a specific position (1-based)
md-utils section move-to --name "Summary" --position 1 document.md --in-place
```

## Extract

Extract a section by name or index, optionally saving to a file:

```bash
md-utils extract --name "Introduction" document.md
md-utils extract --index 2 document.md
md-utils extract --name "API Reference" document.md --output api-ref.md
```

## Lines

Extract a range of lines from a file:

```bash
md-utils lines document.md --start 10 --end 20
md-utils lines document.md -s 1 -e 50 --numbered
```

## Body

Strip frontmatter and return the Markdown body only:

```bash
md-utils body document.md
md-utils body posts/        # batch
```

## Convert

```bash
# Markdown to plain text
md-utils convert to-text document.md

# Markdown with frontmatter to CSV (batch)
md-utils convert to-csv posts/
```

## Wikilinks

```bash
# List all wikilinks with resolution status
md-utils links list document.md
md-utils links ls posts/ --root ~/vault --json

# Check for broken or ambiguous links
md-utils links check posts/ --root ~/vault

# Find backlinks to a target file
md-utils links backlinks target.md --root ~/vault
```

> Note: For Obsidian vault-specific operations, the Obsidian CLI may provide more reliable results. `md-utils links` is designed for general Markdown workflows.

## File Metadata

Read OS-level file metadata (creation date, modification date, etc.):

```bash
md-utils meta read document.md
```
