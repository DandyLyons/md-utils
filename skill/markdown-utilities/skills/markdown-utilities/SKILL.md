---
name: markdown-utilities
description: >-
  Parse, manipulate, and analyze Markdown and mapped text files using the `md-utils` CLI. Supports YAML and TOML frontmatter CRUD and array operations, wrapped and fixed hash-comment non-Markdown frontmatter, YAML-only JMESPath search, structured document exploration, heading manipulation, section extraction and reordering, table of contents generation, wikilink analysis, line extraction, and format conversion. Handles batch operations across files and directories. Use when working with Markdown or mapped text files to: read or write frontmatter, inspect lengthy document structure, restructure documents, search YAML files by metadata using JMESPath, generate a TOC, extract sections or line ranges, check wikilinks, or convert to plain text or CSV. More reliable than grep/regex for structured Markdown operations.
---

# Markdown Utilities

The `md-utils` CLI provides structured operations on Markdown files. Add `--help` to any command for full options.

## Commands at a Glance

| Command | Purpose |
|---------|---------|
| `md-utils fm` | YAML/TOML frontmatter: get, set, remove blocks, uniqueness checks, array ops, dump; YAML-only search |
| `md-utils explore` | Progressively inspect large Markdown files by tree, heading, and line |
| `md-utils toc` | Generate table of contents |
| `md-utils slug 'My Title'` | Print a slug candidate without changing files or checking uniqueness; `--policy unicode`, `strictASCII`, or `preserve` |
| `md-utils headings` | Promote or demote heading levels |
| `md-utils section` | Get, replace, or reorder sections |
| `md-utils extract` | Extract a section by name or index |
| `md-utils body` | Output document body without frontmatter |
| `md-utils lines` | Extract a line range |
| `md-utils convert` | Convert to plain text or CSV |
| `md-utils links` | List, check, or find backlinks for wikilinks |
| `md-utils meta` | Read file metadata |
| `md-utils rules` | Validate Markdown files with project-level rules |
| `md-utils index` | Maintain a rebuildable SQLite collection cache with type/rule assessments |

## Collection Indexing

On macOS, `md-utils index watch ./notes/` registers a scope and completes an
initial refresh before watching native changes. Omit the directory to watch
saved scopes. It reloads configuration, debounces changes, and periodically
reconciles missed events while retaining the persisted metadata-only/FTS mode.
Ctrl-C/SIGTERM cancels pending work. Other platforms require `index update`.
Use `--debounce <seconds>` and `--reconcile-interval <seconds>` to tune latency.

`md-utils index update ./notes/` registers a directory scope and refreshes all
saved scopes in `.md-utils/index.sqlite`. `index type Book ./notes/` selects only
conforming documents; `index rule books` preserves rule-selected invalid members.
Use `index update --verify-hashes` to detect stat-preserving edits, or
`index update --rebuild` to regenerate all scopes while retaining SQL field indexes
and views. Files remain authoritative. Use `--project-root <directory>/` and
`--config <file>` for explicit configuration; nonstandard configs require a root.
`--include-non-md` is saved per scope. Scans skip hidden files and symlinks.
Incomplete scans retain unavailable rows and report errors. Query
`current_documents` for current parsed members, and inspect `assessments` and
`diagnostics` for nonconformance, parsing/evaluation errors, and advisories.
Use `index query '<sql>'` for bounded read-only SQL that refreshes every scope
first and streams rows with independent `--limit`, `--max-bytes`, and
`--max-value-bytes` bounds. Use one-column `--format nul` for unambiguous paths.
New caches are metadata-only. Run `index search enable` to retain one body per
document and build external-content FTS; `index search disable --vacuum` removes
bodies and search storage. Use `index explain '<sql>'` for query plans, `index field
add '$.field'` for an explicit JSON expression index and type-view projection, and
`index status` for freshness. Type views are named `type_<normalized-name>`.
Arrays require explicit `json_each` membership queries; indexing the whole JSON
array does not accelerate individual elements.

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

# Create TOML frontmatter in a document that has none
md-utils fm set --key title --value "TOML Note" --frontmatter-format toml post.md

# Use fixed # frontmatter in an otherwise-unmapped explicit regular file
md-utils fm get --key title tool.conf --line-comment-frontmatter

# Find files with a specific tag
md-utils fm array contains --key tags --value swift posts/

# Check that every frontmatter ID is unique
md-utils fm unique 'id' posts/

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

Core library callers can use `MarkdownRuleCheckPredicate.typeConformance` to enforce
a compiled mdtype after selection. This is not a supported 0.1.0/0.2.0 config check:
do not insert `typeConformance` or the 0.3.0 `types` field into legacy configs.

The standalone rule parser and Core runtime support recursive `allOf`, `anyOf`,
`oneOf`, and `not` matcher expressions through `MarkdownRuleMatchExpression`.
Opt-in 0.3.0 projects use `{"configVersion":"0.3.0"}` and standalone `.mdrule.json`
files recursively under `.md-utils/rules/`, excluding `rules/legacy/`. Each rule has
`name`, optional `match`, and required `types`. Both expressions support these four
operators; type leaves are explicit `.mdtype.json/.yaml/.yml/.toml` filenames relative
to `types/`. Nested references are supported. `rules add books --type book.mdtype.json`
references an existing type. List, describe, validate, matching explanations, and
remove operate on standalone files; removal preserves type/schema resources.

Valid `$md-utils.typeHints` remain name-based and do not establish conformance.
`types interactive` and `rules interactive` require 0.3.0 and a terminal. They
provide CRUD with validated previews and confirmation; a rule can draft a new
type in-process. Existing resource paths and unrelated files are preserved.
Cancel or decline confirmation to discard all drafts. JSON Schema authoring stays
external (`sourcemeta/jsonschema`, `ajv-cli`, `check-jsonschema`, `swaggest/json-cli`).

Back up `.md-utils/` before `config migrate --to 0.3.0`; preview with `--dry-run`.
Automatic migration supports required-schema-only rules and refuses incompatible
conversions before writes. It preserves legacy config and rule artifacts, replaces
active config last, and warns that malformed hints newly fail. There is no staging,
manifest, or multi-file atomicity guarantee. On interruption restore the backup or
inspect reported generated files before retrying. Default init and legacy configs
remain 0.2.0 and retain their existing syntax and behavior.

## Knap Templates

Use `md-utils template render --template ./templates/report.knap --data ./data/report.json --output ./reports/report.md`.
Input is JSON with required `data` and optional `frontmatter` object. Templates use
Knap for the body; md-utils serializes frontmatter as YAML. Use Knap's standard
Markdown filters (`h1`, `list`, `table`, `bold`) and `??` fallback. Optional `--schema`
validates the envelope without supplying defaults. Omit `--output` for stdout;
warnings go to stderr. Existing output is unchanged on failure. No old template
language or translation is supported. Keep YAML/TOML delimiters out of templates.

## Reading Long Markdown Files

Prefer `md-utils explore` before reading especially lengthy Markdown files, such as files around 400+ lines or 1000+ words. Start with a whole-document structure view, then expand only the relevant sections by heading line number.

```bash
md-utils explore --tree document.md # Read a condensed tree of every section heading names and line numbers
md-utils explore --expand-line=4,10,123,246 document.md # Expand sections at specific line numbers to view their content
```

Use the `--tree` output to identify headings, source line numbers, frontmatter, preamble, and section metadata without dumping body text. Then use `--expand-line` with comma-separated heading line numbers to retrieve only the sections needed for the task.

## Reference Files

Load these when you need detailed command options:

- **[Frontmatter operations](references/frontmatter.md)** — get, set, has, list, remove keys or complete blocks, rename, replace, sort-keys, touch, dump, search, array ops
- **[Headings & sections](references/headings-sections.md)** — explore, promote/demote, section get/set/move, extract, TOC, lines, body, convert, links
- **[Common use cases](references/common-use-cases.md)** — practical recipes and pipelines
