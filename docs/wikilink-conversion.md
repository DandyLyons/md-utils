# Wikilink target conversion

`links convert` rewrites existing wikilinks between collection-root-relative path
style (`wiki-path`) and unique name style (`wiki-link`), or repairs declared
frontmatter wikilinks toward a loaded mdtype v2 contract with `--type`. It does not convert to
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

`--root` and exactly one of `--to` or `--type` are required. Input paths follow the ordinary CLI file-selection
rules (relative to the working directory, recursive by default); `--root` does
not rebase input paths. Inputs must be inside the collection. Direct symlink inputs and
symlink ancestors are rejected; directory discovery skips symlinks before recursion.
Resolution excludes hidden files and symlinks.
Existing global selection flags, including `--no-recursive`, apply.

In `--to` mode, `--scope all|body|frontmatter` defaults to `all`. Repeatable `--key` requires
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

## Contract-aware conversion (#185)

```bash
# Preview declarations from the loaded Article type; paths remain working-directory-relative.
md-utils links convert vault/notes/ --root vault/ --type Article

# Resolve output ambiguity without overriding the contract.
md-utils links convert vault/notes/ --root vault/ --type Article \
  --prefer-style relative-path --markdown-extension omit --json

# Apply only the selected literal top-level subtree, including nested objects/arrays.
md-utils links convert vault/notes/ --root vault/ --type Article \
  --key references --include-recommendations --in-place
```

Contract mode selects whole-value Wikilink declarations in required loaded schemas.
It supports nested objects/arrays and literal punctuation in keys. It never scans
body text or repairs a wikilink substring inside prose. `--scope` may be omitted
or explicitly `frontmatter`; `all` and `body` are rejected. `--key` filters literal
top-level subtrees and does not require an explicit scope in this mode.
`--include-recommendations` opts into recommended schemas. Property-name rewriting
and missing-value creation are outside this mode.

Already-conforming occurrences remain unchanged, even if a preference requests a
different spelling. Repairs enumerate canonical name, vault-path, relative-path,
and (for same-file anchored links) self-anchor spellings, with actual or omitted
Markdown suffixes. Only uniquely resolved, representable outputs preserving the
original destination, alias, fragment and embed prefix are eligible. There is no
invented root marker or filesystem-absolute style. Attachments retain their suffix;
the contract can still make an attachment impossible to repair.

`--prefer-style name|vault-path|relative-path|self-anchor` and
`--markdown-extension include|omit` filter permissible repair candidates.
In contract mode `auto` means no extension preference. Exactly one candidate is
required; zero candidates or remaining ambiguity produces an unresolved result.
Preferences never weaken constraints, and a styles array's order has no meaning.

References and mandatory `allOf` checks share the semantic schema adapter.
For failing alternatives, the planner removes lexical policies only to determine
whether exactly one branch has compatible non-lexical shape; the actual candidate
must satisfy that branch's full assertions. Ambiguous alternatives, failing
negated declarations, failing existential `contains`, and link-dependent conditions
require review rather than guessed edits. Already-satisfied alternatives are not
repaired through failing sibling branches. Conditions selected by unrelated values
are supported, and the combined proposal must retain declaration applicability.

Each file is planned against a bounded authoritative collection snapshot. The
existing Fix-It transition evaluator blocks newly introduced required failures,
lost passing type conformance, lost rule membership, and unavailable preservation
evidence. The combined document is reassessed; lexical repair success does not
mean full type or relationship conformance. Existing unrelated failures remain
reported separately and do not alone cause the conversion command to fail.

Preview does not create locks, write an index, or refresh cached evidence.
Application holds the collection writer lease and rechecks definitions, every
supporting source revision, and the candidate namespace before the existing atomic
source-revision-checked write. This does not lock external editors or provide batch
atomicity. Each file is replanned after earlier writes. No-op bytes and timestamps
are preserved; metadata edits may change comments/formatting but retain native
values and untouched body bytes.

Contract JSON remains an array of file reports, with `file`, `status`, `changes`,
`assessment`, and optional `error`. Each change has typed `path` key/index components,
`original`, optional `replacement`, `status`, optional `reason`, and declaration
locations. Change statuses are `unchanged`, `would-change`, `changed`, and
`unresolved`. A rejected proposal may retain its suggested replacement for review;
only `changed` confirms a write. The separate `assessment` reports the resulting
whole-type pass/fail/unavailable outcome and diagnostics.

Exit 1 means a requested repair remains unresolved or a file failed operationally.
Safe repairs can be applied alongside unresolved occurrences; every unresolved
occurrence remains visible, even in a file reported as `changed`. Operational
failure stops the batch, preserving prior writes and listing later files as
`unprocessed`. A blocker rejects the combined edit for that file.

Costs are deliberately conservative: each file's preservation check can read and
assess the whole collection. The shared snapshot budgets are 10,000 records,
64 MiB of source bytes and 100,000 candidates; the Fix-It evaluator also bounds
record/type combinations and graph work. Schema selection is bounded to 100,000
visits and 128 levels. Each selected source and proposed document is limited to
8 MiB, matching shared Fix-It mutations. Budget exhaustion never authorizes an unchecked write.

Tests: `swift test --filter 'Wikilink|ContractConvertLinksTests|ConvertLinksTests'`.
