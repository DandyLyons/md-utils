# Rules: selecting documents and enforcing contracts

Read this when creating, editing, inspecting, validating, or repairing project
rules. For contract contents read [types.md](types.md); for frontmatter JSON
Schema read [schemas.md](schemas.md).

## Choose the existing format first

Inspect `.md-utils/md-utils.json` from the project root. Commands do not search
parent directories. Rule commands accept `--config <file>` and
`--project-root <directory>/`; nonstandard config locations require the latter.
Do not silently migrate a project while editing a rule.

| Format | Storage and behavior |
| --- | --- |
| Config 0.1.0 | Legacy `schemaRules` in project config; retain its existing syntax. |
| Config 0.2.0 | `rules[]` containing `name`, `match`, and `checks`; `schemaDirectory` resolves from project root. Still the `config init` default. |
| Config 0.3.0 | Project settings plus standalone `.mdrule.json` files recursively under `.md-utils/rules/`, excluding `rules/legacy/`; checks live in types. |
| Explicit mdrule 1 | A standalone rule with `"md-utils-rule-schema": "1"`; adds collection relationship policies independently of the project version. |

`$schema` supplies editor metadata, not runtime version selection. Unknown fields,
unsupported versions, malformed definitions, and duplicate rule names are errors.
Creating the directories alone does not enable standalone rules.

## Edit a standalone rule

A minimal 0.3.0 config is `{"configVersion":"0.3.0"}`. With an existing
`.md-utils/types/book.mdtype.yaml`, save `.md-utils/rules/books.mdrule.json`:

```json
{
  "name": "books",
  "match": {
    "allOf": [
      {"paths": ["Books/**/*.md"]},
      {"not": {"paths": ["Books/archive/**"]}}
    ]
  },
  "types": "book.mdtype.yaml"
}
```

For a simple new rule, `md-utils rules add books --type book.mdtype.yaml --path
'Books/**/*.md'` creates the file. Use direct file editing for unattended changes
and richer expressions. Preserve the existing path and unrelated fields. A rule
rename changes the identity used by CLI selections; check callers before renaming.

Type leaves are explicit `.mdtype.json`, `.mdtype.yaml`, `.mdtype.yml`, or
`.mdtype.toml` filenames relative to `.md-utils/types/`, including nested paths.
They are not declared type names or paths relative to the rule. Absolute paths,
traversal, extension guessing, and basename search are unsupported.

Both `match` and `types` allow recursive `allOf`, `anyOf`, `oneOf`, and `not`:

```json
{
  "allOf": [
    "book.mdtype.yaml",
    {"anyOf": ["published.mdtype.json", "draft.mdtype.json"]}
  ]
}
```

A group has exactly one operator, no leaf fields, and nonempty arrays; `not`
contains one expression. Exact duplicate type-group children are rejected.
`allOf` requires all branches, `anyOf` one or more, `oneOf` exactly one, and `not`
ordinary nonconformance. Evaluation errors are not ordinary failures and cannot
be negated into success. Decisive results can still determine a group despite an
error in another branch. Every branch's definitions/resources compile up front.

Selection precedes enforcement. Selected nonconforming documents fail; they do
not disappear. Every applicable rule must pass. An omitted or empty standalone
`match` selects all host candidates. Do not use a conformance filter to select the
documents whose conformance you intend to enforce.

## Matcher vocabulary

Within a matcher leaf, groups and operators combine with AND. `paths` is any-of
project-relative globs; `excludePaths` is none-of. For example:

```json
{
  "paths": ["Books/**/*.md"],
  "excludePaths": ["Books/archive/**"],
  "frontmatter": {"tags": {"includes": "Book"}},
  "document": {"hasHeading": "Synopsis"}
}
```

| Namespace | Operators |
| --- | --- |
| `file` | `pathRegex`, `filenameEquals`, `extensionIn`, `modifiedAfter`, `modifiedBefore` |
| `frontmatter.<literal key>` | `equals`, `doesntEqual`, `includes`, `notIncludes`, `hasKey`, `doesntHaveKey`, `regex`, `startsWith`, `endsWith`, `contains`, `empty`, `emptyString`, `emptyArray`, `emptyObject`, `notEmpty`, `in`, `notIn`, `greaterThan`, `greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`, `after`, `onOrAfter`, `before`, `onOrBefore`, `between`, `typeIs` |
| `frontmatterQuery` | `jmespath`, evaluated against the whole parsed frontmatter |
| `document` | `hasHeading`, `headingRegex`, `hasHeadingAtLevel`, `hasSection`, `bodyContains`, `bodyRegex`, `hasWikilink`, `lineCount`, `wordCount` |

Missing keys do not match `doesntEqual`, `notIncludes`, or `notIn`; use
`doesntHaveKey: true`. `contains` is string containment; `includes` is array
membership. Date operands accept `YYYY-MM-DD` or RFC 3339 timestamps with `Z` or
numeric offsets and compare at the operand's precision. `between` is inclusive.
Regex operators use Swift `NSRegularExpression` syntax. JMESPath false, null,
and empty strings/arrays/objects are falsey. `hasBrokenWikilink` is unsupported.
Legacy 0.2.0 does not accept recursive groups or `all`/`any`/`not` predicates.

Operand shapes:

- `equals`/`doesntEqual`/`includes`/`notIncludes` take JSON-compatible values;
  `in`/`notIn` take nonempty arrays. Numeric comparisons take numbers.
- `hasKey`, `doesntHaveKey`, and all empty/not-empty predicates take `true`.
  Empty means an empty string, array, or object, not a missing key.
- `typeIs` is `string|boolean|number|array|object|null` (not `integer`).
- `between` is `{"from": 1, "to": 5}` or two date/time strings, with ordered bounds.
- `hasHeadingAtLevel` is `{"heading":"Synopsis","level":2}`; unlike a type's
  heading selector, its text key is `heading`. `lineCount`/`wordCount` take
  `{"min":1,"max":200}` with at least one nonnegative bound and min ≤ max.
- Other heading/section/body/wikilink predicates take strings. `extensionIn`
  takes a nonempty array such as `["md","markdown"]`, without leading dots,
  compared case-insensitively. `filenameEquals` includes the extension.

Scans are Markdown-only unless `--include-non-md` is supplied to validation or
file matching. Explicit `rules matching` accepts mapped non-Markdown files;
`.txt` needs that flag. Wrapped/hash-comment frontmatter uses shipped mappings.
Raw body/count predicates can inspect non-Markdown source, but Markdown headings,
sections, heading relationships, and wikilinks are unsupported there. Unmapped
files cannot satisfy required frontmatter. Scans skip hidden entries and symlinks.

## Inspect selection, then validate the edit

```bash
# Inspect rule definitions, selection, and current results before/after an edit.
md-utils rules list --verbose
md-utils rules describe books --format json
md-utils rules matching Books/Dune.md --explain
md-utils rules files-matching books
md-utils types doctor
md-utils rules validate books --no-index --json
md-utils rules validate --no-index
```

Use representative intended members, exclusions, and a deliberately invalid
document to distinguish successful selection from successful enforcement. An
empty selection does not demonstrate that a changed requirement works. After a
shared type/schema edit, validate all affected rules. Review definition diffs and
report new failures; do not weaken contracts merely to make existing data pass.

`--json` and `--yaml` are mutually exclusive validation formats. `--include-ok`
changes text visibility; structured output retains full results. Required failure
or unavailable evidence exits nonzero; advisories remain visible without failure.

Ordinary validation refreshes requested scopes in an existing compatible index;
without one it validates sources and does not create a cache. Index errors warn
and fall back; cancellation stops. `--no-index` forces direct assessment;
`--verify-hashes` detects stat-preserving edits. `--index-only`/`--indexed-only`
reads published SQLite findings only, without current definitions, source reads,
stats, refresh, writes, or fallback. It rejects the other two flags and is not a
way to validate a newly edited definition. Missing evidence stays unavailable.

## Collection relationship policies

Add `"md-utils-rule-schema": "1"` and `relationshipPolicies` to a standalone
rule; `types` remains required. Its referenced types must declare the named
relationships using mdtype v2. For example:

```json
{
  "md-utils-rule-schema": "1",
  "name": "people",
  "match": {"paths": ["People/**/*.md"]},
  "types": "person.mdtype.yaml",
  "relationshipPolicies": [
    {
      "id": "spouse-return",
      "kind": "reciprocity",
      "relation": {"type": "person.mdtype.yaml", "name": "spouse"},
      "scope": "reachable",
      "severity": "error"
    }
  ]
}
```

Each policy needs a unique nonempty `id`, `kind`, and `scope`. Relation bindings
are `{type: <type-resource>, name: <declared-relationship>}`, independently of the
rule's type expression. Invalid bindings fail loading even for advisories.

| Kind | Additional fields and meaning |
| --- | --- |
| `cycles` | Nonempty `relations`; `mode: allowed|discouraged|forbidden`. Mode controls severity; an explicit `severity` is invalid. |
| `selfLinks` | Nonempty `relations`; `mode: allow|forbid`. Identity-equal endpoints are self-links. |
| `reciprocity` | One `relation`; each A → B needs B → A in the same relation. |
| `inverse` | `from` and `to` bindings; each A —from→ B needs B —to→ A. Add a swapped policy for the reverse obligation. |

Non-cycle severity defaults to `error`, optionally `advisory`. `selected` scope
includes edges with both endpoints selected by `match`, reporting boundary edges
without return obligations. `reachable` closes over bound outgoing relations
from selected seeds; inverse closure includes both relations. Resolution still
uses the collection universe. Permission in one policy does not override another.
Policies check stored consistency, never infer truth or create return assertions.
Malformed/ambiguous evidence can make an obligation unavailable; proven violations
remain failures. Empty complete scopes pass, incomplete samples do not prove success.

Cycle output defaults to `--cycle-witness-per-component` (one witness per cyclic
component). Mutually exclusive `--cycle-witness-first` stops each policy's cycle
search at its first witness; neither enumerates every cycle. JSON/YAML preserve
coverage, origins, boundary edges, conflicts, and witnesses.

## Editing definitions versus repairing documents

`rules fix [rule]` changes selected documents, not rule definitions. It previews
by default. `--select 1,4,5` (also repeatable) previews combined proposals;
`--apply` persists. Noninteractive numbered application additionally requires the
printed evidence-bound `--review` token. Stale evidence requires a fresh preview.
`--yes` selects only automatic shared schema fixes, not relationship assertions
or input-required defaults. Advisory repairs need `--include-recommendations`.
Ambiguous/unavailable proposals and conflicting edits block application.

Application reassesses combined changes, preserves passing required conformance,
and rechecks source/supporting revisions, definitions, candidate namespace, and
scope. Metadata may be reserialized; unrelated values and body bytes are preserved.
Writes are sequential, not a cross-file transaction. On failure inspect `index
draft show`, resolve indeterminate receipts with `index draft resolve`, then resume
`index apply` with every batch draft ID, including completed members. Confirmed
commits are not repeated. Cached evidence never replaces final repair checks.

## Creation, interactive authoring, and removal

To create documents through a rule, add `creation: {"type":"Book",
"directory":"./Books/"}`. The directory is project-relative and must exist;
`type` is a declared name referenced by the rule, required when ambiguous.
`rules new --rule books --value ./dune.json --filename Dune.md --dry-run` previews
the chosen type's template. Omit `--dry-run` to save without overwriting. Creation
nonconformance is advisory; follow with validation. See [types.md](types.md) for
template/input/filename and bulk behavior.

`rules interactive --edit books` requires config 0.3.0 and a terminal. It supports
CRUD, recursive expressions, and drafting a new type in-process. Complete drafts
compile and preview before confirmation; cancellation discards them. Type files
save before rules, with atomic individual writes and partial-failure reporting.
`rules remove books` deletes only the rule; types/schemas remain, and
`--delete-schema` is rejected in 0.3.0. Inspect references before deleting resources.

## Legacy editing and migration

A 0.2.0 example (schema path relative to `schemaDirectory`):

```json
{
  "configVersion": "0.2.0",
  "schemaDirectory": ".md-utils/schemas/",
  "rules": [{
    "name": "books",
    "match": {"paths": ["Books/**/*.md"]},
    "checks": [{"type": "frontmatterSchema", "schema": "book.schema.json", "frontmatterRequired": true}]
  }]
}
```

Other serialized checks are `requiredHeading`, `maxBodyLines`, and `maxBodyWords`.
Their shapes are `{"type":"requiredHeading","heading":"Synopsis"}`,
`{"type":"maxBodyLines","max":200}`, and
`{"type":"maxBodyWords","max":1500}`. Counts are nonnegative integers.
With `frontmatterRequired: false`, absent frontmatter skips the schema check;
present malformed frontmatter still fails.
Do not insert `types` or Core's programmatic `typeConformance` into legacy configs.
`rules add books --path 'Books/**/*.md' --tag Book` creates a legacy rule/schema;
inspect its generated path before editing. `config schema` prints the default
config schema, not a schema selected from your file's version.

When migration is requested, back up `.md-utils/`, preview `config migrate --to
0.3.0 --dry-run`, then apply without `--dry-run`. Automatic conversion supports
required-schema-only rules and empty projects; incompatible checks, optional
schemas, unsafe resources, and collisions fail before writes. Legacy config/rule
artifacts remain, and active config is replaced last. Migration has no staging
manifest or multi-file transaction. Inspect completed writes or restore the backup
after interruption. Malformed type hints can newly fail after migration.
