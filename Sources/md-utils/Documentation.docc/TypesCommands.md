# Markdown Type Commands

Create, inspect, assess, identify, verify, and repair typed Markdown records.

`types check` assesses named mdtype v2 relationships with the project's collection
context. Use `relationships` (alias `rel`) to query declaration-scoped occurrences:
`outgoing` (`out`), `incoming` (`in`), or `both`, with explicit `--root ./vault/`,
optional declaring-contract override `--type`, `--relation` (requiring `--type`),
and `--json` or `--yaml`. All formats use `--detail summary|explain|evidence`, defaulting
to concise triples and ordinary links. Files, folders, structural types, rule
applicability, YAML tags, JMESPath and LF/NUL file lists can select documents.
Multiple selectors require explicit union/intersection. Incoming discovery remains
root-wide. Complete queries exit 0; incomplete queries exit 1 with available results.
Self-links have a separate
section. Ordinary outgoing queries use source-directed reads without whole-index
refresh; incoming/both refresh an existing compatible index. `--no-index`,
`--indexed-only` (`--index-only`)
and `--verify-hashes` follow the documented live-query or SQLite-only contracts.
The two index-only spellings read published evidence without raw-file reads,
refresh or fallback and reject `--no-index`/`--verify-hashes`. Missing snapshot
evidence remains unavailable. Domain truth remains the
user's responsibility; validation checks explicit structural assertions.

## Create instances

`types new --type Book --value ./dune.json --filename-data '$.title' ./Books/`
uses the type's `creation.template` and an existing caller-selected directory.
Document mode is default; templates own frontmatter and body. `--dry-run` previews
without saving. Input-schema violations block creation; type nonconformance is
reported as advisory and the starting document is still saved. `--filename` gives
an exact name; `--filename-data` uses JSONPath after defaults and appends `.md`
unless `--extension` changes or omits it. Existing destinations are never replaced.

## Definitions

Project definitions are YAML, JSON, or TOML files under `.md-utils/types/`. Definition filenames must end in `.mdtype.yaml`, `.mdtype.yml`, `.mdtype.json`, or `.mdtype.toml`. Other structured-data files in the directory are ignored. Add a definition scaffold with:

```bash
md-utils types add Book --version 1.0.0
md-utils types add Publishable --version draft-3 --format json
md-utils types add Article --version 1.0.0 --format toml
```

These commands create `.md-utils/types/` when needed and use the compound extension matching the selected format. The declared `name` inside each definition remains the stable type identity; the filename only identifies the file as a Markdown type definition.

Use `types list`, `types describe Book`, and `types doctor` to inspect compiled definitions. `types schema` prints the JSON Schema for definition format version `1`.
Use `types schema --schema-version 2` for semantic strings and explicitly gated
wikilink constraints/relationships. New definition scaffolds still default to v1.

## Assessment and Queries

`types check` assesses records against one named type. `types identify` evaluates every loaded type, and `types find` prints only records that fully conform. Context predicates may narrow candidates, but a path match never substitutes for complete assessment.

Check, identify and verify accept `--format text|markdown|json|yaml|toml`; markdown
uses the text-style renderer for these commands. On `types check`, `--include-ok`
and `--no-advisories` affect text/markdown only; structured output always retains
all results and advisories. `rules validate --include-ok` similarly controls
text visibility while JSON/YAML retain complete evidence.

```bash
md-utils types check Book books/
md-utils types identify books/dune.md --all-assessments
md-utils types find Book books/
```

`types verify` validates claims in `$md-utils.typeHints`. A hint is confirmed only after full assessment; unknown, unavailable-version, and rejected claims fail verification.

```bash
md-utils types verify books/ --include-confirmed
```

## Fixing Records

`types fix` previews structured fix-its, applies only accepted edits, writes atomically, and reassesses each record.

```bash
md-utils types fix Book books/dune.md
md-utils types fix Book books/ --dry-run
md-utils types fix Book books/dune.md --yes --set title=Dune
```

`--yes` accepts deterministic fixes. It never invents values and skips input-required suggestions unless every requested value is supplied explicitly with `--set`. Use `--constraint` to limit changes to one stable constraint identifier. Recommendations are excluded unless `--include-recommendations` is present. A record that remains nonconforming produces a failing exit status.
