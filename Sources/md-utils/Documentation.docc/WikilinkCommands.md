# Wikilink Commands

Inspect Obsidian-style wikilinks in Markdown files.

## Overview

The `links` command group scans Markdown content for wikilinks, resolves them against a vault root, reports broken or ambiguous links, and finds backlinks to a target note.

Resolution is based on Markdown file names and paths inside the vault. Commands that check link health are intended for automation and can fail when broken or ambiguous links are found.

## Convert target styles

`md-utils links convert --to wiki-path vault/notes/ --root vault/` previews
collection-root-relative targets. Use `--to wiki-link` for unique name targets.
`--root` is required; `--in-place` explicitly writes. `--scope all|body|frontmatter`
selects occurrences, and repeatable `--key` selects literal top-level keys with
`--scope frontmatter`. `--json` emits per-file changes, diagnostics, and outcomes.

`--markdown-extension auto|include|omit` defaults to `auto`: include `.md` or
`.markdown` for `wiki-path`, omit for `wiki-link`. Overrides still require unique
resolution to the same file. Non-Markdown extensions such as `.txt` are always
retained; `include` preserves the actual Markdown extension.

Only destination-preserving conversions are applied. Missing or ambiguous links
remain unchanged. Root-level targets have no special prefix and must be unique.
Aliases, fragments, and embeds are preserved. Body-only edits preserve frontmatter
bytes; metadata edits may reformat YAML/TOML. No-op files are not written. Writes
check source revisions; a batch stops at its first failure and reports partial
completion. See `docs/wikilink-conversion.md` for detailed semantics.
