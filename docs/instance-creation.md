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
Bulk creation is tracked in #168. Server reuse of mdtype templates is a future
opportunity; existing server mutation authorization/validation still applies.
