# Generated OpenAPI

Generate and publish one deterministic OpenAPI 3.1.1 contract from the immutable endpoint plan.

## One Route Source

``MarkdownServerOpenAPIGenerator`` consumes only ``EndpointPlan``. The plan retains
its referenced resolved mdtype frontmatter schemas, so generation does not require a
mutable registry or resource provider. Runtime registration and generated paths use
the same ``EndpointRouteDescription`` values, including `/openapi.json`.

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

## Record and Schema Contracts

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
codec alone does not advertise writes.

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
