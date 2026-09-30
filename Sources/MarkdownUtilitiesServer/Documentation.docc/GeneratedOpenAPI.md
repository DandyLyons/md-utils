# Generated OpenAPI

Generate and publish an OpenAPI 3.1.1 contract for configured reads, writes, and mutation recovery.

## One Route Source

``MarkdownServerOpenAPIGenerator`` describes every configured route in ``EndpointPlan``:
reads, CRUD, identity edits, UUID repair, and operation status/recovery. Runtime
registration and generated paths use the same ``EndpointRouteDescription`` values,
including `/openapi.json`. Read and write methods can share a path: `/books` can
have both `get` and `post`, while `/books/{id}` can have `get`, `put`, `patch`, and
`delete`, each with its own operation identifier and request/response contract.

The endpoint plan is immutable after startup: its routes, codecs, and configured
policies stay fixed until restart. Records remain mutable through enabled write
operations. Successful mutations update canonical content and publish refreshed
identities, memberships, diagnostics, and index state without changing the route
plan. The generated OpenAPI document therefore stays stable across record edits,
even though record revisions and publication generations change.

The plan retains the resolved mdtype schemas and writable resource declarations
needed to generate the contract. Generation does not require scanning current
records or performing a mutation.

JSON and YAML are serialized from the same ``MarkdownServerOpenAPIDocument``.
Mapping keys are sorted, and equivalent configuration produces byte-identical output
for one format. The generated document has no host-specific `servers` entry.

```swift
let document = try MarkdownServerOpenAPIGenerator.generate(from: plan)
let json = try document.serialized(format: .json)
let yaml = try document.serialized(format: .yaml)
```

The native server exposes the JSON bytes at `GET /openapi.json`. Export without
importing Markdown records or starting the service with:

```bash
md-utils-server openapi \
  --project-root ./example/ \
  --format yaml \
  --output ./openapi.yaml
```

## Read Contracts

Components describe the generic record envelope, resource memberships, validity,
canonical identity, logical path, revision, diagnostics, collisions, and HTTP errors.
Every resource alias references the same canonical record components.

Collection operations return a bounded page with `records`, `generation`, and
nullable `nextCursor`. They declare `limit`, `cursor`, `pathPrefix`, `valid`, and
JSON-encoded scalar `filter` query parameters. `q` is declared only when the
resource enables search. Invalid queries return `400`, changed generations `409`,
oversized records `413`, and unavailable or changed sources `503`.

Type-selected resources constrain `frontmatter` with the selected type's resolved
Draft 2020-12 schemas. Rule selection with an expected type deliberately retains the
generic envelope because nonconforming records remain successful responses; its
operation links the expected schema with an `x-md-utils-expected-frontmatter-schema`
extension. The logical-path operation uses `x-md-utils-catch-all` because OpenAPI path
templates do not express Hummingbird's `**` syntax.

Generation strictly validates the completed document. Unsupported schema constructs
produce ``MarkdownServerOpenAPIGenerationError`` diagnostics rather than a weakened
published contract.

## Mutation Contracts

Explicitly enabled create, replace, patch, delete, identity-edit, and UUID-repair
routes are included alongside their named-lookup and exact-path aliases. Operation
status and recovery routes share the same durable receipt component. A writable
codec alone does not advertise writes: configuration version `3` requires separate
`mutations.operations` opt-ins. The resource's `operations` array continues to
declare reads. Versions `1` and `2`, and resources without mutation opt-ins,
advertise only their configured read routes.

For a resource rooted at `/books`, the generated contract includes these primary
routes when the corresponding mutations are enabled:

| Operation | Method and path | Request body |
| --- | --- | --- |
| Create | `POST /books` | Writable `frontmatter`, template `data`, creation-only `identifiers`, optional `filename` |
| Replace | `PUT /books/{id}` | Complete writable `frontmatter` and `body` when writable |
| Patch | `PATCH /books/{id}` | Optional `frontmatter.set`, `frontmatter.remove`, and writable `body` |
| Delete | `DELETE /books/{id}` | Absent or an empty object |
| Identity edit | `POST /books/{id}/identity` | Configured `identifiers` |
| UUID repair | `POST /books/{id}/repair-uuid` | Empty object |
| Operation status | `GET /books/_operations/{id}` | None; `id` identifies a receipt |
| Resolve recovery | `POST /books/_operations/{id}/resolve` | `decision`: `confirmCommitted` or `confirmNotCommitted` |

Status and recovery routes accompany a resource's mutation configuration.
Named-lookup and exact-path aliases retain the same revision, validation, and
receipt contracts. A mutation changes one canonical document across all of its
resource aliases. DELETE removes that document, rather than only its membership
in the addressed resource.

Requests describe the configured top-level writable fields, body capability,
creation identifiers, identity-edit fields, and validation-policy override.
For example, an enabled PATCH with writable `title` accepts:

```http
PATCH /books/book-17
Content-Type: application/json
MD-Utils-If-Revision: r1.YWJj

{"frontmatter":{"set":{"title":"Revised title"}}}
```

The example token encodes revision `abc`; use the actual `MD-Utils-Revision` token
returned by a read. The versioned Base64 token represents the canonical source
revision, independently of representation ETags and publication generations.
Creation instead requires an `Idempotency-Key`. Unknown envelope fields are rejected.
PATCH null stores null where supported; remove explicitly deletes a field. PUT
requires the complete writable projection. Full destination and preservation
validation still runs after schema validation.

Request schemas restrict property names to the configured writable or identifier
fields and reject unknown envelope keys. They describe request envelopes separately
from read representations: clients cannot submit a generic record envelope as an
update. Required destination values, protected identifiers, cross-resource
conformance, and uniqueness are assessed against the complete proposed record at
runtime; a schema-valid request can still receive `422` or a conflict response.

## Receipts, Revisions, and Recovery

Successful creates return `201`; other completed writes, including DELETE, return
`200` with a receipt. Receipt dates are numeric seconds since 2001-01-01 UTC.
Structured errors include shared diagnostics and fix-it proposals. Template
validation failures return `422`; Knap warnings remain in receipt diagnostics and
survive replay. No fix-it is automatically applied by this contract.

Ordinary success requires publication. A `503` may contain a receipt with committed
source and publication pending, or uncertain recovery state; it does not imply
rollback. Follow `operationStatus` before retrying. Status reads return `200` even
for incomplete operations. Recovery can return `200`, `201`, `409`, or `503` with
a receipt. Shared components preserve these shapes across resource aliases.

Read freshness and generation headers remain documented alongside canonical
revision headers. New publication invalidates pagination cursors; no cross-filesystem
and SQLite transaction is implied.
