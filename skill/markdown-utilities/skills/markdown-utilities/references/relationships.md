# Relationship queries

Named assertions use explicit mdtype v2 declarations; see [Types](types.md).
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

For collection consistency policies and reviewed relationship repairs, read
[Rules](rules.md). `rules validate` is read-only; `rules fix` previews
by default and requires explicit application.
