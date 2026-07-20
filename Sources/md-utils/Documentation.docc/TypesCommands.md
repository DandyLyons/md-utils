# Markdown Type Commands

Create, inspect, assess, identify, verify, and repair typed Markdown records.

## Definitions

Project definitions are YAML or JSON files under `.md-utils/types/`. Definition filenames must end in `.mdtype.yaml`, `.mdtype.yml`, or `.mdtype.json`. Other YAML and JSON files in the directory are ignored. Add a definition scaffold with:

```bash
md-utils types add Book --version 1.0.0
md-utils types add Publishable --version draft-3 --format json
```

These commands create `.md-utils/types/` when needed, then add `.md-utils/types/book.mdtype.yaml` and `.md-utils/types/publishable.mdtype.json`. The declared `name` inside each definition remains the stable type identity; the filename only identifies the file as a Markdown type definition.

Use `types list`, `types describe Book`, and `types doctor` to inspect compiled definitions. `types schema` prints the JSON Schema for definition format version `1`.

## Assessment and Queries

`types check` assesses records against one named type. `types identify` evaluates every loaded type, and `types find` prints only records that fully conform. Context predicates may narrow candidates, but a path match never substitutes for complete assessment.

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
