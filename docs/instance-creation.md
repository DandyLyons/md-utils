# Creating type and rule instances

`types new` and `rules new` render one Knap template into a new file. They create
starting documents: type and rule nonconformance is reported as advisory and does
not prevent saving or cause a failing exit status. Invalid template input,
rendering failures, unsafe filenames, collisions, and write errors do fail.

## Declare a template

Add this optional declaration to an mdtype under `.md-utils/types/`:

```yaml
creation:
  template:
    ref: ./book.knap
    mode: document
    inputSchema:
      inline:
        type: object
        properties:
          title:
            type: string
            default: Untitled
```

Use `inline: "{{ title | h1 }}"` instead of `ref` for template source in the
definition. `inputSchema` likewise accepts exactly one `inline` schema (object or
boolean) or `ref` to a schema file. References resolve relative to the mdtype
definition and stay inside the project. A template file is UTF-8 text.

Document mode is the default. Input must be a JSON object. Its properties become
Knap variables directly, following upstream Knap; arrays/scalars belong under
named properties. No host variables or implicit root wrapper are added.

```text
---
{{ title | yaml_property:'title' }}
---
{{ title | h1 }}
```

Knap owns all template syntax. Use its YAML serialization filters for generated
frontmatter. Templated TOML is discouraged because Knap has no TOML serializer.
Explicit `mode: body` uses the separate `{ "frontmatter": {}, "data": ... }`
envelope: md-utils serializes YAML frontmatter and Knap renders only the body.

## Choose a destination and filename

```bash
md-utils types new --type Book --value ./dune.json --filename Dune.md ./Books/
md-utils types new --type Book --value ./dune.json --filename-data '$.title' ./Books/
md-utils types new --type Book --value ./dune.json --filename-data '$.title' --extension txt ./Books/
md-utils types new --type Book --value ./dune.json --filename-data '$.title' --extension '' ./Books/
```

`types new` requires an existing destination directory. `--root` chooses the
definition project and defaults to the current directory; it does not search
parents. Explicit destinations outside that root are permitted, but project-relative
path constraints have no available path and may report nonconformance.

Supply exactly one filename option. `--filename` is an exact filename with any
extension or none. `--filename-data` evaluates RFC 9535 JSONPath after defaults
and must select exactly one string stem. The default suffix is `.md`; an explicit
`--extension` changes it or an empty string omits it. A stem already ending in
`.md` gets another `.md`; there is no extension guessing. `--extension` cannot
accompany `--filename`. Names retain spaces, Unicode, and supported punctuation;
unsafe names are rejected, never silently slugified. Content is assessed as
Markdown even when its filename has another extension or no extension.

## Create through a rule

In a standalone `.mdrule.json` file, add:

```json
"creation": { "type": "Book", "directory": "./Books/" }
```

The directory is required and relative to the selected project root. No glob
destination inference occurs. `creation.type` names a type referenced by the rule
and is required when more than one type is referenced. A single type is inferred.

```bash
md-utils rules new --rule Books --value ./dune.json --filename-data '$.title'
md-utils rules new --rule Books --value ./dune.json --filename Dune.md --dry-run
```

The default config is `.md-utils/md-utils.json`. For standard config locations,
the project root is the directory holding `.md-utils/`; nonstandard locations
require `--project-root`. Use `--config` to select a different config.

## Defaults, validation, and persistence

Creation input schemas insert missing defaults automatically, then validate the
effective input. Invalid defaults are inserted and reported as schema violations.
Existing validation commands do not insert defaults. Explicit null, false, zero,
and empty strings are preserved. Missing parent objects stay absent unless the
parent declares a default (such as `{}`). Existing array elements receive
defaults; entries are not manufactured. Conflicting defaults and ambiguous schema
alternatives fail with diagnostics. Recursive expansion has finite work/depth
limits. Local JSON Pointer schema references are supported by default expansion.

The CLI separately labels template input validation, type frontmatter/body/context
diagnostics, and rule outcomes. A created instance may fail conformance; repair it
and use dedicated validation commands when conformance is required.

`--dry-run` renders and assesses without persistent writes. Directories must exist.
Creation publishes complete bytes atomically without overwriting, including if
another writer claims the name after preflight. Existing files remain intact.
Server reuse of mdtype templates is a future
opportunity; existing server mutation authorization/validation still applies.

## Bulk creation

Use `--values` for a nonempty JSON array of input objects, or repeat `--value-file`
for individual JSON object files. These options and single-instance `--value` are
mutually exclusive. An array passed to `--value` is rejected, never treated as a batch.

```json
[
  { "title": "Dune", "author": "Frank Herbert" },
  { "title": "Foundation", "author": "Isaac Asimov" }
]
```

```bash
md-utils types new --type Book --values ./books.json --filename-data '$.title' ./Books/
md-utils rules new --rule Books --value-file ./dune.json --value-file ./foundation.json --filename-data '$.title'
```

With the template above, these create `./Books/Dune.md` and `./Books/Foundation.md`,
each containing its title as YAML frontmatter and a level-one heading. Each item
uses the same template and independently receives schema defaults and validation.
Bulk requires `--filename-data`, evaluated after defaults; `--filename` is rejected.
The same extension options apply, including `--extension ''` for no extension.
Destination directories must already exist.

Array items are identified by source path and zero-based index (`./books.json[0]`).
File inputs include the path and one-based argument position, distinguishing repeated
paths. Processing and reports follow input order. Limits are 10,000 items, 64 MiB
aggregate input bytes, and 64 MiB aggregate rendered UTF-8 output. These bounds keep
preflight in memory without temporary staging files; exceeding them blocks creation.

The whole request is preflighted before writing. Independent input, defaults, schema,
rendering, filename, and destination failures are collected. Stages depending on
failed input are skipped. Duplicate destinations report all participants; existing
files are never overwritten or silently renamed. Type and rule conformance remain
advisory. `--dry-run` uses the same preflight without persistent side effects.

```text
Creation failed; no files were written.
- ./books.json[0] -> /project/Books/Dune.md: Destination already exists: /project/Books/Dune.md
- ./books.json[0] -> /project/Books/Dune.md: Duplicate destination shared by 2 inputs.
- ./books.json[1] -> /project/Books/Dune.md: Destination already exists: /project/Books/Dune.md
- ./books.json[1] -> /project/Books/Dune.md: Duplicate destination shared by 2 inputs.
```

After successful preflight, files are published sequentially and atomically without
overwriting. If a writer claims a destination or another filesystem failure occurs,
publication stops. Every item is reported as `Created`, `failed`, or `not attempted`;
completed files remain. This is not a batch transaction and there is no rollback.
Successful creation and dry run return zero even with advisory nonconformance;
blocking failures and partial completion return nonzero. Dry-run results say
`Would create` and include separate type/rule diagnostics.
