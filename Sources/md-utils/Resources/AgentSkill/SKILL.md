---
name: markdown-utilities
description: >-
  Parse, edit, and analyze Markdown and mapped text files with md-utils. Use for YAML/TOML frontmatter, headings and sections, wikilinks and relationship queries, rules/types/schema authoring and validation, templates, batch operations, indexing, and reviewed document mutations. Standards are upcoming.
---

# Markdown Utilities

Use the `md-utils` CLI for structured document operations. Inspect the installed
command's `--help` before using unfamiliar options; versions and capabilities
are explicit. Read only the references relevant to the task.

## Choose a workflow

| Task | Reference |
| --- | --- |
| Get oriented in a folder: frontmatter patterns, distributions, rules/types and investigation hints | [Survey](references/survey.md) |
| Read/write YAML or TOML metadata, mapped source files, arrays, search | [Frontmatter](references/frontmatter.md) |
| Explore a long document, TOC, headings, sections, lines, body, text/CSV conversion | [Headings and sections](references/headings-sections.md) |
| List/check/backlink or convert wikilinks | [Links](references/links.md) |
| Query named assertions and ordinary links, selection and snapshot evidence | [Relationships](references/relationships.md) |
| Author rules, inspect applicability, validate, review fixes, migrate config | [Rules](references/rules.md) |
| Author types, constraints and relationships; assess hints; create instances | [Types](references/types.md) |
| Author inline/shared frontmatter schemas and semantic strings | [Schemas](references/schemas.md) |
| Learn about upcoming standards | [Standards](references/standards.md) |
| Refresh/query/search/watch a collection index | [Indexing](references/indexing.md) |
| Stage/apply document edits, recover partial writes, managed copy/move | [Mutations](references/mutations.md) |
| Render Knap templates | [Templates](references/templates.md) |
| Select files/directories and understand batch outcomes | [Batch operations](references/batch.md) |
| Practical metadata/document recipes | [Common use cases](references/common-use-cases.md) |
| Config inspection, formatting, metadata, slugs, experimental OKF | [Other commands](references/other-commands.md) |
| Export/install this complete skill | [Installation](references/installation.md) |

## Working principles

Schemas constrain frontmatter values; types combine frontmatter, body, context,
and optional relationships; rules select documents and enforce contracts.
Hints and names do not prove conformance. Inspect existing versions and resource
references before editing; do not silently migrate or weaken contracts.

Validation and queries do not authorize document repairs. Check each command's
persistence behavior: some preview or print by default, while frontmatter edits
write directly. Review combined changes and retain revision/review tokens where
required. Creation may save nonconforming starting documents; assess separately
when conformance is required. Partial batch completion is not a transaction.

Use current source validation after changing definitions. Snapshot-only results
describe a published index generation and cannot certify newly edited files.
Keep missing or unavailable evidence distinct from failure or success.

## Starting examples

```bash
# Inspect structure before expanding a long document.
md-utils explore --tree document.md
md-utils explore --expand-line=4,10 document.md

# Read metadata and validate current rule-selected documents.
md-utils fm get --key title document.md
md-utils rules validate --no-index

# Inspect outgoing relationship evidence with explicit collection context.
md-utils rel out Note.md --root ./vault/ --detail explain
```

Use the full skill folder, including `references/`. `md-utils agents skill` prints
this entrypoint only; `md-utils agents skill --output-directory <new-directory>/`
exports the complete folder. See [Installation](references/installation.md).
