# CLI help audit — issue #187

Audited on 2026-10-21 against the native `md-utils` executable and command
implementations, including contract-aware `links convert --type` from #185.
This document records the completed audit and fixes for
[issue #187](https://github.com/DandyLyons/md-utils/issues/187). Changes are
intentionally help/documentation/test changes; command behavior and registration
are preserved.

## Method and scope

Read `AGENTS.md` and the current issue first. Recursively captured root help and
every registered descendant's `--help` from `.build/debug/md-utils`, following
the executable's immediate subcommand listings. Cross-checked that inventory
against `CLIEntry.configuration` recursively in `CLIHelpTests`; this avoids
mistaking repeated subcommand examples in discussions for registrations.

Coverage: **123 unique pages**, including root, all groups and leaves;
**19 listed command aliases** resolve to the same help as their canonical names.
ArgumentParser's built-in `help` route was also checked. This inventory covers
the `md-utils` executable; `md-utils-server` is a separate executable.

For each page, reviewed descriptions, registered aliases, options, actual
defaults, examples, output formats, file/directory scope and recursion,
YAML/TOML/non-Markdown support, and index behavior where applicable. Compared
help with option declarations, validation and run paths, and shared selection,
serialization and index adapters. A dash in the findings column means no
additional command-specific discrepancy was found; shared findings still apply.

Local captures and example fixtures are under ignored `tmp/cli-help-audit/`.
They are working evidence, not required distribution artifacts. The permanent
inventory below is tested against registration; changed executable help and
representative examples are covered by native verification.

## Findings and corrections

| ID | Verified problem | Correction and implementation evidence |
| --- | --- | --- |
| F01 | Root frontmatter description hid JMESPath file search; nested conversion/index workflows were hard to discover. | Root pointers and the `frontmatter`/`links` abstracts expose nested capabilities without adding root commands. `Search.run` still receives a positional expression. |
| F02 | Shared path help omitted implicit `.` and command-specific input differences; extension text mentioned only dump's mapping exception. | Describe shared defaults and body/to-text stdin exceptions; explain frontmatter mapping selection. `GlobalOptions.resolvedPaths` and `resolvedFrontMatterPaths` retain their existing behavior. |
| F03 | `convert` omitted CSV and claimed generic file output; TOC discussion claimed unordered links despite a headings-only default. | Describe each converter's output, TOC's actual `.mdOnlyHeadings` default, explicit bullet links, and filename headers in batch JSON. `GenerateTOC.processFile` emits per-file headers. |
| F04 | `section list --help` generated the invalid usage `md-utils section table-of-contents list`. | Override help usage only; keep delegation to `GenerateTOC` and accepted arguments unchanged. |
| F05 | Shared format descriptions marked JSON as default even in raw-default search; several option descriptions duplicated generated defaults. | Remove the hardcoded JSON/default label and redundant numeric/format defaults; retain parser-generated defaults. |
| F06 | Search omitted formats/refusals, no-match behavior, hidden recursion, direct-file/index distinction and query-error handling. Mutation pipelines implied boolean writes and mishandled spaces/empty results. | Document YAML-only input, raw/JSON/YAML/plist output, rejected TOML, always-recursive traversal, no index, empty stdout/exit 0 for no matches, skipped evaluation errors and failed reads/parses. Use quoted read loops and string-status examples. |
| F07 | Array contains claimed case-sensitive-only operation despite `--case-insensitive`; invert/no-match semantics were omitted. | Describe string-only comparisons, optional case folding, skipped missing/non-array keys even with invert, and nonzero no-match status. See `ArrayHelpers.containsValue` and `Contains.outputResults`. |
| F08 | `fm has` claimed unconditional success; touch lacked its TOML-null limit; raw dump claimed original source; delimiter wording ignored cat mode. | Explain has read/parse failures, null creation limits, raw reserialization and categorized versus cat output. Help now discloses list's early stop at a keyless file. Existing operational behavior is retained. |
| F09 | Wikilink conversion examples selected `notes/` outside `--root vault/`; scope/preference defaults and required mode selection were incomplete. | Use `vault/notes/`; explain exactly one of `--to`/`--type`, cwd-relative inputs, scope defaults, extension defaults, contract-only preferences, opt-in recommendations, no-op conformance preservation and separate whole-type assessment. |
| F10 | Backlink help did not distinguish target selection from source scanning. | Explain positional targets, always-recursive source scanning, hidden/symlink exclusions, self-link omission and existing aggregate multi-target behavior. Check help also distinguishes reporting from failure status. |
| F11 | Six index leaves had no descriptions; rebuild help promised general view preservation; shared index flags obscured scope persistence and inspection side effects. | Add field/FTS leaf descriptions; describe fresh rebuild from saved configuration, managed projections and discarded history. Explain refresh-before-SQL, metadata-only versus opt-in FTS, persistent per-scope non-Markdown selection, and cache initialization during inspection. `IndexOptions.context/run` and each leaf are authoritative. |
| F12 | SQL format descriptions omitted JSONL column-name and NUL shape constraints; template data/schema descriptions looked like inline values. | Document unique JSONL columns and one text column for NUL (query plans cannot satisfy it). Label template input/schema as file paths, matching bounded file reads. |
| F13 | Creation help did not explain required mutually exclusive input/filename forms or advisory conformance. Config bootstrap/migration and relationship leaves lacked key scope/default guidance; related guidance implied every live direction refreshed an index. | Share creation requirements across types/rules new; add config version/migration constraints and relationship selection, presentation, completeness and SQLite-only semantics. Distinguish source-directed outgoing reads from incoming/both index refresh. No creation/selection behavior changes. |
| F14 | README/skill usage had nonexistent `--query`, `--vault`, `--target`, `--old-key`, `section set --content`, `sort-keys --in-place`, singular touch keys, and promotion without an index. | Correct README, common use cases, DocC and skill references to accepted syntax. Clarify `fm set` strings, `fm has` stdout predicates, supported frontmatter formats, TOC defaults, raw serialization and command-specific batching. Keep canonical/bundled SKILL.md identical. |
| F15 | Replace's leading-hyphen example used a sequence that the mapping-only parser rejects; raw YAML input alias was omitted. | Explain mapping requirement and `--data=` quoting without presenting a rejected sequence as a successful example; document raw as YAML input. |
| F16 | `to-text --in-place` implied replacing Markdown, though it writes sibling `.txt` files; CSV wording was YAML-specific. | Describe retained originals, possible `.txt` overwrite, flat batch basenames, YAML/TOML values, and CSV defaults in the working directory. |
| F17 | No standing pre-commit help check for edited async commands. | Added the requested procedure to `AGENTS.md`: view actual executable help after editing any `AsyncParsableCommand`, including affected group/shared help, and record verification. |
| F18 | Types check/verify/identify omitted accepted Markdown/TOML output; visibility flags did not distinguish human and structured output. | Document all accepted formats (Markdown uses text-style rendering here), check's text-only include-ok/no-advisories, and rule validation's text-only include-ok. `TypesRenderer` and `Validate.run` preserve complete structured evidence. |

## Page inventory

Each row represents one captured and reviewed canonical help page. Aliases are
relative to the same parent; parent aliases compose normally (for example
`fm array contains`, `ln bl`, `rel out`, `sect ls`). `CLIHelpTests` requires this
table to match every registered command and listed alias.

| Command | Aliases | Findings |
| --- | --- | --- |
| `md-utils` | — | F01 |
| `md-utils agents` | — | — |
| `md-utils agents skill` | — | F14 |
| `md-utils agents install` | — | — |
| `md-utils agents printConfigSchema` | — | — |
| `md-utils body` | `b` | F02, F05 |
| `md-utils config` | — | — |
| `md-utils config init` | — | F13 |
| `md-utils config schema` | — | — |
| `md-utils config info` | — | — |
| `md-utils config migrate` | — | F13 |
| `md-utils convert` | — | F03 |
| `md-utils convert to-text` | — | F02, F05, F16 |
| `md-utils convert to-csv` | — | F02, F16 |
| `md-utils explore` | — | — |
| `md-utils extract` | — | F02 |
| `md-utils meta` | — | — |
| `md-utils meta read` | — | F02, F05 |
| `md-utils format` | — | F02, F05 |
| `md-utils frontmatter` | `fm` | F01 |
| `md-utils frontmatter array` | — | F07 |
| `md-utils frontmatter array init` | — | F02 |
| `md-utils frontmatter array clear` | — | F02 |
| `md-utils frontmatter array contains` | — | F02, F07 |
| `md-utils frontmatter array append` | — | F02 |
| `md-utils frontmatter array prepend` | — | F02 |
| `md-utils frontmatter array remove` | — | F02 |
| `md-utils frontmatter dump` | `d` | F02, F05, F08 |
| `md-utils frontmatter get` | — | F02 |
| `md-utils frontmatter has` | — | F02, F08 |
| `md-utils frontmatter list` | `ls` | F02, F08 |
| `md-utils frontmatter remove` | `rm` | F02 |
| `md-utils frontmatter remove-frontmatter` | `rmfm` | F02 |
| `md-utils frontmatter rename` | `rn` | F02 |
| `md-utils frontmatter replace` | `r` | F02, F05, F15 |
| `md-utils frontmatter search` | — | F05, F06 |
| `md-utils frontmatter set` | — | F02 |
| `md-utils frontmatter sort-keys` | `sk` | F02 |
| `md-utils frontmatter touch` | — | F02, F08 |
| `md-utils frontmatter unique` | — | F02 |
| `md-utils table-of-contents` | `toc` | F02, F03, F05 |
| `md-utils headings` | — | — |
| `md-utils headings promote` | — | F02 |
| `md-utils headings demote` | — | F02 |
| `md-utils index` | — | F11 |
| `md-utils index update` | — | F11 |
| `md-utils index watch` | — | F11 |
| `md-utils index type` | — | F11 |
| `md-utils index rule` | — | F11 |
| `md-utils index query` | — | F11, F12 |
| `md-utils index explain` | — | F11, F12 |
| `md-utils index field` | — | F11 |
| `md-utils index field add` | — | F11 |
| `md-utils index field remove` | — | F11 |
| `md-utils index field list` | — | F11 |
| `md-utils index search` | — | F11 |
| `md-utils index search enable` | — | F11 |
| `md-utils index search disable` | — | F11 |
| `md-utils index search status` | — | F11 |
| `md-utils index status` | — | F11 |
| `md-utils index provenance` | — | F11 |
| `md-utils index draft` | — | — |
| `md-utils index draft add` | — | — |
| `md-utils index draft list` | — | — |
| `md-utils index draft show` | — | — |
| `md-utils index draft discard` | — | — |
| `md-utils index draft resolve` | — | — |
| `md-utils index apply` | — | — |
| `md-utils links` | `ln` | F01, F09 |
| `md-utils links list` | `ls` | F02 |
| `md-utils links check` | — | F02, F10 |
| `md-utils links backlinks` | `bl` | F02, F10 |
| `md-utils links convert` | — | F02, F09 |
| `md-utils lines` | `l` | — |
| `md-utils okf` | — | — |
| `md-utils okf init` | — | — |
| `md-utils okf validate` | — | — |
| `md-utils okf report` | — | — |
| `md-utils okf doctor` | — | — |
| `md-utils okf type` | — | — |
| `md-utils okf type set` | — | — |
| `md-utils rules` | — | — |
| `md-utils rules add` | — | — |
| `md-utils rules interactive` | — | — |
| `md-utils rules remove` | — | — |
| `md-utils rules list` | — | — |
| `md-utils rules files-matching` | — | — |
| `md-utils rules matching` | — | — |
| `md-utils rules describe` | — | — |
| `md-utils rules validate` | — | F18 |
| `md-utils rules fix` | — | — |
| `md-utils rules new` | — | F13 |
| `md-utils relationships` | `rel` | F13 |
| `md-utils relationships outgoing` | `out` | F13 |
| `md-utils relationships incoming` | `in` | F13 |
| `md-utils relationships both` | — | F13 |
| `md-utils section` | `sect` | F13 |
| `md-utils section list` | `ls` | F02, F03, F04, F05 |
| `md-utils section get` | — | F02 |
| `md-utils section set` | — | F02 |
| `md-utils section insert` | — | — |
| `md-utils section remove` | — | — |
| `md-utils section move-up` | — | F02, F05 |
| `md-utils section move-down` | — | F02, F05 |
| `md-utils section move-to` | — | F02 |
| `md-utils slug` | — | F05 |
| `md-utils template` | — | — |
| `md-utils template render` | — | F12 |
| `md-utils types` | — | — |
| `md-utils types add` | — | F13 |
| `md-utils types interactive` | — | — |
| `md-utils types list` | — | — |
| `md-utils types describe` | — | — |
| `md-utils types doctor` | — | — |
| `md-utils types check` | — | F02, F18 |
| `md-utils types verify` | — | F02, F18 |
| `md-utils types identify` | — | F02, F18 |
| `md-utils types find` | — | F02 |
| `md-utils types fix` | — | F02 |
| `md-utils types schema` | — | F13 |
| `md-utils types new` | — | F13 |
| `md-utils copy` | — | — |
| `md-utils move` | — | — |

## Verification

Native validation completed successfully:

- `swift build --disable-automatic-resolution` passed.
- `swift test --disable-automatic-resolution` passed: **1,881 tests across 181
  suites** in eight test products, including all three new help tests (nine
  executable help cases in the parameterized test).
- After the final relationship help/skill wording update,
  `swift test --disable-automatic-resolution --filter 'CLIHelpTests|AgentCommandsTests'`
  passed all **6 tests in 2 suites**, including skill synchronization.
- Final executable traversal captured **123 help pages and verified 19 aliases**;
  root's built-in `help` route and updated shared/parent help were also viewed.
- **82 executable examples and edge cases** passed in isolated fixtures,
  covering positional and quoted JMESPath, all search output formats/refusals,
  no matches, hidden recursion, spaces, mapped files, missing keys, string/null
  mutation, raw/cat dumps, actual TOC defaults, section syntax, converter output
  destinations, ad hoc and #185 contract preview/application, relationship
  selection, metadata, SQL formats/refusals, FTS, rebuild, template input files,
  contract version selection and complete structured type/rule evidence.
- `git diff --check` and byte comparison of canonical/bundled SKILL.md passed.
  `Package.resolved` has no diff. Existing compiler warnings in unrelated tests
  remain unchanged.

Reproduce with `swift build`, `swift test` and
`.build/debug/md-utils <command> --help`.
`CLIHelpTests` checks the complete registration inventory, descriptions and
aliases, root discoverability and focused executable help regressions. Existing
command suites supply broader behavior, frontmatter, conversion, indexing and
skill synchronization coverage.

## Remaining limits

- Local Linux validation is CI-only. Local WASM build/smoke verification is
  deferred under `AGENTS.md`; neither is claimed as passed. No tools were installed
  and `Package.resolved` was not manually edited.
- Preserve existing search behavior: no matches yield empty stdout even with
  structured formats; per-file JMESPath evaluation errors are skipped. Search
  scans hidden descendants and does not accept shared traversal flags.
- Preserve existing `fm list` early return on keyless files and aggregate
  multi-target backlink matches. Help now describes these limits; changing their
  behavior requires separate work. Query backlinks one target at a time.
- `types add` has a local `--version <version>` option and also inherits a
  generated `--version` flag line. The discussion explains the local contract
  version and points to root `md-utils --version` for CLI version. Removing this
  parser-generated duplication would require changing argument configuration.
- Human line-based pipelines preserve spaces with quoted read loops, but cannot
  represent embedded newline filenames; use structured search output and a
  suitable consumer when necessary. This audit does not add new output modes.
- This is help/usage verification, not a new exhaustive behavioral or security
  audit of every existing command. Unrelated runtime defects and new features
  remain outside issue #187's scope.
