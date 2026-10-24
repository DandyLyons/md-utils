# Schemas: frontmatter data contracts

Read this when editing inline or shared JSON Schemas used by md-utils. Schemas
constrain data values; [types](types.md) add body/context/relationships, and
[rules](rules.md) select where contracts apply. Definition-envelope schemas
validate `.mdtype`/`.mdrule`/config syntax and are a different layer.

## Locate the schema and all consumers

Inspect the project's config version and consuming types/rules before editing.
In config 0.3.0, shared `.md-utils/schemas/` is a convention, not a required
directory or project `schemaDirectory` setting. A root-level type can use:

```yaml
frontmatter:
  presence: required
  schemas:
    - ref: ../schemas/book.schema.json
```

Or replace that item with `inline: {type: object, required: [title]}`. Each item
has exactly one `inline` or `ref`. Required frontmatter schemas must be objects,
not boolean schemas. JSON and YAML schema resources are supported. All required
schemas validate the same object independently, equivalent to conjunction.
Explicit mdtype v2 `recommendedSchemas` makes data violations advisory but still
requires valid compilable schema resources. Creation `inputSchema` is a separate
contract that permits object or boolean schemas and inserts missing defaults.

Top-level type refs resolve from the definition; nested external `$ref` resolves
from its containing schema. Internal `#` fragments stay in that resource. Resource
resolution is project-confined, including symlink checks; absolute paths, escapes,
missing resources, and external reference cycles fail. No implicit network fetch
is a way to satisfy missing dependencies. Keep shared schemas in-project.
Conflicting content for the same `$id` within a type's schema graph is invalid.

In legacy config 0.2.0, a `frontmatterSchema` check's `schema` filename resolves
under `schemaDirectory`, itself project-root-relative. Preserve that convention
when editing legacy configs rather than converting to type-relative refs.

## A useful complete schema

Save `.md-utils/schemas/book.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["kind", "title"],
  "properties": {
    "kind": {"const": "book"},
    "title": {"type": "string", "minLength": 1},
    "tags": {"type": "array", "items": {"type": "string"}, "uniqueItems": true},
    "rating": {"type": "integer", "minimum": 1, "maximum": 5},
    "summary": {"anyOf": [{"type": "string"}, {"type": "null"}]}
  },
  "additionalProperties": false
}
```

This permits absent `summary` and present null independently. `properties` alone
does not require a key: use `required`. Empty text needs `minLength`; empty arrays
need `minItems` if prohibited. Use `items` for every array element and nested object
schemas for nested properties. Add `additionalProperties: false` only when a
closed object is intended; it rejects unrelated user fields. Reserved `$md-utils`
system metadata is removed before type frontmatter schema evaluation and cannot
be required/rejected/inspected by that schema.

Choose `const` for one required value, `enum` for alternatives, `allOf` for
conjunction, `anyOf` for at least one passing branch, `oneOf` for exactly one,
and `not` for exclusion. Overlapping branches can make `oneOf` fail. Keep type
restrictions explicit rather than relying on a keyword that only applies to a
particular value kind. Use `$defs` and local `$ref` to reuse object schema nodes.
The selected md-utils engine/profile determines support; a generic validator
accepting a schema is not proof that md-utils can execute it.

## Values, defaults, and repairs

YAML/TOML metadata is converted to JSON-compatible values for assessment. Quote
text that resembles null, booleans, numbers, or dates. Native temporal values do
not become valid v2 semantic strings merely because a projection looks textual.
TOML has no null; use another schema branch or explicitly change document format.
Optional frontmatter means absent blocks skip schema assessment; present blocks
are always checked. Recommendations alone do not require frontmatter.

Assessment never inserts defaults or rewrites documents. For a missing required
property, `const` can supply a deterministic repair; `default` remains an
input-required suggestion. Creation input-schema processing explicitly inserts
missing defaults before rendering and validation, preserving supplied values.
Do not confuse these two workflows. `fm set --value` always stores a string;
it is unsuitable for writing a numeric/boolean/object schema value by implication.

## Semantic strings in explicit mdtype v2

Use `md-utils-type-schema: "2"` on the consuming type. Add `type: string` with a
case-sensitive `format`. Subject-only names select the default profile:

| Subject / full profile | Accepted spelling |
| --- | --- |
| `Date` / `Date/ISO8601` | Real Gregorian date `YYYY-MM-DD`, years 0001–9999. |
| `LocalTime` / `LocalTime/ISO8601` | `HH:mm:ss`, optional 1–9 fractional digits; no offset, leap second, or 24:00. |
| `DateTime` / `DateTime/RFC3339` | Date plus `T`/`t`, time, and `Z`/`z` or signed `HH:mm` offset. Unknown `-00:00` offset is retained. |
| `UUID` / `UUID/RFC9562` | Hyphenated 36-character hexadecimal UUID; RFC variant versions 1, 3–8, plus Nil/Max. Case-insensitive. No braces, URN, or compact spelling. |
| `Wikilink` / `Wikilink/Obsidian` | Exactly one whole link, such as `[[People/Bob]]`, with optional alias, fragment, or embed. |

`Time` and `DateTime/ISO8601` are unsupported. Empty strings fail these profiles;
null needs a separate nullable branch. Scalar checks do not resolve destinations,
normalize stored text, allocate UUID identity, or prove uniqueness. UUID generation
is a separate explicit v4 operation.

```yaml
frontmatter:
  schemas:
    - inline:
        type: object
        properties:
          published:
            anyOf:
              - {type: string, format: DateTime}
              - {type: "null"}
          related:
            type: array
            items: {type: string, format: Wikilink}
  recommendedSchemas:
    - inline:
        required: [published]
```

Whole-value wikilinks reject surrounding whitespace, prose, adjacent links,
newlines, NUL, empty destinations without anchors, and empty anchors. Declared
frontmatter uses standard parsing context; do not infer Markdown-table alias
escaping from the string. Aliases do not change destination identity.

### Wikilink spelling policy

Declare top-level `requires: [wikilink-constraints]` on the v2 type, then use:

```yaml
type: string
format: Wikilink
wikilink:
  styles: [name, vault-path]
  markdownExtension: omit
```

Styles are unordered distinct values: `name`, `vault-path`, `relative-path`, and
`self-anchor`. Omitted styles allow any; empty/duplicate/unknown values fail.
Strict vault-path needs a path component: root-level `[[Alice.md]]` remains name
style. Absolute filesystem paths are not a supported constrained style.
`markdownExtension` is `require`, `omit`, or `either` (default), checking only final
`.md`/`.markdown` suffixes case-insensitively. Attachments pass omit/either but fail
require; self-anchor-only plus require is invalid. Style checks do not resolve or
rewrite. `links convert --type` provides separate explicit repair.

### Supported schema profile and errors

Draft 2020-12 is used; missing `$schema` is supplied during compilation. V2 rejects
unsupported dialects/capabilities rather than approximating them: dynamic/recursive
references, `unevaluatedProperties`, `unevaluatedItems`, `prefixItems`,
`minContains`, `maxContains`, and legacy `dependencies`/`additionalItems`.
Recursive refs and expansions beyond 128 levels or 10,000 nodes are rejected.
References must select object schemas at standard schema locations using resource
identifiers or JSON Pointers; anchor references or pointers into literal data or
extension keywords are unsupported by the v2 adapter.

Uppercase-initial or slash-containing formats reserve the semantic namespace;
unknown profiles there fail loading. Lowercase slash-free formats retain engine
behavior. Do not assume arbitrary JSON Schema `format` is asserted. Generic
validators may treat `format` as annotation and cannot substitute for md-utils'
semantic assessment, capability gates, or named relationship checks.

Semantic checks respect JSON Schema branches, negation, nullable alternatives,
references, and array items. Do not implement a second property-walk validator or
infer a required repair from a failed branch when another branch passes.
Diagnostics retain instance/schema locations and `frontmatter.format.invalid`
reasons such as `native-kind`, `syntax`, `trailing-input`, `calendar-range`,
`precision`, and `uuid-layout`. Declaration errors include unsupported formats,
invalid declarations, and unsupported capabilities. Advisory schema definitions
must be valid even though their data failures do not prevent conformance.

## Edit and verify

1. Locate every direct/transitive consumer and confirm its language/profile.
2. Edit the existing schema or inline node, preserving unrelated requirements and
   reference identities. Do not modify published versioned schemas to change a
   local contract; create/edit the project's own resource.
3. Compile via `md-utils types doctor`. For legacy rules, load/validate the rule
   using its config rather than assuming the type registry covers it.
4. Assess representative valid and invalid documents using `types check Book
   Books/ --format json`, then `rules validate --no-index` for affected consumers.
   Include absence, explicit null, wrong kinds, arrays/nesting, and branch cases
   when the edit changes those behaviors. Snapshot-only validation is unsuitable
   for newly edited schemas.
5. Review the schema diff and findings. Repair documents separately and explicitly;
   do not silently relax the schema or apply defaults to make validation pass.

There is no `schema interactive` command. Type/rule editors manage schema
associations, not JSON Schema contents. Edit resources with file-editing tools;
an already available external JSON Schema validator can supplement syntax checks.
Do not install a validator merely to edit a schema without the user's authorization.

`types schema` exports the v1 definition-envelope schema; `--schema-version 2`
exports the capability-bearing v2 schema, including named relationships. This
does not create a user frontmatter schema. `config schema` exports the default
config schema, not a version inferred from an existing project. Keep config,
mdrule, mdtype language, contract, CLI, and JSON Schema dialect versions separate.
