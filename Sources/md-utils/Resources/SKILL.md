---
name: markdown-utilities
description: >-
  Parse, manipulate, and analyze Markdown and mapped text files using the `md-utils` CLI. Supports YAML and TOML frontmatter CRUD and array operations, wrapped and fixed hash-comment non-Markdown frontmatter, YAML-only JMESPath search, structured document exploration, heading manipulation, section extraction and reordering, table of contents generation, wikilink analysis, line extraction, and format conversion. Handles batch operations across files and directories. Use when working with Markdown or mapped text files to: read or write frontmatter, inspect lengthy document structure, restructure documents, search YAML files by metadata using JMESPath, generate a TOC, extract sections or line ranges, check wikilinks, or convert to plain text or CSV. More reliable than grep/regex for structured Markdown operations.
---

# Markdown Utilities

The `md-utils` CLI provides structured operations on Markdown files. Add `--help` to any command for full options.

Explicit mdtype v2 definitions support semantic `type: string` / `format` contracts:
`Date`, `LocalTime`, `DateTime`, `UUID`, and whole-value `Wikilink`. Quote temporal
frontmatter values. `frontmatter.recommendedSchemas` produces advisories; invalid
declarations still fail loading. Existing `types check` and `rules validate` assert
these formats, including nullable branches and array items. New definitions still
default to v1. No scalar inference, normalization, destination resolution or UUID
identity allocation occurs during assessment.

For mdtype v2 wikilink spelling checks, declare top-level
`requires: [wikilink-constraints]`, then add `wikilink` beside `type: string` and
`format: Wikilink`: `styles` accepts an unordered array of `name`, `vault-path`,
`relative-path`, `self-anchor`; `markdownExtension` accepts `require`, `omit`,
`either`. A root-level bare name is not strict vault-path style. These checks never
rewrite or resolve links. Explicit `links convert --type Name` can preview or
apply contract-aware frontmatter repairs; validation itself remains read-only.

For named frontmatter assertions, declare `requires: [document-relationships]`
and a top-level `relationships` mapping. Each name has a literal-key/array `select`
and `target: {type: person.mdtype.yaml}` relative to `.md-utils/types/`.
`md-utils rel out|in|both Note.md --type Person --root ./vault/ --json` queries
declared relationships and ordinary links; `--yaml` is also supported. Long spellings are
`relationships outgoing|incoming|both`. Self-links have their own section.
All formats default to `--detail summary`: declared triples/ordinary links and brief
concern hints. Use `--detail explain` for applicability and findings, or
`--detail evidence` for malformed values, candidates, provenance and assessment graphs.
Detail never changes evaluation or exit status; incomplete results stay concise
unless higher detail is requested. Users own domain meaning and truth.
Omit `--type` for automatic declarations from conforming types, applicable rules
and hints. `--type` is a declaring-contract override; `--relation` requires it and
filters named results while ordinary links remain visible.
Select multiple positional Markdown paths, recursive `--select-folder`, structural
`--select-type`, unconditional `--select-required-type`, applicability `--select-rule`,
exact YAML `--select-tag` or `--select-jmespath`. JMESPath receives path,
frontmatterFormat, frontmatter and body; TOML selector skips are reported.
Multiple selectors require `--select-mode union|intersection`; repeated
`--exclude-file|--exclude-folder|--exclude-type|--exclude-rule|--exclude-tag` subtract
afterward. Incoming sources are searched throughout the explicit root.
`--files-from` accepts UTF-8 LF-separated root-relative paths; `--files-from0`
accepts NUL-separated paths. Either accepts `-` for stdin once. All lists and
positional paths form one deduplicated selector. No selection is an error; use
`--select-folder .` for the collection. Empty supplied lists succeed with zero results.
Complete queries exit 0 even for broken/nonconforming assertions; incomplete queries
exit 1 with available results. Ordinary links need no declarations; embeds/images,
attachments, external URLs and same-document anchors remain outside ordinary discovery.
Ordinary outgoing queries read selected sources/dependencies without refreshing
the whole index. Incoming/both refresh an existing compatible index;
`--no-index` bypasses it and
`--index-only` (alias `--indexed-only`) means SQLite-only on both relationships and
rule validation: no raw source/configuration/schema reads, source stats, refresh,
index writes or fallback. It rejects `--verify-hashes` and `--no-index`. Findings
describe the published generation. Explicit `index update` publishes ordinary
body/frontmatter links, named relationship evidence and reverse edges even in
metadata-only mode. Missing or older-generation projections remain explicitly
incomplete; raw files never fill those gaps. Snapshot JMESPath selection remains
unavailable because its envelope needs full body text.
Ordinary live queries may reuse assessments after filesystem freshness verification.
Older indexes require `index update --rebuild` for cache format 9.

Standalone rules may opt into independent `md-utils-rule-schema: "1"` and
`relationshipPolicies`: explicit cycles, selfLinks, reciprocity, or directional
inverse checks over named type-resource relations, with selected/reachable scope.
`rules validate --json|--yaml` reports collection evidence. Cycle reporting defaults
to `--cycle-witness-per-component`; opt into `--cycle-witness-first` for early
cycle-search termination. The flags are mutually exclusive. Required failure or
unavailability exits nonzero; advisories remain visible without failing validation.
Policies never infer truth or write return assertions. Legacy rules omit the
discriminator and reject policy fields; authoring defaults remain unchanged.

`rules fix [rule]` previews shared Fix-Its by default, including exact source changes
and before/after assessment. Use `--select 1,4,5` (or repeated `--select`) to preview
a combined selection. Only `--apply` persists changes; noninteractive numbered
application also requires the printed `--review` token. Tokens bind proposals to
supporting files, definitions, candidate namespace and scope; stale evidence requires
fresh review. Relationship assertions require explicit selection, never `--yes`
alone. `--yes` selects automatic schema fixes only; known defaults still require
selection. Advisory repairs additionally need `--include-recommendations`.
Unavailable/ambiguous evidence and conflicting edits block application. Metadata
may be reserialized under shared codec guarantees; unrelated values and body bytes
are preserved. Application uses shared drafts/receipts and sequential coordinated
writes, not cross-file atomicity. On failure, inspect `index draft show`, resolve
indeterminate attempts with `index draft resolve`, and resume `index apply` with
every batch draft ID (including completed members); confirmed commits are not
rewritten. No server configuration is needed for Fix-It drafts. Remaining required
failures exit nonzero. Cached assessments never replace final Fix-It review/revision checks.

## Commands at a Glance

| Command | Purpose |
|---------|---------|
| `md-utils fm` | YAML/TOML frontmatter: get, set, remove blocks, uniqueness checks, array ops, dump; YAML-only search |
| `md-utils fm search '<JMESPath>' ./posts/` | Find files by YAML metadata; the query is positional |
| `md-utils explore` | Progressively inspect large Markdown files by tree, heading, and line |
| `md-utils toc` | Generate headings-only Markdown by default; use `--format md-bullet-links` for anchor links |
| `md-utils slug 'My Title'` | Print a slug candidate without changing files or checking uniqueness; `--policy unicode`, `strictASCII`, or `preserve` |
| `md-utils headings` | Promote or demote heading levels |
| `md-utils section` | Get, replace, or reorder sections |
| `md-utils extract` | Extract a section by name or index |
| `md-utils body` | Output document body without frontmatter |
| `md-utils lines` | Extract a line range |
| `md-utils convert` | Convert to plain text or CSV |
| `md-utils links` | List, check, find backlinks, or convert wikilink target styles |
| `md-utils meta` | Read file metadata |
| `md-utils rules` | Validate Markdown files with project-level rules |
| `md-utils types` | Define/check structural types, find conforming files, fix or create instances |
| `md-utils relationships` / `md-utils rel` | Query outgoing/incoming/both with explicit root and file selectors |
| `md-utils template render` | Render Knap with JSON input files |
| `md-utils format` | Normalize bullet/italic markers or tables |
| `md-utils okf` | Work with experimental OKF v0.1 draft bundles |
| `md-utils config` | Initialize, inspect or migrate project configuration |
| `md-utils agents` | Print bundled skill/schema or installation instructions |
| `md-utils index` | Maintain a rebuildable SQLite collection cache with type/rule assessments |
| `md-utils copy` / `md-utils move` | Revision-checked transfers through configured resource opt-ins; copy allocates a fresh configured UUID |

`links convert --to wiki-path|wiki-link vault/files/ --root vault/` requires explicit
collection context and previews by default; `--in-place` writes.
`--markdown-extension auto|include|omit` controls Markdown suffixes: `auto`
includes them for wiki-path and omits them for wiki-link. Other extensions are
always retained, and omission must preserve unique destination resolution. Select occurrences
with `--scope all|body|frontmatter`; repeated `--key` requires frontmatter scope.
`--json` reports per-file outcomes. Missing/ambiguous or destination-changing links
are skipped. Writes check revisions, preserve no-ops, and stop at the first file
failure with partial-completion reporting. Metadata edits may reformat frontmatter.
Markdown-link output and server conversion are not supported by this command.

Alternatively, `links convert vault/files/ --root vault/ --type Name` repairs declared
whole-value frontmatter wikilinks, including nested keys/arrays. It replaces `--to`;
body/all scope is invalid. `--key` optionally filters literal top-level subtrees.
`--prefer-style name|vault-path|relative-path|self-anchor` and extension include/omit
only disambiguate contract-permitted repairs; auto supplies no extension preference.
Conforming values remain unchanged. Recommended schemas need
`--include-recommendations`. Ambiguous branch intent/output, missing destinations,
or unrepresentable requirements stay unresolved and cause nonzero exit status.
JSON separates occurrence outcomes from whole-type assessment. Preview uses bounded
read-only collection evidence; application preserves passing required conformance
and rechecks definitions, sources and candidates before revision-checked writes.

Wikilink paths containing `/` resolve only from the vault root unless prefixed
with `./` or `../` for source-relative resolution. Missing paths never fall back
to another directory or basename. Bare names retain collection-wide ambiguity;
omitted Markdown extensions match `.md`/`.markdown`, while attachments require
extensions. Paths must be discovered vault files (no hidden files or symlinks).
Compatibility (#170): change implicit source-relative `[[sub/Target]]` links to
`[[./sub/Target]]`. List/check/backlinks default `--root` to the working directory.

## Collection Indexing

On macOS, `md-utils index watch ./notes/` registers a scope and completes an
initial refresh before watching native changes. Omit the directory to watch
saved scopes. It reloads configuration, debounces changes, and periodically
reconciles missed events while retaining the persisted metadata-only/FTS mode.
Ctrl-C/SIGTERM cancels pending work. Other platforms require `index update`.
Use `--debounce <seconds>` and `--reconcile-interval <seconds>` to tune latency.

`md-utils rules validate` automatically refreshes an existing project index's
requested rule scopes and reuses current assessments. Without an index it validates
directly, suggesting indexing after scans above 1,000 files. Index failures warn
on stderr and fall back to source validation. `--no-index` bypasses indexing and
suppresses advice; `--verify-hashes` detects stat-preserving edits. Both validation
paths skip symlinks; consistent symlink support including indexing is future work.
Simple positive rule paths such as `PROBLEMS/**/*.md` automatically narrow direct
validation and native CLI index discovery to `PROBLEMS/`. Broad globs and recursive
match groups retain full-project discovery; manual narrowing is unnecessary for
simple directory-based rules.

`md-utils index update ./notes/` registers a directory scope and refreshes all
saved scopes in `.md-utils/index.sqlite`. `index type Book ./notes/` selects only
conforming documents; `index rule books` preserves rule-selected invalid members.
Use `index update --verify-hashes` to detect stat-preserving edits, or
`index update --rebuild` to create a fresh cache from `.md-utils/md-utils.indexconfig.json`,
restoring managed fields/type views and discarding observation history. Files remain authoritative. Use `--project-root <directory>/` and
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
`index provenance <path>...` prints retained observations and confirmed operations
after a hash-verified refresh; it never repairs UUIDs automatically.

Stage explicit patch/replace intent with `index draft add <collection-relative-path>
--resource <name> --revision <source-sha256> --patch-file <file>` (or `--replace-file`).
Use the configured resource's shared mutation JSON envelope and operation opt-ins.
`index draft list/show` reads durable intent; `index apply --dry-run` previews exact
source and diagnostics without refresh, recovery, or persistent state changes.
`index apply` replans and revision-checks each file, publishing all affected scopes
and enabled FTS. Drafts remain outside SQLite through refresh/rebuild. Managed move
evidence can follow a configured UUID; external relocation, UUID collisions, and
stale hashes require explicit review. Never treat arbitrary indexed-row edits as
write intent. Partial batches retain completed/pending outcomes; use `index draft
resolve <id> --decision confirmCommitted|confirmNotCommitted` only after reviewing
the receipt and actual source. Unresolved submitted drafts cannot be discarded.

Use managed `copy`/`move` for UUID-aware transfers rather than naive filesystem
copies. Both require `--resource`, `--revision <source-sha256>`, and
`--idempotency-key`; the source is collection-relative and the destination argument
is a filename inside the resource's configured `creation.directory`. The server
resource must explicitly enable the operation. Copy accepts `--identifiers` JSON
for new configured identifiers (for example a slug), generates a new configured
UUID and preserves the source. Move preserves bytes/UUIDs. Neither rewrites links.
Retain the exact revision/key for retries. Incomplete receipts require recovery;
an interrupted move can leave both paths present. Do not delete either blindly.
Arrays require explicit `json_each` membership queries; indexing the whole JSON
array does not accelerate individual elements.

## Batch Operations

Commands using shared path options generally accept files and directories and
recurse by default (`--no-recursive` disables traversal). Check each command's
help: `lines`, `explore`, `extract`, and most section edits require one file;
`fm search` always recurses and has its own options. `body` and `convert to-text`
require paths or stdin rather than implicitly scanning the working directory.
`links backlinks` traversal flags select targets; its source scan always recurses.

`fm search '<JMESPath>' ./posts/` directly scans YAML frontmatter without the
SQLite index. Raw output is absolute paths, one per line; `--format json|yaml|plist`
serializes matches. TOML input/output is rejected. No matches succeed with empty
stdout (including structured formats). Query evaluation errors skip a file;
read/parse errors fail after reporting available matches. `fm array contains`
supports string membership in YAML/TOML and `--case-insensitive`; unlike search,
no matches fail. Missing/non-array keys are skipped even with `--invert`.
`fm has` prints true/false and succeeds for missing keys; never use its exit code
as a presence predicate. `fm set --value` always stores a string, not a boolean
or array. `fm dump --format raw` reserializes the source format; it does not
preserve original bytes or comments. Use `fm dump` for categorized collection
inventory. `fm list` continues through files without keys and retains failures
from earlier files.

```bash
md-utils fm set --key author --value "Jane Doe" posts/
md-utils toc docs/*.md
```

## Quick Examples

```bash
# Get a frontmatter value
md-utils fm get --key title post.md

# Set an empty string or an explicit YAML null (mutually exclusive options)
md-utils fm set --key summary --value '' post.md
md-utils fm set --key summary --null post.md

# TOML cannot represent null; explicitly convert to YAML when needed
md-utils fm set --key summary --null --frontmatter-format yaml post.md

# Create TOML frontmatter in a document that has none
md-utils fm set --key title --value "TOML Note" --frontmatter-format toml post.md

# Use fixed # frontmatter in an otherwise-unmapped explicit regular file
md-utils fm get --key title tool.conf --line-comment-frontmatter

# Find files with a specific tag
md-utils fm array contains --key tags --value swift posts/

# Initialize missing or null values while preserving existing arrays, or empty an array
md-utils fm array init --key tags posts/
md-utils fm array clear --key tags post.md

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
Default document mode accepts a JSON object of named variables and renders the
whole document. Use Knap `yaml`/`yaml_property` for YAML frontmatter; avoid templated
TOML without a serializer. Explicit `--mode body` accepts required `data` and optional
`frontmatter`, serializing the latter separately. Optional `--schema` inserts missing
defaults before validation. Supplied null/false/zero/empty strings are preserved.
Omit `--output` for stdout; warnings go to stderr.

Types may declare `creation.template` with `inline` or `ref`, optional `mode`, and
nested `inputSchema` (`inline` or `ref`). References are relative to the definition.
Use `md-utils types new --type Book --value ./dune.json --filename-data '$.title' ./Books/`.
Rules require `creation.directory`, relative to project root, and `creation.type`
when ambiguous: `md-utils rules new --rule Books --value ./dune.json --filename Dune.md`.
No glob destination inference occurs. Exactly one filename option is required;
`--filename` is exact, while `--filename-data` selects one string via JSONPath after
defaults and appends `.md`. `--extension txt` changes it; `--extension ''` omits it.
Directories must exist; writes never overwrite. `--dry-run` has no persistent
effects. Type/rule nonconformance is advisory and still saves with success; input
schema, rendering, filename, and persistence errors block creation.
For bulk creation use `--values ./books.json` (a nonempty array of objects), or repeat
`--value-file ./dune.json --value-file ./foundation.json`, instead of `--value`.
Bulk requires `--filename-data`; extension controls still apply. The entire batch
is preflighted and all collision participants are reported before any writes.
`--dry-run` has no persistent side effects. Publication stops at the first write
failure, preserves created files, and reports created/failed/not-attempted items.

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
