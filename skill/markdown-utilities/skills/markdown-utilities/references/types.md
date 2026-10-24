# Types: authoring Markdown contracts

Types assess structure across frontmatter, Markdown body, and host context.
Conformance is structural and nonexclusive: a document can satisfy multiple types.
[Rules](rules.md) select where contracts are required; [schemas](schemas.md)
constrain frontmatter values. A type name or hint alone proves nothing.

## Find and edit definitions

Definitions are discovered recursively under `.md-utils/types/` with suffixes
`.mdtype.yaml`, `.mdtype.yml`, `.mdtype.json`, or `.mdtype.toml`. Other files are
ignored. CLI type names are exact case-sensitive declared names, not filenames.
Only one loaded definition per name is allowed. Run from the project root or use
`--root <directory>/` on ordinary type commands; there is no parent search.

```bash
# Inspect definitions before editing; scaffold only a genuinely new type.
md-utils types list
md-utils types describe Book
md-utils types doctor
md-utils types add Book --version 1.0.0 --format yaml
md-utils types schema --schema-version 1
md-utils types schema --schema-version 2
```

`types add` creates a scaffold, defaults to v1/YAML and contract version `0.1.0`,
and refuses overwrite. `--output` chooses a filename with the matching suffix.
Edit an existing definition directly for unattended work. Preserve names, stable
constraint IDs, source paths, format, and unrelated fields unless changing them
is intended. Renames require checking rule filename references, relationship
bindings, creation type names, and document hints; they are not automatic rewrites.

The required envelope fields are `md-utils-type-schema`, `name`, `version`,
`frontmatter`, `body`, and `context`. The language version (`"1"` or `"2"`) is
independent of the opaque contract `version` string. SemVer is recommended for
contracts but not required. CLI releases and config versions are separate again.
Unknown language versions/fields and malformed resources fail registry loading.

## Complete v1 example

Save as `.md-utils/types/book.mdtype.yaml`:

```yaml
md-utils-type-schema: "1"
name: Book
version: "1.0.0"
frontmatter:
  presence: required
  schemas:
    - inline:
        type: object
        required: [kind, title]
        properties:
          kind: {const: book}
          title: {type: string, minLength: 1}
body:
  requirements:
    - id: book-title
      heading: {text: Book, level: 1}
    - id: synopsis
      section:
        heading: {text: Synopsis, level: 2}
        content: nonEmpty
  recommendations:
    - id: reviews
      heading: {text: Reviews, level: 2}
context:
  requirements:
    - id: book-location
      path: {glob: "Books/**/*.md"}
  recommendations: []
```

For example, a document at `Books/Dune.md` with `kind: book`, `title: Dune`,
`# Book`, and a `## Synopsis` containing text meets the required constraints.
Missing `## Reviews` is advisory. Type definitions do not select files: the context
path is a requirement that fails for an assessed document outside that location.

## Frontmatter contracts

Each `schemas` item contains exactly one `inline` object or nonempty `ref` path.
Use `ref: ../schemas/book.schema.json` from a root-level type, or
`../../schemas/book.schema.json` from a type nested one directory deeper. Every
required schema evaluates the same user frontmatter object, conjunctively.
References resolve from the definition, nested schema references from the schema,
and remain project-confined. See [schemas.md](schemas.md) for schema editing.

| Presence setting | Result |
| --- | --- |
| `required` | A physical frontmatter block is required. |
| `optional` | Absence passes and schemas are skipped; present frontmatter is validated. |
| Omitted, required schemas nonempty | Frontmatter is implicitly required. |
| Omitted, no required schemas | No frontmatter presence obligation. |

In explicit v2, `frontmatter.recommendedSchemas` uses the same resource form but
produces advisories. Recommendations alone do not require a frontmatter block;
invalid declarations/resources still fail loading. The reserved `$md-utils`
metadata is removed before schema assessment. Malformed hints or frontmatter
remain errors. YAML/TOML values retain their kinds; quote strings resembling dates
or other native values. TOML cannot represent null.

## Body and context predicates

Both groups require `requirements` and `recommendations` arrays, even if empty.
Each constraint has one nonempty `id` and exactly one predicate. IDs must be
unique across all four arrays in a type. Failed requirements are errors;
recommendations are advisories. Parse errors remain errors regardless of severity.

| Predicate | Value and semantics |
| --- | --- |
| `heading` | `{text: Synopsis, level: 2}`; rendered text, exact and case-sensitive. Optional level is 1–6; omission allows any level. |
| `headingRelationship` | `{parent: {text: Book, level: 1}, child: {text: Synopsis}, relationship: directChild}`; also supports `descendant`. Heading order/levels determine ancestry. Any matching pair suffices. |
| `section` | `{heading: {text: Synopsis, level: 2}, content: nonEmpty}`; `any` is the default. `nonEmpty` requires direct non-whitespace content before the next heading, not just descendant subsections. |
| `maxBodyLines` | Nonnegative integer; raw LF-separated components after frontmatter. Empty body is zero; a nonempty body ending in LF includes its final empty component. |
| `maxBodyWords` | Nonnegative integer; raw whitespace-separated tokens, including Markdown markup. |
| `path` (context only) | `{glob: "Books/**/*.md"}`; whole, case-sensitive collection-relative logical path. Missing path fails rather than skips. |

Context paths use `/`, have no leading slash or directory suffix, and reject
empty/`.`/`..` segments and backslashes after removing one leading `./`.
Globs support `*` (not `/`), `?` (one non-`/` character), `**` (including `/`),
and `**/` (zero or more complete segments). Other characters are literal; do not
assume brace expansion or character classes. These body predicates inspect
Markdown structure; mapped non-Markdown files do not support heading/section checks.

## Explicit v2 capabilities

Switch `md-utils-type-schema` deliberately to `"2"` when using semantic string
formats or schema recommendations. Defaults remain v1; there is no automatic
migration/downgrade. Read [schemas.md](schemas.md) for exact profiles, branch
semantics, engine limits, and examples.

`requires: [wikilink-constraints]` enables `wikilink` policy beside a schema's
`type: string` and `format: Wikilink`. `requires: [document-relationships]`
enables named frontmatter assertions. Include both if using both. Unknown or
unsupported capabilities fail; editor schema shape validation is insufficient.

### Named relationships

An Article type can declare the following, provided `person.mdtype.yaml` exists:

```yaml
md-utils-type-schema: "2"
requires: [document-relationships]
name: Article
version: "1.0.0"
frontmatter: {}
body: {requirements: [], recommendations: []}
context: {requirements: [], recommendations: []}
relationships:
  authors:
    select: [written_by, {each: true}]
    target: {type: person.mdtype.yaml}
    cardinality: {min: 1}
    duplicates: forbid
    anchors: forbid
    embeds: forbid
```

`written_by: ['[[People/Bob]]']` supplies an assertion. The relation name and key
can differ. Selection is a list of literal keys and `{each: true}` array steps,
not JSONPath/JMESPath; periods/slashes in keys stay literal. At most 128 steps are
allowed. Missing keys yield no occurrences; wrong intermediate container kinds
fail. Terminal null fails unless `nulls: ignore`. Other malformed/nonstring values
remain visible. `cardinality.min` defaults to zero, `max` to unbounded; counts are
after ignored nulls, before syntax/resolution. Duplicates compare resolved document
identity. `duplicates`, `anchors`, and `embeds` default to `allow`, alternatively
`forbid`; `severity: advisory` makes findings advisory.

Targets resolve relative to `.md-utils/types/`, not the declaring file. They require
an explicit mdtype suffix and confined resource path. Full target requirements
are assessed; hints do not establish target conformance. Scalar/style/schema
constraints remain independent and conjunctive. Allowed fragments assess the
document, not heading/block existence. Cyclic type bindings and valid positive
relationship cycles are supported; cyclic external JSON Schema resources are not.
Rules own collection cycle/reciprocity/inverse policy, not relationship names.

Missing collection evidence gives `unavailable`, not proof of a broken link.
Complete namespace coverage is needed to establish unique/unresolved lookup;
two proven candidates establish ambiguity even with incomplete coverage. Native
queries have bounded reads and expose exhausted/changed evidence. Required failure
or unavailability fails type/rule validation. Relationship query commands instead
exit zero for complete answers even when those answers contain violations.

```bash
# Inspect stored assertions after changing relationship declarations.
md-utils rel out Articles/example.md --type Article --root ./ --detail evidence --json
```

## Validate definitions and affected documents

```bash
# Compile the registry, assess members and nonmembers, then check applicable rules.
md-utils types doctor
md-utils types check Book Books/ --format json
md-utils types identify Books/Dune.md --all-assessments
md-utils types find Book Books/
md-utils types verify Books/ --include-confirmed
md-utils rules validate --no-index
```

`doctor` compiles definitions/resources; it does not prove documents conform.
`check` tests a named type; `identify` assesses loaded types; `find` emits only
fully conforming documents. Do not validate an obligation by checking only `find`
results. Include examples that should fail the changed requirement and confirm
they remain selected by rules. Review the diff and report the changed contract
and any new findings separately from proposed document repairs.

Check/identify/verify accept `--format text|markdown|json|yaml|toml`; markdown uses
the text-style renderer. `check --include-ok` and `--no-advisories` affect only
text/markdown. Structured outputs retain all results and advisories.

Hints are `$md-utils: {typeHints: [Book, {name: Publishable, version: "1.0.0"}]}`
in frontmatter. Verification reports confirmed, rejected, unknown type, or
unavailable exact contract version. Malformed hints prevent conformance. Use
`verify --require-hints` when absence itself should fail.

## Repairing documents is separate from editing types

`types fix Book Books/Dune.md --dry-run` previews without writing. Without
`--dry-run` it prompts and can persist accepted fixes, then reassesses.
`--yes` accepts deterministic fixes; input-required fixes need explicit `--set
title=Dune` values. A schema `const` can determine a fix; `default` is only a
suggestion and is not automatically accepted by repair. Never invent domain data.
Use `--constraint <id>` for a particular constraint and
`--include-recommendations` to include advisory repairs. Remaining nonconformance
fails. For collection relationship repairs, use the reviewed `rules fix` workflow
in [rules.md](rules.md).

For declared frontmatter wikilink spelling, `links convert Books/ --root ./ --type
Book` previews contract-aware edits; `--in-place` writes. This replaces `--to`,
cannot select body/all scope, and preserves conforming values. Optional
`--prefer-style name|vault-path|relative-path|self-anchor` and
`--markdown-extension auto|include|omit` only choose permitted alternatives;
`--key` filters literal top-level subtrees. Recommended schemas require
`--include-recommendations`. Unresolved ambiguity or missing targets exits nonzero;
never infer a branch's intended replacement merely because another branch failed.

## Templates and new instances

Optional type creation metadata:

```yaml
creation:
  template:
    ref: ./book.knap
    mode: document
    inputSchema:
      inline:
        type: object
        properties:
          title: {type: string, default: Untitled}
```

Use exactly one `inline` template string or `ref`. `inputSchema` similarly accepts
one inline object/boolean schema or resource ref. Resources are definition-relative
and project-confined. Default document mode accepts a JSON object of named Knap
variables and renders the entire file. Use Knap `yaml`/`yaml_property` for YAML
frontmatter; templated TOML has no serializer. Explicit body mode uses
`{ "frontmatter": {}, "data": ... }`, with md-utils serializing YAML separately.

```bash
# Preview a new document; remove --dry-run only when ready to create it.
md-utils types new --type Book --value ./dune.json --filename-data '$.title' ./Books/ --dry-run
```

Destinations must exist and are never overwritten. Exactly one filename option:
`--filename Dune.md` is exact; `--filename-data '$.title'` selects one string with
JSONPath after input defaults, then appends `.md`. `--extension txt` changes the
suffix; `--extension ''` omits it and cannot accompany `--filename`. Existing
suffixes are not detected. Unsafe filenames fail rather than being slugified.
Input defaults precede validation; supplied null/false/zero/empty values survive.
Input/rendering/persistence errors block creation. Type/rule nonconformance is
advisory and still saves successfully, so run validation if conformance is needed.

For bulk creation use a nonempty object array via `--values ./books.json` or repeat
`--value-file`, instead of `--value`. Bulk requires `--filename-data`. Preflight
reports all input failures and collision participants; input/output is bounded at
64 MiB and 10,000 items. Publication stops at the first write failure, reporting
created/failed/not-attempted items; earlier creations remain. Dry run has no
persistent effects. Rules can choose the destination via their `creation` metadata.

## Interactive editing and deletion

`types interactive --name Book` requires config 0.3.0 and a terminal, using
`--config`/`--project-root` rather than ordinary type commands' `--root`. It offers
Create/Edit/Remove and manages existing schema associations, not schema contents.
Complete drafts compile before preview/confirmation. Cancel, `:cancel`, or interrupt
before confirmation discards drafts. Source paths/formats and unrelated resources
are preserved; edited files may be reformatted and lose comments. Individual writes
are atomic, multi-file saves are not. Referenced-type removal is refused; update
dependent rules first and inspect other resource bindings before manual deletion.
