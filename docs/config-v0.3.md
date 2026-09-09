# Config 0.3.0

Config 0.3.0 is opt-in. `config init` still creates 0.2.0; existing 0.1.0 and 0.2.0 projects keep their version-specific behavior. The `latest` schema alias remains 0.2.0 pending the format-wide release tracked in #135.

## Layout and authoring

`.md-utils/md-utils.json` contains project settings, not rules:

```json
{"configVersion":"0.3.0"}
```

Create `.md-utils/types/book.mdtype.json`:

```json
{
  "md-utils-type-schema": "1",
  "name": "Book",
  "version": "1.0.0",
  "frontmatter": {"presence": "required", "schemas": [{"inline": {"type": "object", "required": ["title"]}}]},
  "body": {"requirements": [], "recommendations": []},
  "context": {"requirements": [], "recommendations": []}
}
```

Then run `md-utils rules add books --type book.mdtype.json --path 'Books/**/*.md'` or write `.md-utils/rules/books.mdrule.json`:

```json
{
  "name": "books",
  "match": {"allOf": [{"paths": ["Books/**/*.md"]}, {"not": {"paths": ["Books/archive/**"]}}]},
  "types": "book.mdtype.json"
}
```

Rules are recursively discovered by `.mdrule.json` suffix, excluding `rules/legacy/`. Duplicate names and malformed files report source paths. Rule ordering has no semantic significance. `rules list --verbose`, `rules describe`, `rules validate`, `rules files-matching`, and `rules matching --explain` use these definitions. `rules remove` deletes only the selected rule, preserving shared types and schemas; `--delete-schema` is rejected in 0.3.0. Use `rules interactive` to author richer expressions through prompts or JSON expression input.

## Composition, references, and hints

Both `match` and `types` support recursive `allOf`, `anyOf`, `oneOf`, and `not`. A group has exactly one operator; arrays are nonempty. Type leaves require explicit `.mdtype.json`, `.mdtype.yaml`, `.mdtype.yml`, or `.mdtype.toml` filenames relative to `types/`. Nested paths are allowed; extension guessing, basename search, absolute paths, and traversal are not. Exact duplicate children in a type group are rejected. Match leaves retain existing flat semantics. Omitted or empty `match` selects every host candidate; CLI scans remain Markdown-only unless opted into other files.

Selection runs before type enforcement. Selected invalid records fail rather than disappear. All applicable rules must pass. `allOf` requires every branch, `anyOf` at least one, `oneOf` exactly one, and `not` ordinary nonconformance. Evaluation errors remain distinct from nonconformance: `not` cannot turn malformed input into a pass. A decisive ordinary failure in `allOf`, success in `anyOf`, or two successes in `oneOf` determines the result despite other evaluation errors. All definitions and resources compile before records are processed. Full branch evidence is retained; alternative repairs are not merged automatically.

Type filenames resolve to the definitions' declared names. Existing `$md-utils.typeHints` remain name-based, support optional versions, and never establish conformance without assessment. Malformed hints remain errors under mdtype v1.

`schemas/` is optional shared-resource storage. Types may embed schemas or use `{"ref":"../schemas/book.schema.json"}`. References are definition-relative; nested schema references are schema-relative, confined to the project. There is no project `schemaDirectory` in 0.3.0.

The shared loader derives the project root from `<project>/.md-utils/md-utils.json`, not the working directory. Rule commands accept `--config` and `--project-root`; a nonstandard config location requires the latter. Normal commands still default to the current directory's config.

## Interactive authoring

```bash
md-utils types interactive
md-utils rules interactive
md-utils types interactive --name book
md-utils rules interactive --edit books
md-utils rules interactive --config /path/to/project/.md-utils/md-utils.json
md-utils types interactive --config /path/to/custom.json --project-root /path/to/project/
```

Both commands require an existing 0.3.0 config and offer Create, Edit, and Remove.
They use the same config selection and root resolution as other standalone rule
commands. Select resources by exact declared name; new filenames are entered
separately, relative to `types/` or `rules/`, including the resource suffix.
Nested paths are supported. Editing or renaming a resource retains its original
source file. Type edits retain JSON, YAML, or TOML format and existing constraint
and schema associations; edited files may be reformatted and comments are not retained.
Unrelated files remain byte-for-byte unchanged.

The shared type editor supports contract names and versions, frontmatter presence,
existing schema references, and required or recommended heading, heading-relationship,
section, body-count, and context-path constraints. Each constraint has a unique ID.
Existing inline schemas are preserved; the editor manages schema associations,
not schema contents. Schema references are relative to the containing type file:
`../schemas/book.schema.json` for a root-level type, or
`../../schemas/book.schema.json` for a type one directory deeper.

Rule authoring supports recursive `allOf`, `anyOf`, `oneOf`, and `not` type and
match expressions. Matcher leaves combine paths, exclusions, file metadata,
frontmatter predicates, JMESPath queries, and document predicates. Prompts explain
JSON values for structured matcher operands. Existing expressions and the optional
rule `$schema` remain intact until explicitly changed. In 0.3.0, checks belong to
types; rules associate type expressions rather than embedding legacy `checks`.
Choose **Create new type** while building a rule's type expression to enter the
same type editor and return to the rule. Both changes remain drafts.

No files are written while answering prompts. Choose **Cancel**, enter `:cancel`
at a text prompt, or interrupt before confirmation to discard the session.
The complete proposed project is decoded and compiled, including referenced types,
schema resources, all expression branches, and constraint IDs, before displaying
every affected file and asking for confirmation (default: No). Invalid definitions
report diagnostics and return to the editor. Removing a referenced type is refused;
remove or update its rules first. Removing a rule preserves its types and schemas.

Each confirmed file write or removal is atomic. Saving multiple resources is not
a transaction: types are written before their rules, and an I/O failure reports
completed resources for inspection before retrying. Declining confirmation leaves
the project unchanged, including any type drafted inside rule authoring.

JSON Schema authoring remains external. Use `sourcemeta/jsonschema`, `ajv-cli`,
`check-jsonschema`, or `swaggest/json-cli` to author and validate schemas, then enter
an existing schema reference in the type editor. There is no `schema interactive`
command.

## Migration and recovery

Back up the entire `.md-utils/` directory first:

```sh
md-utils config migrate --to 0.3.0 --dry-run
md-utils config migrate --to 0.3.0
```

Use `--config` for another config file and `--project-root` for a nonstandard location. The supported automatic subset is rules containing one or more required frontmatter-schema checks; generated types use contract version `1.0.0` and preserve rule names. Schema references are rewritten to the same resolved resource. Body checks and optional-schema conversions currently require manual remediation; they are refused before writes because a general outcome-preserving conversion has not been established. Empty projects can also migrate.

Preview lists destination files and warnings. Migration preserves the original config bytes as `md-utils.legacy-<source-version>.json` and original rule values under `rules/legacy/`. Generated types and active rules are written before replacing the active config. Conflicting files and unsafe resources are rejected during preflight; identical artifacts may be reused after verification.

The approved semantic exception is that migrated rules newly reject malformed `$md-utils.typeHints`. Correct malformed hint metadata; valid hints retain support. Diagnostics, locations, wording and fix-it proposals may change to mdtype diagnostics. All other selection/pass/fail/skipped guarantees remain in force.

There is no staging directory, manifest, or multi-file atomicity guarantee. An interrupted migration can leave generated files alongside the still-active legacy config. The failure reports completed writes. Restore the backup, or inspect those files and retry; do not delete legacy copies as part of recovery. Repeated attempts verify artifacts and refuse conflicting contents. An already-current config is a no-op.

The project and rule schemas are bundled and published at `schemas/0.3.0/md-utils.schema.json` and `schemas/0.3.0/mdrule.schema.json`. See [RFC 0002](rfcs/0002-config-v0.3.md) for the full contract.
