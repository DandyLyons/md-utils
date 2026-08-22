# ``MarkdownUtilitiesServer``

Persist canonical Markdown records, compile explicit resources, and serve immutable native reads.

## Overview

`MarkdownUtilitiesServer` defines the transport-neutral contract shared by runtime
route registration and OpenAPI generation. It also provides native project loading
and the generic Hummingbird 2 adapter. The `md-utils-server` executable remains the
thin owner of command-line options, logging, application construction, and process
lifecycle.

The module also defines the storage-neutral ``RecordStore`` contract. Stores persist
canonical `MarkdownRecord` values without treating filesystem paths, SQL, parsed
frontmatter, or type indexes as universal storage concepts.

``MarkdownServerReadSnapshotBuilder`` composes that storage boundary with an
``EndpointPlan``, compiled rules, and a type registry. It performs selection and
assessment once at startup and returns immutable ``MarkdownServerReadSnapshot``
state for concurrent request handling. See <doc:ReadSnapshots>.

Server resources are opt-in. A loaded rule or mdtype is never exposed unless a
``MarkdownResourceConfiguration`` references it explicitly.

```swift
import MarkdownUtilitiesCore
import MarkdownUtilitiesServer

let book = MarkdownTypeDefinition(
  name: MarkdownTypeName(rawValue: "Book"),
  version: "1"
)
let registry = try MarkdownTypeRegistry(definitions: [book])
let configuration = MarkdownServerConfiguration(resources: [
  MarkdownResourceConfiguration(
    name: "books",
    route: "/books",
    operations: [.list, .get],
    selection: .type(
      name: MarkdownTypeName(rawValue: "Book"),
      searchRoot: "books/"
    ),
    identityPolicy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
  )
])
let ruleRegistry = try MarkdownRuleCompiler(typeRegistry: registry).compile([])
let plan = try EndpointPlanCompiler(
  ruleRegistry: ruleRegistry,
  typeRegistry: registry
).compile(configuration)
```

## Canonical record storage

``RecordStore`` fetches records by stable identity, enumerates bounded pages, and
performs revision-checked mutations. Revisions are opaque and store-owned: create
and replace return the canonical stored record with its assigned revision, while
replace and delete atomically compare an expected revision.

```swift
let proposed = MarkdownRecord(
  identity: MarkdownRecordIdentity(rawValue: "dune"),
  content: "# Dune"
)
let store = try InMemoryRecordStore()
let created = try await store.create(proposed)

let page = try await store.records(matching: RecordStoreQuery(limit: 100))
```

Enumeration is ordered deterministically by stable identity. ``MarkdownSearchRoot``
narrows records by their collection-relative logical paths; the collection root
also retains records without a logical path. ``RecordStoreContinuationToken`` is
opaque and scoped to the query that produced it. Paging is bounded but does not
provide snapshot isolation across mutations.

``RecordStoreError`` exposes stable not-found, conflict, invalid-record,
invalid-query, and unavailable categories. Cancellation propagates as
`CancellationError`. Canonical Markdown is not parsed or assessed at this boundary,
so malformed YAML or nonconforming content remains representable. Parsed views,
conformance indexes, and resource projections are derived state that can be rebuilt.

``InMemoryRecordStore`` is the portable reference implementation. It is intended
for tests and composition work, not as a production persistence selection.

## Selection modes

``MarkdownResourceSelection`` keeps three behaviors distinct:

- Rule selection includes records for which a named rule is applicable.
- Type selection includes conforming records beneath an explicit collection-relative
  directory such as `books/`; `.` selects the collection root.
- Rule selection with an expected type preserves rule-selected candidates even when
  they fail the expected type, allowing the read snapshot to expose validity and
  diagnostics.

Type conformance is non-exclusive. Multiple planned resources may reference the
same type, and one canonical record may appear through each resource without
creating a route or identity collision.

## Routes and operation identifiers

The initial read-only operations are `list` and `get`. They produce `GET /books`
and `GET /books/{id}` respectively. Operation identifiers default to
`books.list` and `books.get`; ``MarkdownOperationIDOverride`` provides an explicit
override when required.

When at least one configured `get` operation enables logical-path fallback, the
plan includes one reserved `GET /_md-utils/path/{path...}` route. Resource routes
cannot use the `/_md-utils` namespace.

``EndpointRouteDescription`` values contain only an HTTP method, canonical path
template, semantic route kind, optional resource name, and stable operation ID.
``MarkdownServerHTTPAdapter`` installs these routes in Hummingbird 2. Issue #84
generates OpenAPI 3.1 from the same ``EndpointPlan``.

## Startup validation

``EndpointPlanCompiler`` validates all resources before a server accepts requests.
It reports unsupported versions, missing references, unsafe paths,
duplicate names or operations, route ambiguity, and operation-ID collisions in one
``EndpointPlanCompilationError``. Diagnostics have stable codes and configuration
locations and are deterministically ordered.

Equivalent resource and operation orderings produce the same immutable,
`Sendable` plan. The read snapshot consumes the plan's selection, identity, and
projection policies without mutating the plan.

## Configuration boundary

``MarkdownServerConfiguration`` is a versioned `Codable` model, currently version
`1`. ``MarkdownServerProjectLoader`` decodes the human-authored YAML at
`.md-utils/server/server.yaml`, loads rules and mdtypes, recursively imports Markdown, and
builds the immutable plan and snapshot before route registration. Server
configuration is separate from the md-utils CLI configuration and does not extend
`.md-utils/md-utils.json`.

## Topics

### Read-side composition

- <doc:ReadSnapshots>
- <doc:NativeReadOnlyServer>
