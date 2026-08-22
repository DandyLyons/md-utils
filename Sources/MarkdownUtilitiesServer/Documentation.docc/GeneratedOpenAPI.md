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

Type-selected resources constrain `frontmatter` with the selected type's resolved
Draft 2020-12 schemas. Rule selection with an expected type deliberately retains the
generic envelope because nonconforming records remain successful responses; its
operation links the expected schema with an `x-md-utils-expected-frontmatter-schema`
extension. The logical-path operation uses `x-md-utils-catch-all` because OpenAPI path
templates do not express Hummingbird's `**` syntax.

Generation strictly validates the completed document. Unsupported schema constructs
produce ``MarkdownServerOpenAPIGenerationError`` diagnostics rather than a weakened
published contract.
