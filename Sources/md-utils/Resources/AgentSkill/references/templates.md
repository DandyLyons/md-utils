# Templates and file creation with Knap

Use this guide to create Markdown files that follow a project's conventions,
including the destination folder, frontmatter and body structure. md-utils
already includes [Knap](https://knap.md/) through SwiftKnap; no separate Knap
installation is required.

Contents: [choose a command](#choose-a-command), [complete walkthrough](#complete-walkthrough),
[common syntax](#common-knap-syntax), [other scenarios](#other-scenarios),
[failures and limits](#failures-and-limits). For the full expression, logic and
filter reference, read [Knap syntax](knap-syntax.md).

## Choose a command

| Need | Command | Where the template and destination come from |
| --- | --- | --- |
| Create according to a rule, in its configured folder | `rules new` | The rule selects a type and directory; the type supplies the template. |
| Create an instance of a type in a caller-selected folder | `types new` | The type supplies the template; you supply an existing directory. |
| Render a standalone template without type/rule setup | `template render` | You supply the template, JSON and optional output path. |

A **schema** constrains frontmatter values. A **type** combines frontmatter,
body and context requirements and may declare a creation template. A **rule**
selects documents, requires type conformance and may declare a creation directory.
A **template** produces the starting contents; it does not replace validation.
Creation reports type/rule nonconformance as advisory and may still save the file.

For an existing project, run from its root and inspect `.md-utils/md-utils.json`,
`md-utils types list`, `md-utils rules list`, and representative documents first.
Reuse existing conventions and definitions. Rule commands do not search parent
directories. Do not replace a config or migrate a legacy project silently; read
[Rules](rules.md) for the version boundary. `config init` currently defaults to
0.2.0, whereas the standalone rule workflow below uses 0.3.0.

## Complete walkthrough

Scenario: create book notes under `Books/`, with typed frontmatter, a title,
a nonempty Synopsis and a Review section. The following files form a complete
new example project. File names, declared names and relative references have
different roles; retain the spelling shown.

```text
book-notes/
  .md-utils/
    md-utils.json
    rules/
      books.mdrule.json
    types/
      book.mdtype.yaml
      book.knap
  inputs/
    dune.json
  Books/
```

Create the directories from the new project's root:

```sh
# Prepare the definition, input and output folders; creation requires an existing destination.
mkdir -p .md-utils/types/ .md-utils/rules/ inputs/ Books/
```

### 1. Enable standalone rules

Save `.md-utils/md-utils.json` in this new example project:

```json
{"configVersion":"0.3.0"}
```

### 2. Define the Book type and its template input

Save `.md-utils/types/book.mdtype.yaml`:

```yaml
md-utils-type-schema: "1"
name: Book
version: "1.0.0"
frontmatter:
  presence: required
  schemas:
    - inline:
        type: object
        required: [kind, title, author, tags]
        properties:
          kind: {const: book}
          title: {type: string, minLength: 1}
          author: {type: string, minLength: 1}
          tags: {type: array, items: {type: string}}
body:
  requirements:
    - id: synopsis
      section:
        heading: {text: Synopsis, level: 2}
        content: nonEmpty
    - id: review
      section:
        heading: {text: Review, level: 2}
        content: nonEmpty
  recommendations: []
context:
  requirements:
    - id: book-location
      path: {glob: "Books/**/*.md"}
  recommendations: []
creation:
  template:
    ref: ./book.knap
    mode: document
    inputSchema:
      inline:
        type: object
        required: [title, author, synopsis]
        properties:
          title: {type: string, minLength: 1}
          author: {type: string, minLength: 1}
          synopsis: {type: string, minLength: 1}
          review: {type: string, minLength: 1, default: Not reviewed yet.}
          tags: {type: array, items: {type: string}, default: []}
```

The two schemas serve different purposes: `creation.template.inputSchema`
validates JSON **before rendering**, while `frontmatter.schemas` assesses the
**generated document's metadata**. Input defaults fill missing values; validation
of existing documents does not add defaults. The template supplies `kind: book`,
so callers do not have to provide it. See [Types](types.md) for other constraints.

### 3. Write the Knap document template

Save `.md-utils/types/book.knap` as UTF-8 with LF line endings:

```knap
---
kind: book
{{ title | yaml_property:"title" }}
{{ author | yaml_property:"author" }}
{{ tags | yaml_property:"tags" }}
---
{{ title | h1 }}

## Synopsis

{{ synopsis }}

## Review

{{ review }}
```

`document` is the default mode: input object properties are named Knap variables,
so `{"title":"Dune"}` is accessed as `{{ title }}`, without an implicit `data`
wrapper. The template renders the whole file. Use `yaml_property` for complete
metadata entries so quotes, colons, arrays and string-like booleans stay valid
YAML. Do not write `title: {{ title }}` for arbitrary input. Template references
resolve relative to the type definition, not the working directory, and must
remain within the project. `inline` can replace `ref` for a small template.

### 4. Define the books rule and destination

Save `.md-utils/rules/books.mdrule.json`:

```json
{
  "name": "books",
  "match": {"paths": ["Books/**/*.md"]},
  "types": "book.mdtype.yaml",
  "creation": {"type": "Book", "directory": "./Books/"}
}
```

`types` references a **filename relative to `.md-utils/types/`**.
`creation.type` is the **declared type name**; `--rule books` is the **rule name**.
A single referenced type can be inferred if `creation.type` is omitted; several
types require an explicit choice. `creation.directory` is relative to the
project root, must stay inside it, and must already exist. It is required:
md-utils does not infer a destination from `match.paths`.

Keep the rule's selector, type context and creation directory aligned. A
destination alone does not guarantee that the output matches the rule. Rules
using metadata or heading selection also need those values in the generated file.

### 5. Supply JSON

Save `inputs/dune.json`:

```json
{
  "title": "Dune",
  "author": "Frank Herbert",
  "synopsis": "A young heir arrives on Arrakis.",
  "tags": ["fiction", "science-fiction"]
}
```

`review` is absent, so the creation input schema inserts its default. Explicit
null, false, zero and empty strings are preserved rather than replaced; they
must still satisfy the input schema. Arrays/scalars at the JSON root are rejected
for single creation; put them under a named property.

### 6. Check definitions, preview, create and validate

Run from the example project root:

```sh
# Check definitions, then render and assess without saving a document.
md-utils types doctor
md-utils rules describe books
md-utils rules new --rule books --value ./inputs/dune.json --filename-data '$.title' --dry-run

# Create without overwriting, then validate current source files.
md-utils rules new --rule books --value ./inputs/dune.json --filename-data '$.title'
md-utils types check Book ./Books/Dune.md
md-utils rules validate --no-index
```

The dry run reports the proposed path and type/rule assessments; it does not
print the full document. To inspect rendered Markdown before saving, run
`template render` as described below, with the same effective input/defaults.
The created `Books/Dune.md` contains these values and sections (YAML quoting and
layout are owned by the serializer):

```markdown
---
kind: book
title: Dune
author: Frank Herbert
tags:
  - fiction
  - science-fiction
---
# Dune

## Synopsis

A young heir arrives on Arrakis.

## Review

Not reviewed yet.
```

A zero exit from creation alone does not establish conformance. Review **both**
type and rule outcomes and warnings, then validate the written files.
`rules validate --no-index` checks the project's selected documents, including
other files; existing unrelated failures can also make it fail.

## Common Knap syntax

Knap is ordinary Markdown with output expressions and control tags. These are
the most common patterns; see [the full cheatsheet](knap-syntax.md) for operators,
scope, loops, serialization, filter families and compatibility limits.

| Task | Template fragment |
| --- | --- |
| Insert a variable or nested field | `{{ title }}`, `{{ author.name }}`, `{{ authors[0].name }}` |
| Transform text | `{{ title \| trim \| upper }}` |
| Render a heading | `{{ title \| h1 }}` |
| Safely write a YAML entry | `{{ title \| yaml_property:"title" }}` |
| Render an array as a list | `{{ tags \| list }}` |
| Render object rows as a table | `{{ rows \| table }}` |
| Optional content | `{% if summary %}{{ summary }}{% endif %}` |
| Repeat content | `{% for person in people %}{{ person.name }}{% endfor %}` |
| Presentation fallback | `{{ subtitle ?? "No subtitle" }}` |
| Author-only comment | `{# This is removed when rendered. #}` |

`??` uses truthiness: zero, false, empty strings and empty arrays also select the
fallback. Use input-schema defaults when a fallback should apply only to a
missing input. Input defaults and Knap presentation fallbacks are separate steps.

## Other scenarios

### Choose a filename or a different destination

```sh
# Exact filenames include their own suffix.
md-utils rules new --rule books --value ./inputs/dune.json --filename 'Dune - reading note.md' --dry-run

# A type alone lets the caller choose the existing destination folder.
md-utils types new --type Book --value ./inputs/dune.json --filename 'Dune - type preview.md' ./Books/ --dry-run
```

`--filename-data` is **JSONPath**, evaluated on input after defaults; it must
select exactly one string stem. `.md` is appended by default. Use a separate
input property such as `filename` when titles contain path separators, and select
`'$.filename'`. Template-local `set` variables and filters cannot change the CLI
filename: naming occurs on the JSON input. There is no automatic slugification.
`--extension txt` changes the suffix; `--extension ''` omits it. These apply only
to `--filename-data`. A stem already ending in `.md` receives another `.md`.

### Import several records into the same convention

Save `inputs/books.json`:

```json
[
  {"title":"Foundation","author":"Isaac Asimov","synopsis":"A plan spans centuries."},
  {"title":"The Dispossessed","author":"Ursula K. Le Guin","synopsis":"A physicist crosses between societies."}
]
```

```sh
# Preview the entire batch before creating any files.
md-utils rules new --rule books --values ./inputs/books.json --filename-data '$.title' --dry-run
md-utils rules new --rule books --values ./inputs/books.json --filename-data '$.title'
md-utils rules validate --no-index
```

Each object gets its own defaults, render and assessments. Alternatively, repeat
`--value-file ./inputs/one.json --value-file ./inputs/two.json`.
`--value`, `--values` and repeated `--value-file` are mutually exclusive.
Bulk creation requires `--filename-data`; duplicate destinations are failures.

### Render a report without creating a type or rule

Save `report.knap`:

```knap
{{ title | h1 }}

{% if summary %}
{{ summary | blockquote }}
{% endif %}

## Tasks

{{ tasks | list:task }}

## Metrics

{{ metrics | table }}
```

Save `report.json`:

```json
{
  "title": "Weekly review",
  "summary": "The import is ready for review.",
  "tasks": ["Check metadata", "Validate the notes"],
  "metrics": [{"metric":"Imported notes","count":12}]
}
```

```sh
# Inspect Markdown on stdout before choosing an output file.
md-utils template render --template ./report.knap --data ./report.json
md-utils template render --template ./report.knap --data ./report.json --output ./weekly-review.md
```

Here the input flag is `--data`; `rules new` and `types new` use `--value`.
`template render` does not load a type's creation input schema automatically;
use `--schema ./input.schema.json` for missing defaults and input validation.
It does not assess the result against project types/rules. Its `--output` accepts
`.md`/`.markdown` and **replaces existing files atomically**, whereas `new` refuses
overwrite. Omit `--output` for stdout. Warnings go to stderr.

### Let md-utils serialize frontmatter separately

Use explicit `body` mode for an input envelope containing `frontmatter` and `data`.
Save `meeting.json`:

```json
{
  "frontmatter": {"kind":"meeting","title":"Planning","attendees":["Ada","Lin"]},
  "data": {"decisions":["Keep the current schema"],"actions":["Review the template"]}
}
```

Save `meeting.knap` without frontmatter delimiters:

```knap
{{ frontmatter.title | h1 }}

## Decisions

{{ data.decisions | list }}

## Actions

{{ data.actions | list:task }}
```

```sh
# Body mode renders only the body and serializes the explicit frontmatter object as YAML.
md-utils template render --mode body --template ./meeting.knap --data ./meeting.json
```

An mdtype can also declare `creation.template.mode: body` and use this same
envelope with `rules new` or `types new`. Its input schema must validate the
envelope; filename JSONPath might be `'$.frontmatter.title'`. Body templates and
rendered bodies must not start with YAML/TOML delimiters. Omitted frontmatter
produces no block; `{}` produces an empty block; explicit null is rejected.

## Failures and limits

| Symptom | What to inspect |
| --- | --- |
| Unknown rule/type | Working directory, selected config, exact declared name, config version and resource suffixes. |
| Rule has no creation target | Add explicit `creation.directory`; align it with rule selection and type context. |
| Several possible types | Set `creation.type` to a declared name referenced by that rule. |
| Missing template/schema | Resolve `ref` from the type definition's folder; keep it project-confined. |
| Missing folder | Create the configured destination first; `new` does not create it. |
| Input schema error | Check required keys and kinds; defaults only fill missing values. |
| Wrong output/missing sections | Check variable paths, document/body mode and Knap diagnostics. Keep contract-required sections unconditional. |
| Invalid YAML or wrong scalar kind | Use `yaml`/`yaml_property`, or body mode; do not interpolate arbitrary raw values into YAML. |
| Creation succeeds but a rule fails or is not applicable | Inspect advisory findings, selection predicates, path requirements and all required type branches. |
| Collision or unsafe filename | Supply a unique single filename/stem; names cannot contain path separators or control characters. |

Single and bulk `new` preflight input, rendering, naming and destinations before
writing. Any preflight failure writes no files. Each publication is atomic and
never overwrites. A later write failure stops a batch, retains earlier creations
and reports created/failed/not-attempted items; there is no batch rollback.
Bulk limits are 10,000 items, 64 MiB aggregate input and 64 MiB rendered output.

Knap renders content; it does not fetch data, create folders or execute arbitrary
scripts. md-utils installs no custom filters or DOM/network/filesystem resolvers.
Templated TOML has no serialization filter; prefer YAML or body mode. Templates
are not rerun when editing existing documents. Native server creation uses
separate administrator-configured templates; it does not yet reuse mdtype creation
declarations. See [Mutations](mutations.md) for server and staged edit workflows.

For authoritative language details and experiments, use [knap.md](https://knap.md/),
[Variables](https://knap.md/variables), [Logic](https://knap.md/logic),
[Filters](https://knap.md/filters) and the [Playground](https://knap.md/playground).
The playground may run a newer Knap version; confirm templates with the installed
md-utils executable.
