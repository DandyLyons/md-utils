# Frontmatter Commands

Read and mutate YAML or TOML frontmatter from the `frontmatter` command group.

## Overview

The `frontmatter` command group, also available as `fm`, provides CRUD operations for Markdown frontmatter. YAML uses `---` delimiter lines and TOML uses `+++`. Existing blocks retain their format; creation-capable commands accept `--frontmatter-format yaml|toml`, with YAML as the default. Commands can operate on one file, several files, or directories resolved through the shared global path options.

Common operations include reading values, setting values, checking for keys, removing or renaming keys, replacing or completely removing an entire frontmatter block, dumping frontmatter in multiple formats, checking uniqueness, sorting keys, and mutating array values. `fm search` is intentionally YAML-only. TOML has no null value, so `fm touch` cannot add an empty TOML key and reports an error instead.

Do not put comments in frontmatter that will be mutated by `md-utils`. YAML and TOML are parsed into a format-neutral value model and serialized again, so comments are not guaranteed to survive.

`fm set --key summary --value '' post.md` stores an empty string.
`fm set --key summary --null post.md` stores a YAML null. Supply exactly one of
`--value` or `--null`; `--value null` stores the literal string `null`.
TOML rejects `--null` without writing unless you explicitly convert using
`--frontmatter-format yaml`.

## Non-Markdown Hash Comments

Shipped shell, Ruby, R, YAML/TOML, Make/CMake, properties, Nix, Bazel, Terraform,
ignore-file, toolfile, and `.env.schema` mappings use fixed `# ` prefixes. Their
YAML and TOML delimiters are `# ---` and `# +++`. A block is legal at line 1,
immediately after a shebang, or after one empty post-shebang line. Exact basename
mappings take precedence over extension behavior, so `requirements.txt` uses
hash comments while an ordinary `.txt` remains opt-in Markdown-style text.

Every `fm` leaf accepts `--line-comment-frontmatter` for otherwise-unmapped
explicit regular files. All supplied inputs must be regular files; the flag is
rejected for implicit current-directory input, directories, and traversal. It
does not override Markdown or shipped wrapped mappings. Project rules use shipped
mappings only and do not honor this CLI override.

## Removing Complete Frontmatter

Use `fm remove-frontmatter`, or its `rmfm` alias, to delete the complete
frontmatter block while preserving the document body:

```bash
md-utils fm remove-frontmatter post.md
md-utils fm rmfm notes/ --include-non-md
md-utils fm rmfm post.md --yes
```

The command asks for `y` confirmation once per file that contains frontmatter.
Pass `-y` or `--yes` to skip the confirmation. Mapped non-Markdown files are
included in batch operations only when `--include-non-md` is supplied.

## Uniqueness Checks

Use `fm unique` to check that a scalar selected by JMESPath is unique across a
directory or explicit list of paths:

```bash
md-utils fm unique 'id' notes/
md-utils fm unique 'metadata.id' notes/
md-utils fm unique 'id' --reference foo.md notes/
```

Collection mode reports every collision. `--reference` instead checks only the
reference note's selected value and ignores unrelated collisions. Missing and
null results are skipped by default; use `--require-value` to reject them.

The expression must produce one string, number, or boolean for each note. Arrays,
objects, and projections such as `authors[].id` are unsupported. A future
`--each` option is outside the current command's scope.

Simple selectors such as `id` are safe unquoted, but single-quoting the complete
expression is recommended. Richer JMESPath syntax may contain characters that
Bash or Zsh interpret. Double-quoted expressions do not protect JMESPath backtick
literals from shell command substitution.

## Output Semantics

Commands that report values preserve the distinction between a missing key and a YAML null value. TOML cannot represent null. Machine-readable formats should be preferred when that distinction matters.

`fm dump` and `fm unique` support TOML output; `fm search` rejects it. Because TOML
requires a document root to be a table, generic scalar and array outputs use a
stable `value` key. `fm dump --format raw` reserializes the source format and
does not preserve original bytes, comments or layout. Collection raw output is
YAML. `--include-delimiters` uses matching `---` or `+++` lines for one file or
each `--cat-headers` block and is ignored for categorized collection output.

`fm dump` is read-only and automatically selects Markdown, plain-text, and
mapped non-Markdown files. A sole explicit file outputs its mapping directly.
Directory and explicit file-list invocations output an object whose
`frontMatter`, `noFrontMatter`, and `emptyFrontMatter` members distinguish
nonempty mappings, absent blocks, and complete blocks with empty mappings.

`fm has` prints `true`/`false` and succeeds for a missing key; read/parse errors
fail. `fm list` currently stops at the first file with no keys; use `fm dump`
for a complete collection inventory. `fm rename` uses `--key` and `--new-key`;
`fm touch` uses plural `--keys`. Frontmatter mutation commands write directly;
`fm sort-keys` does not take `--in-place`.

## JMESPath File Search

```bash
md-utils fm search 'draft == `true`' ./posts/
md-utils fm search 'contains(tags, `"swift"`)' ./posts/ --format json
```

The expression is positional, not `--query`, `--key` or `--value`. Search reads
YAML frontmatter directly without SQLite and always recurses through directories,
including hidden descendants. Omitted paths default to `.`; there is no
`--no-recursive` or `--exclude`. Raw output (default) is absolute paths, one per
line; JSON/YAML/plist output is a path array when matches exist. No matches
succeed with empty stdout in every format and diagnostics on stderr. TOML
frontmatter/output is rejected. Read/parse errors fail after available matches;
per-file query evaluation errors are skipped. For YAML/TOML string membership,
use `fm array contains`; it supports `--case-insensitive`, skips missing/non-array
keys even with `--invert`, and fails for no matches.
