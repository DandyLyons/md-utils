# RFC 0002: md-utils Configuration 0.3.0

- Status: Proposed
- Date: 2026-09-09
- Scope: MarkdownUtilitiesCore, MarkdownUtilities, md-utils, and server hosts
- Roadmap: [#135](https://github.com/DandyLyons/md-utils/issues/135)
- Depends on: [RFC 0001](0001-mdtype.md)

## Goal

Define one coherent configuration version that separates project settings, file-selection rules, Markdown type contracts, and reusable frontmatter schemas. This RFC records the approved design direction; it does not describe currently implemented 0.3.0 support. Completing this document does not complete issue #135.

MUST, MUST NOT, SHOULD, and MAY describe requirements of the proposed format.

## Layout and versions

```text
.md-utils/
  md-utils.json
  md-utils.legacy-0.2.0.json
  schemas/
    book.schema.json
  types/
    book.mdtype.json
    publishing/
      publishable.mdtype.yaml
  rules/
    books.mdrule.json
    legacy/
      books.mdrule.legacy-0.2.0.json
```

The minimal project configuration is:

```json
{
  "configVersion": "0.3.0"
}
```

An optional `$schema` identifies the published project schema. Version 0.3.0 MUST reject embedded `rules`, legacy `schemaRules`, and `schemaDirectory`. Unknown project fields MUST be rejected until defined by a versioned schema. Version-specific decoders MUST continue accepting 0.1.0 and 0.2.0 with their existing behavior.

`types/` holds reusable contracts. `schemas/` is an optional resource convention: types may embed schemas or reference shared resources. A project need not contain shared schemas. `config init` creates empty `schemas/`, `types/`, and `rules/` directories for discoverability. Rules enforce type expressions; direct schema and body checks remain supported by legacy configuration decoders.

The project config version, rule-file format, mdtype definition-language version, and individual type contract version are distinct concepts. This proposal uses the enclosing project config version to select the rule-file schema. An optional rule `$schema` provides editor integration but MUST NOT override runtime version selection. The mdtype v1 envelope and semantics remain governed by RFC 0001.

## Rules and discovery

One active JSON file contains one rule:

```json
{
  "name": "books",
  "match": { "paths": ["Books/**/*.md"] },
  "types": {
    "allOf": [
      "book.mdtype.json",
      "publishing/publishable.mdtype.yaml"
    ]
  }
}
```

`name` is a nonempty rule identity, `types` is required, and `match` is optional. An optional `$schema` is permitted. Unknown fields are invalid. Rule names and type names occupy separate namespaces.

Recursively discover `.mdrule.json` files under `rules/`, excluding the entire `rules/legacy/` subtree before inspecting its contents. Ignore unrelated files. Sort by project-relative resource path for reproducible diagnostics and output; order MUST NOT change validity. Reject duplicate rule names with both source paths. Missing rule directories represent an empty rule set. Malformed active files fail configuration compilation rather than being silently skipped.

Authoring and removal commands MUST operate on the resolved source file and preserve unrelated resources. Removing a rule does not implicitly remove its referenced types or schemas. Rule compilation and command output MUST retain source provenance.

## Type references

A string leaf references a definition relative to `.md-utils/types/`. `book.mdtype.json` refers only to the file at that directory's root. `publishing/book.mdtype.json` explicitly names a nested file. Hosts MUST NOT search recursively by basename or guess extensions.

Every reference MUST end in a recognized `.mdtype.yaml`, `.mdtype.yml`, `.mdtype.json`, or `.mdtype.toml` suffix, using RFC 0001's case-insensitive suffix recognition. Exact file lookup follows host filesystem behavior; configurations SHOULD avoid names differing only by case. Absolute paths, URLs, traversal segments, and symbolic-link escapes outside the types directory are invalid type references.

The host resolves the file and maps it to its declared type name during compilation. The declared name remains its identity. Duplicate declared names remain invalid under RFC 0001. Existing name-based hints and CLI commands remain supported. Portable Core receives explicit definitions and resolved bindings; it performs no implicit filesystem access.

Schema references inside types retain RFC 0001 semantics: relative to the containing definition or schema resource, confined to the project root after lexical and symbolic-link resolution. Thus `../schemas/book.schema.json` is valid within a root-level type definition. Migrating a legacy schema reference MUST preserve the resolved resource, not simply copy its old string.

## Type expressions

```text
TypeExpression = filename-string
               | { "allOf": [TypeExpression, ...] }
               | { "anyOf": [TypeExpression, ...] }
               | { "oneOf": [TypeExpression, ...] }
               | { "not": TypeExpression }
```

A composition object MUST contain exactly one operator. Arrays MUST be nonempty. A bare array, empty object, unsupported operator, or extensionless leaf is invalid. There is no separate `type`, `types.all`, or `types.any` field.

`allOf` requires every child to conform; `anyOf` requires at least one; `oneOf` requires exactly one; `not` requires ordinary nonconformance of its child. Children assess the same record independently. They do not merge definitions, alter closed-schema behavior, assign a nominal type, or create mdtype inheritance. This is rule-level composition of assessments and does not extend the mdtype v1 definition language.

Exact duplicate children in one composition array are rejected with both expression locations. Implementations MUST NOT deduplicate `oneOf` silently because doing so changes its meaning. Overlapping but distinct branches remain valid; multiple successful branches make `oneOf` fail. Recursive expressions are finite JSON trees, not references to other expressions; this format introduces no expression-reference cycles. Existing schema-resource cycle checks still apply.

## Match expressions and evaluation

Match expressions accept the same four recursive operators, with matcher objects as leaves rather than filename strings. A group contains exactly one operator and cannot mix operator and leaf fields. A leaf accepts existing `paths`, `excludePaths`, `file`, `frontmatter`, `frontmatterQuery`, and `document` fields with their existing flat composition semantics. Multiple leaf fields are conjunctive; paths are any-of and exclusions are none-of. Missing-key predicate behavior remains unchanged.

For example:

```json
{
  "name": "published-books",
  "match": {
    "allOf": [
      { "paths": ["Books/**/*.md"] },
      {
        "anyOf": [
          { "frontmatter": { "status": { "equals": "published" } } },
          { "frontmatter": { "status": { "equals": "featured" } } }
        ]
      }
    ]
  },
  "types": "book.mdtype.json"
}
```

Omitted `match` and `{}` select every candidate supplied by the host. CLI scans remain Markdown-only by default and retain their explicit non-Markdown opt-in behavior. Selection does not grant filesystem access or expand the candidate set. Path prefiltering MUST conservatively retain every candidate that the complete expression could select, including through negation and alternatives.

Evaluate selection first. A false match skips the rule; a true match triggers type enforcement. Required type nonconformance MUST fail the rule rather than make it inapplicable. Existing Core type-based applicability APIs remain separate. All applicable rules are evaluated independently, and overall success requires each to succeed. This is conjunction across rule outcomes, without merging their contracts.

Flat match syntax remains accepted in 0.3.0. Generated canonical output SHOULD use explicit grouping where it can preserve behavior. Legacy versions retain their exact parsing and resolution behavior.

## Errors, advisories, and repairs

Compile all referenced definitions and resources before processing records, including references in alternatives that might not be selected. Missing types, malformed definitions, unavailable required capabilities, and invalid schemas are configuration errors.

Expression evaluation distinguishes success, ordinary mismatch/nonconformance, and evaluation failure. A schema-engine failure or required unavailable evaluation input MUST NOT be treated as ordinary false and then inverted by `not`. Analysis failures prevent the affected branch from evaluating; an independent branch can still establish a decisive result. Configuration compilation failures remain fatal regardless of alternatives.

Both match and type composition use outcome-based error propagation:

| Operator | Result |
| --- | --- |
| `allOf` | Any ordinary failure establishes failure. Otherwise, any evaluation error makes the result an error. Otherwise, success. |
| `anyOf` | Any success establishes success. Otherwise, any evaluation error makes the result an error. Otherwise, failure. |
| `oneOf` | Two or more successes establish failure. Otherwise, any evaluation error makes the result an error. With no errors, exactly one success passes and zero successes fail. |
| `not` | Invert success and ordinary failure; preserve evaluation error. |

Evaluated errors that do not determine the aggregate result remain available in detailed explanation output, without becoming top-level failures. Short-circuit evaluation is permitted only when it preserves the aggregate result regardless of child order. Full explanation mode SHOULD evaluate all branches to provide their evidence. An aggregate match error fails assessment rather than silently skipping the rule.

RFC 0001 recommendations do not affect conformance or successful-branch counts. Preserve diagnostic codes, severities, constraint IDs, locations, and fix-its, and attach rule identity, resource path, and expression location as additional provenance.

Child failures under a successful `anyOf`, or a successful `not`, are explanatory evidence rather than top-level errors. A failed `oneOf` identifies whether zero or multiple branches passed. Detailed explanation output retains branch results; ordinary validation output reports the aggregate failure and relevant evidence. Advisories from successful positive branches may be reported without changing validity.

Fix-its retain their branch context. An alternative expression MUST NOT automatically combine fixes from competing branches. A workflow must select a repair target and reassess the complete expression afterward. Negation does not automatically authorize edits intended to break type conformance.

## Migration and compatibility

### Project root

For 0.3.0, a config at `<project>/.md-utils/md-utils.json` establishes `<project>/` as the project root, including when selected with `--config` from another working directory. Resolve `types/` and `rules/` under that root's `.md-utils/` directory and matcher paths relative to the project root. A config outside this standard layout requires an explicit project root from the CLI or calling host; never guess from the working directory. Server and CLI hosts MUST use the same rule. Legacy versions retain their existing resolution behavior.

Migration supports explicit source-version validation and a dry-run/preview listing every proposed file and conversion. Recommend backing up the complete `.md-utils/` directory before applying migration. No staging directory or migration manifest is required.

Before writing, validate the complete source and generated representation in memory, resolve resources, establish a deterministic destination map, and reject incompatible conversions or collisions. Never overwrite an existing destination with different contents. An identical file may be reused only after verification. Filename normalization collisions and existing declared type-name collisions are separate checks.

Preserve the original project configuration byte-for-byte as `md-utils.legacy-<source-version>.json`. Preserve each original embedded rule payload under `rules/legacy/`; JSON whitespace may be reserialized, but values MUST remain unchanged. Retain the original rule identity in active rules and generated types where possible; do not invent a `migrated-` prefix to bypass a collision. The original byte-for-byte project copy remains the authoritative historical source.

Write generated resource and rule files after preflight, then replace the active config last. Individual writes SHOULD be atomic. This is not a multi-file transaction: interrupted migration may leave newly created files, and a backup recommendation does not guarantee rollback. Report completed writes and recovery instructions on failure where possible. Do not delete legacy artifacts automatically. Repeated attempts MUST verify existing artifacts and fail clearly on inconsistent state. An already-current config produces a no-op rather than re-migrating legacy copies.

### Conversion requirements

| Legacy behavior | Conversion direction | Required verification |
| --- | --- | --- |
| Selection predicates | Preserve as match leaves or equivalent groups | Same selected candidates, including missing data and non-Markdown behavior |
| Required schema check | Generated mdtype frontmatter schema | Same resource, presence policy, and validation result |
| Required heading/body counts | Generated mdtype body requirements | Same predicate semantics and stable constraint provenance |
| Core-only advisory body checks | Generated mdtype recommendations if a future API converter supports them | Not part of serialized 0.1.0/0.2.0 migration |
| Core-only advisory schema checks | No general mdtype v1 equivalent | Not a serialized legacy config blocker; do not add API conversion implicitly |
| Several schema checks with differing presence policies | Not necessarily representable by one type | Prove an equivalent expression or stop |
| Existing type applicability | Preserve selection semantics | Never convert applicability into enforcement implicitly |
| Skipped results | Preserve the outcome or reject conversion | Do not silently turn `skipped` into `passed` |
| Legacy diagnostic identities and fix-its | Document the new type-based diagnostics | Codes, IDs, wording, detail, and repair suggestions may change without changing the validation outcome |

Migration MUST NOT claim every legacy rule is representable by one generated mdtype. Unsupported cases fail before mutation with manual remediation guidance. Changes to mdtype definition semantics require a separate RFC 0001 compatibility decision; config 0.3.0 alone cannot redefine mdtype v1.

Legacy loading remains available whether or not automatic migration is possible. Compatibility tests must cover required/advisory distinctions, invalid records, optional frontmatter, matching, resource resolution, multi-rule results, and diagnostic provenance.

### Approved compatibility boundary

Automatic migration MUST preserve file selection and rule pass/fail/skipped outcomes. It MUST reject conversions known to change these outcomes before writing. Checking only the project's currently valid records is insufficient evidence that a conversion preserves behavior for future records.

Documented diagnostic changes are permitted: migrated rules may report mdtype diagnostic codes, constraint IDs, wording, locations, additional explanatory detail, and fix-it proposals. The migration preview and migration documentation MUST explain this transition. Such changes MUST NOT turn advisory guidance into a failing requirement or otherwise change the validation outcome. The runtime MUST still preserve the originating mdtype diagnostics when wrapping them with rule/expression provenance, as specified above.

Do not add a permissive migration flag that silently accepts changed outcomes. Unsupported cases remain loadable through the legacy version until a behavior-preserving conversion or a separately approved semantic change is defined.

## Delivery and validation

1. Agree on this RFC and reconcile issue acceptance criteria.
2. Implement #109's portable enforcement model, recursive composition, and diagnostic behavior while preserving type applicability.
3. Implement #71's recursive selection and #96's standalone storage against one final 0.3.0 format; do not publish an intermediate embedded-rule 0.3.0 format.
4. Complete conversion coverage and interruption/recovery tests.
5. Coordinate #72's canonical schema publication; synchronize public/bundled project and rule schemas, README, DocC, CLI help, and canonical/resource Agent Skill copies.
6. Implement or explicitly defer #58's interactive authoring against the resulting storage format.

Use Swift Testing for recursive operators, malformed expressions, unknown resources, duplicate identities, discovery exclusions, deterministic output, non-Markdown candidates, command preservation, migration refusal/success/interruption, and legacy compatibility. Core, native CLI, server, Linux, and WASM-capable hosts must agree when given equivalent inputs. Analyze a record once and reuse immutable compiled registries.

Keep coverage proportional to this project's current usage. Reuse existing config migration and rule assessment tests; add a compact operator table and representative conversion cases instead of an exhaustive cross-product or a new test framework. Review a required schema rule, an optional-frontmatter rule, a body-only rule with malformed frontmatter, and a custom schema-resource location. Advisory checks are Core API behavior, not serialized 0.1.0/0.2.0 input. Check selection, pass/fail/skipped behavior, diagnostics, and resolved resources for these cases. Existing collision and dry-run coverage should be extended where needed rather than duplicated.

### Focused migration review (2026-09-09)

This is a source-based review, not an executed 0.3.0 migration: the new runtime and converter do not exist yet. Evidence comes from `MarkdownRuleConfiguration.parseCheck`, `MarkdownRuleChecker`, `MarkdownTypeChecker`, `MdUtilsConfig.compiledRuleRegistry`, and existing `ConfigCommandsTests` and `MarkdownRuleCheckerTests`.

The serialized 0.2.0 checks are `frontmatterSchema`, `requiredHeading`, `maxBodyLines`, and `maxBodyWords`. They do not accept check severity or messages. The decoder also does not serialize Core's type applicability fields. Those richer API capabilities must not be mistaken for legacy config migration inputs.

| Representative before/after | Source-confirmed outcome | Migration implication |
| --- | --- | --- |
| Required `book.schema.json` check becomes a type with required frontmatter and `ref: ../schemas/book.schema.json` | Ordinary valid/invalid schema results can agree, but rule schema codes and IDs differ from type diagnostics; missing frontmatter can produce additional type schema diagnostics and fix-its | Diagnostic changes are approved when documented; verify invalid-record outcomes before admitting this conversion |
| Optional schema-only rule becomes a type with optional frontmatter | With no frontmatter, the old rule is `skipped`; the type conforms | Pass/fail equivalence alone is insufficient; preserve the status through an explicit supported mechanism or reject this conversion |
| Required heading/count rule becomes an equivalent body constraint | Body predicates map naturally, but type assessment starts with record parse diagnostics; direct legacy body checks do not universally do so | A body-only conversion may newly fail malformed frontmatter; it is not universally behavior-preserving |
| Custom `schemaDirectory: shared/schemas/` with `schema: book.schema.json` becomes a root-level type reference `../../shared/schemas/book.schema.json` | The same resource remains under the project root; nested schema references remain relative to that schema | Rewrite from the actual resolved resource; retain project containment checks |
| Several required schema checks become multiple schemas in one type | All schemas are conjunctive; one shared presence policy suffices when all are required | Diagnostic differences remain; differing presence policies require a separate conversion decision |

For an ordinary schema-only rule, the complete candidate generated type has this shape (the generated contract-version value remains to be assigned):

```json
{
  "md-utils-type-schema": "1",
  "name": "books",
  "version": "migration-version-to-be-assigned",
  "frontmatter": {
    "presence": "required",
    "schemas": [{ "ref": "../schemas/book.schema.json" }]
  },
  "body": { "requirements": [], "recommendations": [] },
  "context": { "requirements": [], "recommendations": [] }
}
```

Its active rule preserves the original `match` and sets `types` to `books.mdtype.json`. Selection stays in the rule; do not transfer path selectors into type constraints. This is a candidate structural conversion, not a claim of full diagnostic equivalence.

The existing 0.1.0-to-0.2.0 migration fixture writes a schema reference without creating the referenced schema file. That is sufficient for its existing storage-conversion test, but a 0.3.0 test that compiles the generated registry must supply an actual schema. Extend that fixture locally for the new case rather than treating its current success as resource-resolution evidence.

Start with the four representative cases above plus existing dry-run/collision tests. Do not introduce an API migration framework or change mdtype v1 to accommodate hypothetical advisory configs. Diagnostic changes are approved subject to the compatibility boundary above. Optional-schema-only and body-only conversions with known outcome differences must be rejected until those differences are resolved. Required-schema conversions remain candidates pending focused invalid-record checks, rather than being declared safe from shape alone.

Issue #135 remains open until the format is implemented, related work is completed or explicitly deferred, compatibility and migration behavior are tested, and schemas and documentation agree.

## Remaining specification work

- Finalize rule discovery suffix case handling consistently across hosts.
- Confirm the automatic migration subset with focused invalid-record cases; diagnostic changes are allowed, while selection and pass/fail/skipped outcomes must be preserved.
- Assign public rule-schema URLs and the generated migration type contract version.

These details must be settled before declaring the format implementation-ready. The directory, syntax, identity, and migration decisions above provide the shared design target.

Dedicated expression depth/size limits are deferred; they are not a prerequisite for 0.3.0 at the project's current scale.
