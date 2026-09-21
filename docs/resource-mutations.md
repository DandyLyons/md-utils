# Writable resource planning (#90)

Resource mutation planning is a library contract, not an HTTP mutation implementation.
`ResourceMutationPlanner` combines an explicitly configured codec with the destination
resource's existing rule/type selection. It returns a complete proposed record,
diagnostics, and before/after conformance evidence without writing a store or file.
REST routes and commit coordination belong to #82; CLI `index apply` belongs to #142.

## Configure a writable representation

The existing read projection does not become reversible. A resource must declare
`writable` to support planning. Existing configurations without it remain read-only.
The current HTTP `operations` remain `list` and `get`, including when `writable` exists.

```yaml
serverConfigVersion: "1"
resources:
  - name: books
    route: /books
    operations: [list, get]
    selection:
      mode: ruleWithExpectedType
      rule: books
      type: Book
    identityPolicy:
      source: frontmatter
      path: [id]
      format: string
    writable:
      codec:
        frontmatterFields: [title, author, due]
        bodyWritable: true
        protectedFields: [internal]
      creation:
        template: |
          # Book

          {{ data.description }}
        inputSchema:
          type: object
          required: [frontmatter, data]
          properties:
            frontmatter:
              type: object
              required: [title]
            data:
              type: object
              required: [description]
```

The creation template is administrator-owned source, never a request-selected file
or template. `MarkdownUtilitiesTemplates` implements creation using #31's renderer;
Stencil stays outside Core/WASM. Omit `creation` to disable creation planning.
`protectedFields` defaults to an empty list. The server planner additionally protects
the entire top-level field containing its configured identity path. `$md-utils` is
always reserved. Unknown/read-only metadata fields fail even when their values equal
the existing values. Field names are literal top-level keys, not dotted paths.

## Create, replace, patch

Creation takes `MarkdownTemplateInput(frontmatter:data:)`, plus separately supplied
host identity, context, and protected metadata. It produces YAML frontmatter and a
rendered Markdown body. Neither schema defaults nor mdtype fix-its populate missing
values. Input-schema errors fail rendering; resulting mdtype/rule errors fail validation.
The input schema sees the combined client and host frontmatter envelope.

Given this record, assume the Book mdtype requires `title` and `# Book`:

```markdown
---
id: book-17
title: Old title
due: 2026-10-01
internal: retained
---
# Book

Original description.
```

| Library request | Proposed behavior |
| --- | --- |
| Create with title and description | Render the configured template, then validate the complete document. |
| Replace with title and body | Replace both; remove omitted writable `due`; retain `id` and `internal`. |
| Replace without title | Proposal lacks title, so Book validation fails; nothing is persisted. |
| Patch title only | Retain due, id, internal, and the exact existing body. |
| Patch `due: .set(.null)` | Store YAML null; this is not deletion. |
| Patch `due: .remove` | Delete the entry; removing an absent entry is a no-op. |
| Patch `title: .remove` | Proposal fails required-title validation. |
| Patch author with a new object | Replace the whole author value; no nested merging. |
| Replace body without `# Book` | Proposal fails the required-heading check. |

Replacement requires a body when `bodyWritable` is true. When false, body inputs
are rejected and the old body remains. Patch body omission means unchanged; an empty
string explicitly clears it. Edits never rerender the creation template. Nested-path
and heading/section edits are deferred. These are Swift request types, not a finalized
HTTP PATCH media type or wire format.

## Preservation and encoding

- Metadata-only edits retain the exact body bytes, including its newlines and Unicode.
- Body-only edits retain the exact existing frontmatter bytes, including comments.
- Metadata edits reserialize the block in its existing YAML/TOML format, with sorted
  keys. They preserve unaffected metadata values, not frontmatter comments, ordering,
  whitespace, or quote style. **Comments in frontmatter are not recommended.**
- Semantic no-ops retain the entire original source. YAML is used when adding a block
  to a document without frontmatter. Existing empty blocks are retained.
- TOML null is rejected, including null nested inside a supplied object or array.
- YAML aliases may expand to their parsed values; anchor/alias syntax is not preserved.
  Metadata edits involving merge keys, custom tags, or non-string keys are unsupported.
  Malformed/duplicate mappings fail parsing. No lossless YAML editing claim is made.
- Canonical LF delimiter lines are required. CRLF delimiter blocks, BOM-prefixed
  blocks, malformed closing lines, and non-Markdown paths are rejected. Body text can
  retain CRLF. Comment-wrapped non-Markdown sources are outside this version.
- The codec reparses its output and compares the intended metadata, format, and exact
  body bytes. Unrepresentable changes fail rather than silently changing values or
  interpreting requested body text as new frontmatter.

Serialization is deterministic for supported values. Creation inherits the shared
renderer's size limits and semantics; time-dependent Stencil features such as `now`
are not byte-deterministic. Existing-record hosts must enforce bounded source/request
sizes before invoking the in-memory codec.

## Validation and concurrency

For an existing record, construct `ResourceMutationSource` from complete authoritative
source plus its expected canonical revision. A missing/mismatched revision fails before
planning. Native indexed reads already provide bounded, revision-checked source through
`RecordStore.record(for:)`; metadata projections and cached FTS bodies are not inputs.
The codec cannot independently attest the provenance of arbitrary caller-supplied text.

The proposal keeps canonical identity/context, clears its new record revision, and
returns the baseline revision separately. It retains the original record for assessment.
Host-selected creation identity/path allocation and collection-wide uniqueness remain
responsibilities of the mutation coordinator, not the codec.

Destination enforcement is derived from resource configuration:

- `rule`: remain applicable and pass the rule's checks.
- `type`: conform to that mdtype and remain in its configured search directory.
- `ruleWithExpectedType`: remain applicable, pass the rule, and conform to the expected type.

The default `preserveExistingConformance` also preserves every currently satisfied
mdtype and every applicable, passing rule in the supplied collection registries,
including definitions with no public endpoint. Previously failing checks are not
additional blockers. Evaluation errors fail closed; an unknown baseline cannot
silently reduce the set being protected. Supply complete registries compiled with
the same type definitions, schemas, and runtime capabilities. Both assessments use
the same immutable registries and record context.

`endpointOnly` is an explicit per-mutation override. For example, a `/books/` edit may
remove a Story-required heading only in this mode, provided Book still passes.
`lostConformance` reports the lost checks and their diagnostics. `lostMembership`
separately reports types/rules that stop selecting the record: a rule may still select
an invalid document. Losing membership never deletes the canonical record.

`isValid` means the proposal passed planning-time validation. It is **not** a commit.
Diagnostics retain shared fix-its and RFC 0001 safety classifications. No fix-it is
automatically applied. Future persistence must atomically recheck the canonical
revision, enforce uniqueness, and publish reassessments for all affected resources.
All routes share one canonical record/revision domain. Index publication generations
and representation-specific HTTP ETags are distinct from this baseline revision.
Filesystem persistence followed by failed index publication requires explicit recovery
in the future mutation coordinator; SQLite cannot transact a filesystem write.

## Verification

```console
swift test --filter 'ResourceCodecTests|ResourceMutationValidatorTests|TemplateResourceCreationCodecTests|ResourceMutationPlannerTests'
swift test --filter IndexedMarkdownRepositoryTests
swift test
docker build --file Dockerfile.core-linux --tag md-utils-core-linux .
scripts/build-wasm.sh
```

The native integration test produces identical proposed source and baseline revisions
with metadata-only and FTS caches, rejects changed authoritative source, and verifies
planning did not alter the file. Server tests verify existing read routes, explicit
codec requirements, template creation, and failed validation leaving a store unchanged.
