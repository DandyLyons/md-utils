# Native REST mutations

Config v3 adds opt-in writes to the indexed native server. Versions 1 and 2 remain
read-only. Generate its local editor schema with
`md-utils-server schema --schema-version 3`. No mdtype/mdrule edit-policy YAML is
required: the server derives `FileEditPolicy` from each source revision, loaded
contracts, resource membership, codecs, and protected identifiers.

Example `.md-utils/server/server.yaml` (requires a loaded `books` rule selecting
`books/`, and an existing destination directory):

```yaml
serverConfigVersion: "3"
persistentIdentity: {path: [uuid]}
resources:
  - name: books
    route: /books
    operations: [list, get]
    selection: {mode: rule, rule: books}
    identityPolicy: {source: frontmatter, path: [isbn], format: string}
    lookups:
      - {name: uuid, source: persistentIdentity}
      - {name: slug, source: frontmatter, path: [slug], format: slug, slugPolicy: unicode}
    writable:
      codec: {frontmatterFields: [title, slug, subtitle], bodyWritable: true}
      creation: {template: "# Book\n{{ data.description }}"}
    mutations:
      operations: [create, replace, patch, delete, identity, repairUUID]
      identityFields: [isbn]
      idempotencyRetentionSeconds: 604800
      creation:
        directory: books/
        filenameField: title
        collision: reject
        identifiers: [isbn]
        slug: {field: slug, sourceField: title, policy: unicode, collision: reject}
```

`operations` declares reads; `mutations.operations` independently enables writes.
Declaring a writable codec alone does not install write routes. All writes use the
existing bounded native index and authoritative files; no second corpus cache is
created. The existing generated OpenAPI explicitly labels itself **read-only**;
mutation OpenAPI remains #108.

## Requests and revisions

| Operation | Primary route | Input |
| --- | --- | --- |
| Create | `POST /books` | `frontmatter`, template `data`, creation-only `identifiers`, optional `filename` |
| Replace | `PUT /books/{id}` | Required `frontmatter` object; required `body` when writable |
| Patch | `PATCH /books/{id}` | Optional `frontmatter: {set: {...}, remove: [...]}` and optional `body` |
| Delete | `DELETE /books/{id}` | No body or an empty object |
| Identity edit | `POST /books/{id}/identity` | `identifiers` object containing configured identity fields |
| UUID repair | `POST /books/{id}/repair-uuid` | Empty object; host generates a new UUID |

Named lookup routes accept the corresponding item methods, including query-value
transport. For example `PATCH /books/by/uuid/{uuid}` and
`POST /books/by/uuid/identity?value=...` for identity editing. Ambiguity never chooses a candidate. When resolving a collision,
address a document explicitly with
`POST /books/_mutations/identity/by-path?path=books%2FDune.md`.
The same `/_mutations/<operation>/by-path` pattern supports replace, patch, delete,
and repairUUID. Every route checks resource membership, including exact paths.

Item reads and committed writes return `MD-Utils-Revision`. Send its exact value
as `MD-Utils-If-Revision` for every item mutation. The reversible wire format is
`r1.` followed by canonical standard Base64 of the opaque revision's UTF-8 bytes.
Native revisions are SHA-256 source hashes. These are not revision history,
representation ETags, weak validators, wildcards, or index generations.

```http
POST /books
Content-Type: application/json
Idempotency-Key: add-dune-1

{"frontmatter":{"title":"Dune"},"identifiers":{"isbn":"9780441172719"},"data":{"description":"Desert planet."}}
```

This creates `books/Dune.md`, stores ISBN on creation, generates a UUID because the
resource opted into persistent UUID lookup, and fills the missing slug. Existing
documents need no UUID. Clients cannot supply the host UUID in creation input.

```http
PATCH /books/9780441172719
Content-Type: application/json
MD-Utils-If-Revision: <exact token from the read>

{"frontmatter":{"set":{"title":"Dune: reading notes","subtitle":null},"remove":["slug"]}}
```

This changes metadata without renaming the file. Slug lookup alone makes neither
uniqueness nor protection mandatory. Configured constraints still apply.
Explicit null stores null; removal deletes. Omitting a patch field leaves it alone.
Duplicate removal entries, set/remove overlap, unknown fields, and body null fail.
Top-level metadata names are literal; nested objects replace whole field values.
PUT removes omitted exposed metadata fields, preserves protected/unexposed values,
and rejects an omitted writable body. Required fields are enforced by validation.

Updates and identity edits default to `preserveExistingConformance`. Explicit
`validationPolicy: endpointOnly` permits losing other prior conformance while
still enforcing the destination, identifier protections, and uniqueness. Receipts
include policy, lost conformance/membership names, and detailed changes/diagnostics.
Previously failing checks do not become new blockers unless the destination needs
them. Structural requirements do not imply immutable fields or delete denial.
DELETE removes the canonical file and every alias; it is not membership removal.

## Allocation, identity, and source preservation

An explicit `filename` must be a single Markdown filename. Otherwise `filenameField`
supplies the expressive stem and `.md` is appended. Names are not normalized;
unsafe paths and symlinks are rejected. Configured directories must exist.
Filename collision defaults to rejection. `collision: suffix` allocates
`Name (1).md`, etc., under the writer lease without overwriting any file.

Slug generation accepts a configured metadata `sourceField`; `$filename` means
the filename without its extension. Missing/non-string sources fail when generation
is needed. Supplied slugs are validated and preserved. Slug `collision: suffix`
optionally tries `slug-1`, etc., only for generated values when a configured
uniqueness requirement conflicts. Slugs are never synchronized after title changes.

Default identity fields, explicitly protected lookups, codec-protected fields, and
the persistent UUID are protected across resources selecting either the baseline
or proposal. Ordinary edits cannot bypass them by changing membership. ISBN-like
fields use creation-only input and explicit identity edits. UUIDs are excluded from
ordinary identity editing; explicit repair generates a new UUID for the selected
document and does not rewrite backlinks. With no reliable provenance identifying
an original, choose the intended duplicate by path. #152 can later supply evidence
for safe automatic duplicate selection; timestamps alone are not that evidence.

Metadata edits preserve body bytes and unaffected metadata **values**, but may
reserialize the entire frontmatter block, losing its comments/formatting. Body-only
edits preserve frontmatter bytes. Semantic no-ops preserve source bytes. Unsupported
representations fail through #90's codec. Input and proposed source are bounded to
8 MiB. Fix-its remain structured proposals and are never automatically applied.

## Commit, retry, and recovery

The shared `MarkdownMutationService` is usable without HTTP. Its native coordinator
acquires a collection-level OS writer lease, refreshes authoritative evidence,
checks revisions and constraints, then persists through a lease-bound `RecordStore`.
Refresh, CLI index update, and text rebuild use the same lease. Source replacements
are atomic; creation uses an atomic no-clobber claim. Existing POSIX permissions are
preserved on replacement. The portable implementation does not promise retention
of inode identity, extended attributes, ACLs, or file birth time.

Unrelated editors do not take the lease and can still race the final revision check
and replacement. External edits detected before commit reject the write. A change
after commit that prevents publication of that revision requires recovery.

Durable receipts live in `.md-utils/mutations/`, separately from rebuildable SQLite
projections and pending drafts. States are prepared, committed, completed,
recoveryRequired, and abandoned. Intent is synced before source persistence;
completed success requires refreshed membership, identity, diagnostics, and FTS
publication. There is no filesystem/SQLite transaction or claimed source rollback.

Creation requires an `Idempotency-Key` of 1–256 bytes. Keys are scoped to resource
and operation; sorted JSON payloads are compared. The same key returns the original
receipt, even after later edits/deletion. Changed input conflicts. Terminal receipts
expire after the configured retention (default seven days) and are pruned on a
subsequent mutation. Unresolved operations never expire. Use a new key only when
intentionally creating another document.

Responses include the receipt ID, state, canonical path/revision, `committed`, and
`operationStatus` URL. `committed: true` means persistence is confirmed. A crash
window with no durable confirmation returns `committed: null`, not a false claim
that nothing changed. Publication-pending responses use status 503 with
`mutation.publication-pending`; indeterminate outcomes use
`mutation.recovery-required`. An ordinary success is 201 for creation, otherwise 200.

`GET /books/_operations/{id}` inspects a receipt without writing. Restart retries
confirmed commits whose source still matches, without rewriting source. An
indeterminate intent or externally changed source requires operator action:

```http
POST /books/_operations/{id}/resolve
Content-Type: application/json

{"decision":"confirmCommitted"}
```

`confirmCommitted` is an explicit operator assertion, accepted only if current source
matches the proposed revision (or confirmed deletion). `confirmNotCommitted` requires
the baseline source or originally absent path and marks the intent abandoned; it
cannot override a confirmed commit. Neither choice edits source. If source matches
neither outcome, both fail, retaining the receipt for investigation. Status and
resolution are resource-scoped. Recovery decisions are not an automatic inference
from matching bytes or a missing file.

Errors: malformed input 400, missing item 404, disabled operation 405/router 404,
identity/key conflict 409, stale revision 412, size 413, media 415, invalid proposal
or protected edit 422, missing revision 428, unavailable/pending recovery 503.
