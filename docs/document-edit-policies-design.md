# Derived FileEditPolicy implementation design

Status: clarified on 2026-09-22. FileEditPolicy is an internal derived model, not
a new YAML configuration interface. The earlier proposal for authored editPolicy
declarations and editable/identityOnly/immutable modes is withdrawn.

See [REST mutation design](rest-mutation-design.md). Users do not author a policy
for each file. No new policy property is added to mdtype or mdrule schemas.
Existing types, rules, resource codecs, identity configuration, and shared mutation
invariants supply the inputs.

## Purpose

The mutation layer associates each authoritative document revision with an
explainable FileEditPolicy: satisfied types, applicable rules and their validity,
resource memberships, writable representations, protected identifiers, and revision.
Include definitions without public endpoints. This is regenerated derived state,
not a policy stored in the Markdown document.

FileEditPolicy is a working Swift name. Keep portable assessment primitives in
Core and server/resource composition in the server module. Native hosts supply
authoritative source and collection checks; Core remains independent of SQLite.

## Restrictions versus conditional edits

- A resource's operation opt-ins and codec determine which inputs it accepts.
- Protected identifiers require explicit identity editing; persistent UUID changes
  require the distinct repair operation. Alternate resources cannot bypass these
  document-wide identity protections.
- A required title is not an immutable title. Changing its value can be allowed;
  removing it fails when the resulting document must still conform to Book.
- A required heading constrains the result, not every body edit.
- Compound schemas and rule predicates require assessing the complete proposal.
  An independent boolean per field cannot represent all allowed edits.
- Collection uniqueness, source revisions, and filesystem persistence require host
  checks in addition to per-document validation.

Do not infer immutable or delete-deny semantics from structural conformance alone.
Do not turn JSON Schema annotations or type names into invented edit restrictions.
One resource's narrower ordinary writable projection does not globally freeze a
field; shared protected identity invariants do apply across resources.

## Derivation and assessment

1. Read authoritative source and assess complete, consistent loaded registries.
   Bind baseline evidence to source revision and configuration fingerprint.
2. Resolve destination operation/codec and document-wide identity protections.
3. Use #90 to construct the complete proposed document.
4. Reassess the result. By default preserve all previously satisfied loaded types
   and applicable passing rules, including unexposed definitions. Enforce destination
   membership and validation. Keep the existing explicit endpointOnly override and
   its separate conformance/membership loss report.
5. Produce an explained rejection or planning approval with outstanding host checks.
6. Recheck revisions, configuration validity, uniqueness, and persistence conditions
   under writer coordination before committing. Regenerate/invalidate derived policy
   after writes, external refresh, membership changes, or configuration changes.

Baseline evidence prevents a request from dropping a type marker and pretending the
old contract never applied. endpointOnly may explicitly waive preservation of other
conformance; it does not waive protected identity handling. Previously failing checks
do not become new blockers unless required by the destination. Evaluation errors
fail closed, distinct from ordinary nonconformance.

Creation has no old values to preserve: assess the rendered proposal, destination,
creation inputs, and identity allocation. DELETE checks enabled operation, identity,
and revision, without requiring a nonexistent remaining document to conform.
These preserve the accepted #90/#82 semantics.

## Examples

| Requested edit | Derived explanation |
| --- | --- |
| Replace Dune with Dune: Revised Edition as title | Allowed if destination exposes title and complete result passes required contracts. |
| Remove Book's required title | Rejected with Book schema location and required-field diagnostic. |
| Remove Story's required heading through books | Rejected by default because baseline Story conformance must be preserved. |
| Same heading edit with endpointOnly | May pass if destination passes; report lost Story conformance/membership. |
| Change ISBN by ordinary PATCH through another alias | Rejected: protected identifier requires explicit identity edit. |
| Correct ISBN by explicit identity edit | Conditional on validation, uniqueness, and revision checks. |
| Change persistent UUID by ordinary identity edit | Rejected: use dedicated UUID repair. |
| Edit body through a resource with bodyWritable false | Rejected there; another body-writable resource can permit it if document constraints pass. |

## Internal representation proposal

Use a revision-bound value containing baseline contract evidence, document-wide
restrictions with origins, and resource-specific operation capabilities. An
assessment method consumes a proposal and returns diagnostics, conformance and
membership changes, and outstanding collection checks. It explains conditional
permission rather than precomputing every possible mutation.

Origins identify type/rule names, constraint IDs, schema locations, resource codec
settings, or identity invariants. No new public explain endpoint is implied.
Avoid a corpus-sized policy cache: derive in bounded work and optionally cache
revision/fingerprint-keyed summaries. Indexed summaries cannot replace authoritative
mutation-source acquisition.

## Verification

Cover overlapping resources, unexposed definitions, required-versus-immutable
distinctions, compound constraints, selected-but-invalid remediation, endpointOnly,
protected identifier bypass attempts, stale source/configuration, evaluator errors,
creation/deletion differences, and shared CLI/REST decisions. Deriving a policy
must not modify source files.
