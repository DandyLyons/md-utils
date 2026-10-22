# Wikilink Commands

Inspect Obsidian-style wikilinks in Markdown files.

## Overview

The `links` command group scans Markdown content for wikilinks, resolves them against a vault root, reports broken or ambiguous links, and finds backlinks to a target note.

Resolution is based on Markdown file names and paths inside the vault. Commands that check link health are intended for automation and can fail when broken or ambiguous links are found.

Bare names use case-insensitive collection-wide matching and duplicate matches
are ambiguous. Targets containing `/`, such as `[[About/Daniel Lyons.md]]`, are
vault-root-relative. Only `./` and `../` explicitly select source-relative paths.
A missing path stays unresolved without trying another directory or basename.
Omitted extensions match `.md` or `.markdown` (ambiguous if both exist);
attachments require their extensions. Hidden files, symlinks, and paths outside
the vault are excluded. Self-heading links resolve to the source file.

Compatibility change (#170): replace formerly implicit source-relative links
such as `[[sub/Target]]` with `[[./sub/Target]]`. Unprefixed paths now always use
the vault root. List, check, and backlinks default `--root` to the working
directory; specify `--root vault/` when working elsewhere.

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

## Convert declared frontmatter links

Use `md-utils links convert vault/notes/ --root vault/ --type Article` to preview
repairs for a loaded mdtype v2's declared whole-value wikilinks, including nested
keys and arrays. `--type` replaces `--to`; body selection is not supported in this
mode. `--prefer-style` and `--markdown-extension include|omit` select among valid
outputs only. Already-conforming values stay unchanged; `auto` means no extension
preference. Recommended schemas require `--include-recommendations`.

The command preserves destination identity and passing required conformance.
Ambiguous schema intent or output, missing targets and unrepresentable constraints
remain unresolved. `--json` separates per-occurrence repairs from whole-type
assessment. Unresolved repairs exit nonzero, including after partial writes.
Preview is read-only; `--in-place` rechecks authoritative evidence before writing.
