# RFC 0005: mdstandard Definition Language

- Status: working language draft; not an approved format or implemented feature
- Date: 2026-10-23
- Tracking: #191–#196; compatibility coordination #184/#135; semantic identity #186
- Authoritative decision history: [standards design](../mdstandards-design.md)
- Adoption proposal: [bindings and worked cases](../mdstandard-adoption.md)

## Purpose and approval boundary

Define the language before implementing it. The owner explicitly requested this
phase on 2026-10-23. This RFC will consolidate the coordinated specification;
existing design documents retain rationale and approval history. Proposed field
names and examples below are review material, not a schema publication decision.
No mdrule format change, identifier syntax, signature system, or configuration
placement is selected merely by introducing this draft.

Approved direction: explicit standards adoption; independent versioned releases
with separate rule/type/schema resources; destination-owned migration definitions
and pinned cross-version references; migration from the preceding release for
every release after the first; JSON actions executed exclusively by md-utils;
staging, review, and a separate apply command that also cleans up after success.
Manual editing of staged files is approved subject to renewed validation/review,
with permission to drop that feature if its design becomes too complex.

## Language boundaries

| Resource | Author | Meaning |
| --- | --- | --- |
| Standard definition | Standard author | Identity, release, required rule references, predecessor and incoming migrations |
| Rules, types, content schemas | Standard author or referenced dependency author | Actual minimum contracts; existing languages retain their semantics |
| Migration definition | Standard author | Declarative transformation between identified standard releases |
| Adoption declaration | Adopting user | Chosen release, local rule bindings, populations and modes |
| Import/export strategy | Adopting user | Directional transformation between standard and local endpoints |
| Staging manifest and review report | md-utils | Frozen inputs, proposed outputs, assessment and review evidence |

The standard document is proposed to support JSON and equivalent restricted YAML;
the transformation definitions are JSON per owner direction. Exact YAML profile
and language discriminators remain to be specified. Definition-language versions,
authored standard releases, operation-language versions, and executable releases
are separate version axes.

## Proposed standard document shape

This is an illustrative JSON shape, not a valid published fixture. Angle-bracket
strings stand for unresolved identifiers or actual digests. `md-utils-standard-schema: "1"`
is a candidate discriminator, not a reserved or approved version.

The example document is named **`recipes.mdstandard.json`** and lives at the
root of its independently downloadable release bundle. Illustrative unpacked layout:

```text
md-recipes-0.2.0/
  recipes.mdstandard.json
  rules/
    recipe.mdrule.json
  types/
    recipe.mdtype.json
  schemas/
    recipe.schema.json
  migrations/
    from-0.1.0.json
```

The outer directory name is illustrative, not part of standard identity. A
publisher may host this root at `/md-recipes/0.2.0/`, but other versions need not
be adjacent or bundled together. Resource paths are relative to this standard
document's directory. The proposed naming convention is `<name>.mdstandard.json`
(or `.mdstandard.yaml` for the eventual YAML profile); the basename need not
equal the document's `name`. References identify the exact filename, without
guessing. This layout is explanatory, not files created by this RFC.

```json
{
  "md-utils-standard-schema": "1",
  "id": "<stable standard identifier>",
  "name": "md-recipes",
  "version": "0.2.0",
  "rules": {
    "recipe": {"resource": "recipe-rule"}
  },
  "resources": {
    "recipe-rule": {
      "kind": "rule",
      "path": "rules/recipe.mdrule.json",
      "sha256": "<64 lowercase hexadecimal characters>"
    },
    "upgrade-from-0.1.0": {
      "kind": "migration",
      "path": "migrations/from-0.1.0.json",
      "sha256": "<64 lowercase hexadecimal characters>"
    }
  },
  "predecessor": {
    "version": "0.1.0",
    "location": "https://example.org/recipes/0.1.0/recipes.mdstandard.json",
    "sha256": "<digest of the predecessor standard document>",
    "migration": "upgrade-from-0.1.0"
  }
}
```

The real release must include the complete rule/type/schema dependency closure;
the abbreviated resource table above does not demonstrate that closure. A required
role points to an actual rule resource, not merely a type name. References inside
bundled rules/types must have explicitly specified resolution semantics; do not
silently reinterpret existing project-relative references as bundle-relative.

Owner decision, 2026-10-23: `predecessor` is REQUIRED in every release. The first
release explicitly sets `"predecessor": null`; omission is invalid. Later releases
require a non-null predecessor object and migration definition. Declaring null
is not a mechanism to reset the history of an existing standard; verification of
initial-release status belongs to publication/history policy. Exact branch and source-range
rules remain open. Source release files are not embedded in every destination
bundle. Migration preparation obtains the pinned source/intermediate dependencies
needed by the chosen route. Locations are retrieval hints, not proof of authority.

Approved parser policy, 2026-10-23: reject duplicate keys, unknown fields, missing
resources, unsupported language versions, and invalid digests. Optional `$schema`
is editor metadata only; it neither selects runtime semantics nor authorizes
fetching. The language discriminator determines runtime interpretation.

Further proposed checks: reject unsupported capabilities, unresolved resource
keys, and conflicting resource identities before running actions. Exact extension
mechanisms remain to be designed. An arbitrary JSON property cannot introduce a
new executable action. Proposed `kind`, `sha256`, rule-map, and predecessor-reference
syntax above is synchronized with the latest review proposal; the parser-policy
approval does not approve every proposed field or identifier restriction.

## Proposed bundle resource resolution

Proposal reviewed for current project conventions on 2026-10-25; not yet a
complete approved resolver contract. Each release has an isolated resource root.
An inventory resource path resolves relative to the standard document. Rule type
references resolve against that release's `types/`; type schema references resolve
relative to the containing type, and nested relative schema references relative
to the containing schema resource. Existing project definitions retain their
current project context; loading a release must not change that context globally.

For example, `rules/recipe.mdrule.json` references `recipe.mdtype.json`, which
resolves to `types/recipe.mdtype.json`. That type's `../schemas/recipe.schema.json`
resolves to the schema in this release. Inventory paths prohibit `..`; relative
schema references may contain it only when their resolved destination stays
inside the release. No similarly named local definition is a fallback.

Every resolved dependency file must appear in the release inventory and pass its
digest check. Internal schema fragments resolve within the bound schema resource.
Absolute schema identifiers and URI-based references need an explicit offline
mapping policy; they do not authorize network fetching. Escape through paths or
symlinks is rejected. Missing or unlisted dependencies are errors. Data-population
selection remains separate from this definition-resource namespace.

Still to specify: URI base/identifier mapping, canonical path comparisons,
relationship target-type bindings, duplicate declared type names across releases,
and exact loader capability/version activation. No existing mdrule version is
silently reinterpreted by this proposal.

## Transformation language contract

All operations belong to a closed, versioned vocabulary implemented by md-utils.
No scripts, subprocesses, dynamically loaded plugins, evaluated code, or executable
template escape hatches are permitted. Authors cannot expand file/network access
through a definition. Installation and dependency retrieval are separate from
execution. The user chooses permitted source/destination boundaries.

The operation vocabulary still needs specification. Candidate operations include
moving/renaming structured properties, setting explicit values, removing explicit
properties, and bounded literal text edits. No candidate is approved by this list.
Every operation needs normative input/output types, literal path rules, ordering,
missing/null behavior, conflict behavior, preservation guarantees, diagnostics,
and resource limits. File creation/deletion/moves, body changes, reference rewriting,
and transformations of custom local definitions require their own explicit decisions.

## Persistent review artifacts

Owner direction, 2026-10-23: generate a Markdown review report alongside staged
outputs. Use fenced `diff` code blocks with changed lines and a small amount of
surrounding context. CLI output points to the persistent report and summarizes
findings; it is not the sole copy of the review.

Proposed default: two unchanged lines before and after each changed region,
merging overlapping hunks. Include file paths, addition/removal counts, validation
findings, and explicit creates/deletes. Distinguish real file deletions from missing
staged files. Diff input is the exact source baseline and exact proposed bytes,
not independently rendered frontmatter. Expose whole-file serialization changes.

Example report section:

### `Kitchen/Recipes/soup.md`

```diff
--- before/Kitchen/Recipes/soup.md
+++ after/Kitchen/Recipes/soup.md
@@ -1,5 +1,5 @@
 ---
-title: Soup
+name: Soup
 ingredients:
   - lentils
 ---
```

Report generation must safely quote filenames and choose fences long enough for
arbitrary source content. It must not interpret document content as report HTML.
Report-size limits must disclose truncation and preserve access to complete staged
files; incomplete display is not complete review. Exact limits remain open.

## Review, apply, and cleanup semantics

The stage command creates proposed files and the report without changing originals.
Manual content edits to staged outputs are permitted as a provisional feature.
Recommend restricting edits to existing staged output files initially: manifest
paths, deletion intent, and authorization boundaries are not editable instructions.

Changing staged contents invalidates their previous assessment/review. Revalidate
the proposed collection, regenerate the report against the original baseline,
and require renewed review of the current output hashes. Apply must not silently
regenerate a changed report and immediately commit unseen changes. Exact commands
and review-token/confirmation mechanics remain to be specified.

Apply installs the reviewed staged bytes, not rerun transformations. It verifies
source and destination preconditions and relevant supporting evidence. Missing
staged output is a conflict, not an inferred deletion. Apply performs cleanup in
the SAME command after all intended writes and completion bookkeeping succeed.
No separate user cleanup command is required for successful operation.

On conflict, interruption, or partial completion, retain staging and recovery
information. Record completed writes so retries do not repeat them incorrectly.
Cleanup failure is distinct from write failure. No collection-wide atomicity is
promised. Retention of review reports after successful staging deletion and backup
retention are still open; proposed approach is to preserve a report/receipt outside
the temporary stage before deleting it.

## Deferred interoperability research

JSON-LD/YAML-LD integration was deferred by the owner on 2026-10-26. The
[Schema.org alignment proposal](../schema-org-alignment.md) and
[linked-data authoring proposal](../linked-data-authoring-proposal.md) retain
research for possible reconsideration. They are not specification deliverables
or mdstandards release prerequisites. Domain vocabulary research may inform
example standards without introducing linked-data processing.

## Next specification deliverables

Owner-approved release acceptance work is tracked in [#201](https://github.com/DandyLyons/md-utils/issues/201):
installable example standards, multiple migratable releases, different local
definitions, and fixture-first workflows. See [fixture plan](../mdstandards-fixture-plan.md)
and [recipe proposal](../md-recipes-proposal.md); domain details need owner approval.
Explicitly lossy imports are permitted with acknowledged loss; distinguish lossless
round trips from the ability to produce a conforming, but incomplete, export.
Discarding required fields prevents conforming export unless they are supplied
again. Exact acknowledgment syntax remains design work.

1. Settle standard identity, publisher trust references, and canonical comparisons.
2. Finalize standard fields, resource references, dependency closure, and predecessor
   rules; write valid/invalid JSON fixtures and a definition schema.
3. Specify adoption/population bindings and structural proof boundaries together.
4. Specify transformation endpoints, operation vocabulary, deterministic semantics,
   and standard migration versus import/export distinctions.
5. Specify stage/review/apply artifacts and manual-edit revalidation, with recovery
   examples and report retention decisions.
6. Specify exchange identities, target coverage, preservation, and compatibility.

The specification can be completed and reviewed without implementing the runtime.
Schema validation alone cannot prove resource resolution, structural implication,
migration correctness, publisher authority, or filesystem safety.
