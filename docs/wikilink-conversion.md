# Wikilink target conversion

`links convert` rewrites existing wikilinks between collection-root-relative path
style (`wiki-path`) and unique name style (`wiki-link`). It does not convert to
ordinary Markdown links or expose server endpoints (follow-ups #182 and #183).

```bash
# Preview; no files are written.
md-utils links convert --to wiki-path vault/notes/ --root vault/

# Apply explicitly.
md-utils links convert --to wiki-path vault/notes/ --root vault/ --in-place

# Simplify targets, only when the name still resolves to the same file.
md-utils links convert --to wiki-link vault/notes/ --root vault/

# Select body occurrences or specific literal top-level frontmatter keys.
md-utils links convert --to wiki-path vault/notes/ --root vault/ --scope body
md-utils links convert --to wiki-path vault/notes/ --root vault/ \
  --scope frontmatter --key related --key references --json
```

`--root` and `--to` are required. Input paths follow the ordinary CLI file-selection
rules (relative to the working directory, recursive by default); `--root` does
not rebase input paths. Inputs must be inside the collection. Direct symlink inputs and
symlink ancestors are rejected; directory discovery skips symlinks before recursion.
Resolution excludes hidden files and symlinks.
Existing global selection flags, including `--no-recursive`, apply.

`--scope all|body|frontmatter` defaults to `all`. Repeatable `--key` requires
`--scope frontmatter`; absent keys are ignored. Selected frontmatter strings and
arrays (including nested arrays) are traversed; object values are not traversed.
Body scanning follows the existing wikilink scanner, including literal wikilinks
inside code blocks and inline code.

## Resolution and preservation

`--markdown-extension auto|include|omit` controls only `.md` and `.markdown`:

| Policy | `wiki-path` | `wiki-link` |
| --- | --- | --- |
| `auto` (default) | Include the actual Markdown extension | Omit the Markdown extension |
| `include` | Include the actual Markdown extension | Include the actual Markdown extension |
| `omit` | Omit the Markdown extension | Omit the Markdown extension |

For example, `--to wiki-path --markdown-extension omit` can produce
`[[People/Alice]]`, while `--to wiki-link --markdown-extension include` can produce
`[[Alice.md]]`. `.markdown` is retained as `.markdown`, never changed to `.md`.
Non-Markdown extensions such as `.txt`, `.png`, and `.pdf` are always retained.
If omission introduces ambiguity (for example both `Alice.md` and `Alice.markdown`
exist), the original link remains unchanged with a diagnostic.

- By default, `[[Alice]]` can become `[[People/Alice.md]]`; the reverse conversion omits
  `.md`/`.markdown` but preserves attachment extensions.
- Bare names use collection-wide case-insensitive stem matching. Explicit paths
  containing `/` resolve from the collection root; only `./` and `../` prefixes
  select the source directory. Missing paths never fall back to another directory
  or an unrelated basename. If both Markdown extensions exist
  at an extensionless explicit path, the target is ambiguous.
- Every proposed target is resolved again and must uniquely identify the original
  destination. Source-relative files cannot shadow root-relative conversions.
- Root-level output uses `[[Alice.md]]` only when that spelling uniquely resolves
  to the original file. A nested duplicate makes it ambiguous. No special root
  marker is invented.
- Missing, ambiguous, unrepresentable, or destination-changing conversions remain
  unchanged with per-occurrence diagnostics. These skips are not command failures.
- Display text, heading/block fragments, and embed prefixes retain their original
  spelling. Self-heading links such as `[[#Overview]]` remain unchanged.
- Body-only changes retain the exact frontmatter envelope. Metadata changes retain
  unaffected values and body text but may reserialize YAML/TOML and remove comments
  or formatting. The existing source format is retained.

## Compatibility

Compatibility change (#170): `[[sub/Target]]` previously tried the source
directory before the collection root. It now means only the root-relative path;
use `[[./sub/Target]]` for a file beneath the source directory or `[[../Target]]`
for one in its parent. Relative paths remain confined to discovered vault files;
hidden files, symlinks, and files outside the vault are not candidates. This does
not change `--root` defaults for list/check/backlinks (the working directory).

## Preview, application, and output

The default output lists each file's status and each replacement or skipped
occurrence. `--in-place` writes without prompting. `--json` emits an array of file
reports with `file`, `status`, and `changes`, plus `error` when present. Each change
has `location`, `original`, and either `replacement` or `diagnostic`.

Statuses are `would-change` (preview), `changed` (written), `unchanged`, `failed`,
and `unprocessed`. On the first file failure processing stops, reporting prior
successful files and every remaining unprocessed file; the exit status is nonzero.
There is no batch rollback. Missing/ambiguous links alone do not cause failure.

Application refreshes the resolver before planning each file and uses the shared
revision-checked atomic writer. Source bytes must still match the planning
snapshot. No-op files retain their bytes and modification times. A preview is not
a persisted plan: a later `--in-place` invocation replans against current files.
Uncoordinated external edits can still race the final check and replacement, or
change link targets after resolution; this command does not lock other editors.

Tests: `swift test --filter 'Wikilink|ConvertLinksTests'`.
