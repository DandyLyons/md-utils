# Wikilinks

Use `links list <paths>`, `links check <paths>`, or `links backlinks <target>` to inspect resolution, failures, or incoming references. `list` also has alias `ls`; use `--json` for structured results. `check` fails for broken/ambiguous links. Backlinks traversal flags select targets; source discovery always recurses.

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
