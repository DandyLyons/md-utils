# MarkdownUtilities Server Architecture

- Status: mdtype and portable rules prerequisites implemented; server design can proceed
- Last updated: 2026-08-02

This document records the architectural direction for exposing Markdown-backed data through conventional HTTP APIs. It distinguishes implemented foundations, decisions already made, the next recommended milestone, and questions that still require explicit design.

## Objective

Build an HTTP server framework in which maintainers expose ordinary application resources while Markdown remains a persistence implementation detail.

API clients should interact with domain resources such as books, documents, or projects. They should not need to know that the server persists those resources as Markdown containing YAML frontmatter and structured body content.

For example, an API might expose `/books/{id}` while internally storing the resource as canonical Markdown. The API resource, its HTTP representation, and its Markdown storage representation are deliberately separate concepts.

The server should use existing mdtype definitions to derive as much validation, discovery, and OpenAPI structure as is safe. It must not infer exposure, authorization, routes, identifiers, or write behavior solely from the existence of a type definition.

## Current Assessment

The original type-system prerequisite has been met. The project now has enough portable infrastructure to begin a server-focused design and prototype.

### Implemented foundations

- `MarkdownUtilitiesCore` and `MarkdownUtilities` have an enforced portable/native boundary.
- Core builds and runs on Linux and through the supported Swift WASI toolchain.
- `MarkdownRecord` represents canonical content with optional identity, revision, logical path, storage context, type hints, and attributes.
- `MarkdownRecordPath` provides portable, collection-relative path normalization and glob matching.
- mdtype v1 is implemented across definitions, registry compilation, JSON Schema resolution, structural assessment, type hints, diagnostics, and in-memory fix-its.
- mdtype definitions are loaded recursively from `.md-utils/types/` by the native integration.
- reusable rule definitions, applicability, type-based selection, checking, and structured assessments are available in `MarkdownUtilitiesCore`.
- native adapters can read filesystem records, construct logical paths, resolve project-confined schema resources, and write records atomically.
- `MarkdownUtilitiesServer` defines the asynchronous, storage-neutral `RecordStore` contract and actor-backed `InMemoryRecordStore` reference implementation.
- `MarkdownServerReadSnapshotBuilder` performs one bounded scan, reuses one analysis per candidate, and builds immutable generic record, membership, validity, identity, and lookup indexes.

The normative type design is documented in [RFC 0001: mdtype](rfcs/0001-mdtype.md). The portable dependency and runtime status is documented in [WebAssembly Support](webassembly.md).

### Remaining server foundations

The following pieces do not yet exist:

- a domain-resource projection and encoding contract;
- a public schema-introspection API suitable for generators outside `MarkdownUtilitiesCore`;
- OpenAPI generation from exposed resources;
- server request semantics, HTTP error mapping, resource pagination, and query behavior;
- native HTTP or Cloudflare Workers distributions; and
- persistent type indexes or a production storage backend.

The next blocker is native HTTP adaptation of the accepted generic read representation.

## Decisions

### Ship Native and Cloudflare Distributions

The project should eventually ship two server solutions sharing the same semantics and portable core:

1. A conventional native Swift server for Linux and other supported server environments.
2. A Cloudflare Workers distribution that uses WebAssembly where necessary.

These are two runtime distributions of the same architecture, not necessarily identical HTTP implementations.

### Use One Immutable Endpoint Plan for Routing and OpenAPI

At startup, the server must compile loaded rules, mdtypes, and explicit resource configuration into one deterministic, immutable `EndpointPlan`. The same plan registers runtime routes and generates the OpenAPI 3.1 description. This prevents the running server and its published contract from drifting.

The authoring and startup flow is:

```text
normalized rule definitions + runtime capabilities + mdtype definitions + explicit resource configuration
                              ↓
                  immutable EndpointPlan
                         ↙             ↘
          registered runtime routes    OpenAPI 3.1 document
                         ↘             ↙
                    shared contract tests
```

The implemented plan contains resource names, routes, read operations, selection policy, expected types, projection policy, identity policy, and stable operation identifiers. Rules are first compiled by Core into one `MarkdownRuleRegistry`; endpoint planning and read snapshots consume that same registry. `MarkdownUtilitiesServer` compiles the versioned `Codable` resource configuration into immutable, `Sendable` values and reports invalid references, unsafe paths, duplicate or ambiguous routes, and operation-ID collisions before a server begins accepting requests. Missing rule capabilities, invalid JMESPath, and unresolved schemas fail during rule compilation at startup.

The OpenAPI document is inspectable, versionable output from the plan. It is not an input to Swift source generation. Resource-specific Swift code, Swift OpenAPI Generator, build plugins, and generated server protocols are explicit non-goals. Native and Workers transports use generic handlers backed by the same endpoint semantics.

This decision is tracked in [issue #77](https://github.com/DandyLyons/md-utils/issues/77) and [issue #84](https://github.com/DandyLyons/md-utils/issues/84).

### Use Hummingbird 2 for the Native Server

The native server distribution uses Hummingbird 2. A `MarkdownUtilitiesServer` library target owns server planning and generic HTTP behavior, while an `md-utils-server` executable loads configuration, builds the immutable plan, composes dependencies, and starts Hummingbird.

Hummingbird is an adapter around the resource and repository semantics. Core selection, identity, validation, and projection behavior must remain testable without an HTTP server and reusable by the future Workers distribution.

### Keep the Portable Core Boundary

The implemented target boundary is the foundation for both server distributions:

```text
MarkdownUtilitiesCore
├── Portable Markdown records, documents, and parsing
├── Frontmatter conversion
├── mdtype definitions and assessment
├── Rule definitions and assessment
├── Structured diagnostics and fix-its
└── In-memory mutation

MarkdownUtilities
├── MarkdownUtilitiesCore
├── Filesystem records and schema loading
├── Configuration loading
├── Extended attributes
└── Other native integrations

MarkdownUtilitiesServer
├── MarkdownUtilitiesCore
├── Storage-neutral RecordStore and InMemoryRecordStore
├── Explicit versioned resource configuration
├── Deterministic EndpointPlan compilation
├── Transport-neutral route descriptions
└── Structured startup diagnostics

md-utils
├── MarkdownUtilities
├── ArgumentParser commands
├── CLI presentation and prompts
└── Process exit behavior
```

`MarkdownUtilitiesCore` runs on Linux and compiles to WebAssembly. It avoids direct filesystem access, process execution, CLI dependencies, and platform-specific APIs. Linux support is verified with `Dockerfile.core-linux`; WASI compilation and representative runtime behavior are verified with `scripts/build-wasm.sh`.

`MarkdownUtilities` contains functionality appropriate for native platforms but unavailable or unsuitable in WebAssembly. The `md-utils` executable is not a server runtime and must not be spawned by server code.

The standalone `md-utils-server` executable will own configuration-file loading and Hummingbird 2 application composition. Its server configuration remains separate from the md-utils CLI configuration and `.md-utils.json`.

### Treat Types and Rules as Distinct Server Inputs

The type and rule prerequisites are now implemented as library concepts:

- A **Markdown type** answers whether a record structurally conforms to a named type such as `Book`.
- A **rule** selects records and applies validation or policy checks to them.

Types should drive resource discovery, read validation, write conformance, and derived type membership. Rules should drive explicitly configured policy checks at defined lifecycle points. A matching rule is not a type, and rule applicability is not conformance.

The server must not automatically enforce every loaded rule on every endpoint. Resource exposure configuration must state which rule sets, if any, participate in reads, writes, or administrative diagnostics. This avoids turning local lint policy into an undocumented HTTP contract.

### Use Whole-Markdown Structural Conformance

mdtype v1 assesses complete Markdown records across:

- YAML frontmatter using JSON Schema Draft 2020-12;
- headings and heading relationships;
- section presence and direct content;
- body line and word limits; and
- logical record paths.

Requirements affect conformance. Recommendations produce advisory diagnostics without causing conformance to fail.

Conformance is structural and non-exclusive. One record may simultaneously conform to `Book`, `Document`, and `Publishable`. A query for `Book` records returns every record conforming to `Book` regardless of its other type memberships.

Type hints can accelerate candidate selection, but they are not proof. Server reads and writes that claim a resource type must use successful assessment, not an unverified hint or path match.

### Allow One Record Through Multiple Resource Routes

Resource membership is many-to-many. A canonical record may conform to multiple mdtypes, and multiple explicitly exposed resources may therefore address that same record. For example, if one record conforms to both `Person` and `Author`, illustrative routes such as `GET /people/c-s-lewis.md` and `GET /authors/c-s-lewis.md` may both resolve successfully.

These routes are two resource views of one stored record, not two records or an identity collision. The server model must distinguish:

- **canonical record identity**, which is global within the configured store or collection;
- **resource membership**, which says that the record is selectable through a configured resource;
- **resource-local lookup**, which resolves an identifier within that resource; and
- **resource projection and policy**, which may produce different response fields, links, diagnostics, or authorization decisions for the same canonical record.

Within one resource collection, results are deduplicated by canonical identity. Across different resources, repeated exposure is expected. When two routes return the same canonical content, they should expose the same record identity and revision even if their projections differ.

Future mutations must preserve this aliasing model. Updating through either resource updates the one canonical record, uses the same revision/precondition domain, and reassesses every affected membership and policy before commit. Delete and “remove from this resource” are not interchangeable: deleting the canonical record affects all routes, while removing structural membership would require a content mutation that makes the record cease to conform. Exact mutation semantics remain deferred to the mutation RFC.

### Treat Markdown Records as Canonical Data

Canonical Markdown content does not have to exist as an ordinary filesystem file. It may be stored as an exact Markdown string or byte sequence inside another persistence system, including SQLite.

`MarkdownRecord` is implemented as the storage-neutral value:

```text
MarkdownRecord
├── optional stable identity
├── canonical Markdown content
├── context
│   ├── optional logical path
│   ├── optional storage metadata
│   ├── type hints
│   └── host attributes
└── optional revision or content hash
```

The persistence abstraction operates on records rather than assuming direct filesystem paths:

```text
RecordStore
├── InMemoryRecordStore
├── FileRecordStore
├── SQLiteRecordStore
└── future object-store adapters
```

Parsed JSON, search indexes, cached type memberships, and generated API representations are derived data. They must be rebuildable from canonical Markdown records and the versioned definitions that produced them.

### Keep Markdown Encoding Behind the Repository Boundary

Type assessment answers whether a record conforms. It does not define a reversible mapping between arbitrary domain JSON and canonical Markdown.

A typed repository must compose four concerns:

```text
RecordStore
    + MarkdownTypeRegistry
    + configured Markdown rules
    + ResourceProjection / ResourceCodec
                    ↓
           TypedMarkdownRepository
```

Conceptually, the repository must support:

```text
load a canonical record by stable identity
find records that fully conform to an expected Markdown type
project a conforming record into its public resource representation
validate and encode a proposed create or update
apply configured rules before committing
commit with revision-aware concurrency control
return structured errors and advisory diagnostics
```

The portable `MarkdownTypeFixer` is not a general write codec. It applies selected repairs to an existing record; it does not define how an arbitrary API request creates a complete Markdown document.

## Deriving Endpoints from mdtype

### What mdtype can provide

An mdtype definition provides useful endpoint-generation inputs:

- a stable type name and contract version;
- a JSON Schema view of schema-visible frontmatter;
- required and recommended body structure;
- logical-path constraints;
- deterministic conformance assessment;
- structured validation diagnostics; and
- non-exclusive type membership.

These inputs are sufficient to generate validation hooks, diagnostic schemas, type-filtered repository queries, and part of an OpenAPI component schema.

The current registry compiles and caches resolved frontmatter schemas for assessment, but its resolved-schema accessor is internal to `MarkdownUtilitiesCore`. Server generation therefore needs a deliberate public introspection model. That API should expose stable schema inputs without exposing mutable registry internals.

The OpenAPI generator must also define which JSON Schema constructs it can translate, preserve, or reject. Unsupported or ambiguous schema features must produce generation diagnostics rather than a silently weakened HTTP contract.

### What mdtype cannot safely infer

mdtype v1 intentionally does not define:

- whether a type should be publicly exposed;
- singular or plural route names;
- supported CRUD operations;
- resource identifiers or their relationship to logical paths;
- create-time path templates;
- which frontmatter or body values are writable;
- how sections map to JSON fields;
- how repeated headings or rich Markdown are represented;
- pagination, filtering, sorting, or search behavior;
- rule enforcement policy;
- authentication or authorization; or
- tenant and shard boundaries.

Inferring these choices from a type name or path glob would create unstable APIs and security risks.

### Require explicit resource exposure

Server resources are opt-in. The versioned `MarkdownServerConfiguration` associates a stable resource name with explicit selection, route, read operations, identity, and projection behavior.

The following remains illustrative file syntax; issue #77 owns file-format decoding into the implemented `Codable` model:

```yaml
resources:
  books:
    type: Book
    route: /books
    operations: [list, get]
    id: recordIdentity
    representation: book-v1
    rules: [published-books]
```

The resource configuration should be separate from the mdtype contract. A type remains portable validation infrastructure even when no server exposes it, and the same type can support different server representations in different applications.

Resource selection must also be explicit. The native read-only design supports three distinct modes:

- **rule selection**, where rule applicability determines membership and type diagnostics are optional;
- **type selection**, where successful conformance to a named mdtype determines membership within an explicit search root; and
- **rule selection with an expected type**, where rule-selected candidates remain visible even when they do not conform, with validity and diagnostics represented in the response.

The third mode is useful for administrative and remediation APIs. It must not silently discard invalid candidates merely because an expected type was configured.

### Treat reads and writes differently

Read-only generation is feasible before a general-purpose encoder exists:

1. load or enumerate canonical records;
2. assess complete conformance to the exposed mdtype;
3. project conforming records into a declared response representation; and
4. return stable identity, revision, and structured diagnostics as configured.

Create and update endpoints require additional semantics:

- a reversible or explicitly one-way resource codec;
- create-time templates for required Markdown body structure;
- path allocation;
- identity and revision generation;
- replacement versus patch semantics;
- deterministic handling of unknown fields and advisory constraints; and
- optimistic concurrency behavior.

The first endpoint-generation prototype should therefore be read-only. Mutation should be a separate milestone after the resource codec and store contracts are accepted.

## RecordStore Contract

The implemented `RecordStore` is asynchronous, `Sendable`, and storage-neutral. It exposes semantic operations rather than backend-specific query syntax:

- fetch by stable record identity;
- deterministic bounded enumeration by logical search root, limit, and opaque continuation token;
- create only when identity is absent, with a store-assigned opaque revision;
- replace or delete only when an expected revision atomically matches; and
- stable not-found, conflict, invalid-record, invalid-query, and unavailable errors.

Logical paths narrow enumeration but are not universal storage keys. The collection root retains pathless records. Cancellation is checked before work, during enumeration, and immediately before commits, and is propagated without wrapping. Paging is deterministic while store contents remain unchanged; immutable cross-mutation snapshots belong to the read-snapshot layer.

`InMemoryRecordStore` is the first implementation because it enables portable repository and contract tests without deciding the production database. A `FileRecordStore` should follow to validate ordinary folder-backed operation. SQLite should be evaluated after repository semantics are stable.

The initial repository may enumerate candidates and assess types on demand. Persistent type indexes are an optimization and must never become the source of truth.

## Recommended First Vertical Slice

The next implementation milestone should prove endpoint derivation with the smallest useful read path:

1. Define one explicit exposed resource backed by a `Book` mdtype.
2. Define a minimal response projection for that resource.
3. Implement `InMemoryRecordStore` and the read-only portion of `TypedMarkdownRepository`.
4. Compile the resource into an immutable `EndpointPlan` containing `GET /books` and `GET /books/{id}`.
5. Register generic Hummingbird 2 handlers from that plan.
6. For type selection, return records that conform to `Book`; separately test rule selection with an expected type, where invalid candidates remain visible with `valid: false` and diagnostics.
7. Add in-process HTTP tests for success, not found, nonconforming stored data, overlapping type membership, route collisions, and revision exposure.

This slice intentionally excludes OpenAPI generation, create, update, delete, authentication, SQLite, persistent indexes, and Workers deployment. Its purpose is to validate the resource model, endpoint-planning boundary, and typed read repository before expensive infrastructure choices are made. OpenAPI 3.1 generation follows as a separate milestone using the accepted plan.

Success means the same repository fixture produces the same resource responses through direct library calls and Hummingbird without exposing Markdown storage details.

## Native Server Architecture

The conventional server will run as a native Swift application on Linux. It should call library APIs directly rather than spawning the `md-utils` CLI.

```text
rules + mdtype definitions + resource configuration
                         ↓
              immutable EndpointPlan
                    ↙          ↘
        Hummingbird 2 routes    OpenAPI 3.1
                    ↘          ↙
                 generic handlers
                         ↓
              TypedMarkdownRepository
              ↙          ↓           ↘
       ResourceCodec  Type/Rules   RecordStore
                                      ↓
                         FileRecordStore or SQLiteRecordStore
```

`MarkdownUtilitiesServer` owns plan construction and generic handlers. The `md-utils-server` executable performs startup composition and serves the registered plan through Hummingbird 2. No resource-specific Swift source is generated.

Storage must remain replaceable so a maintainer can use an ordinary folder hierarchy, SQLite, or a future adapter appropriate to the deployment.

## Cloudflare Workers Architecture

The likely Workers architecture uses a TypeScript shell for HTTP routing, authentication, OpenAPI transport, and Cloudflare bindings. `MarkdownUtilitiesCore` runs as a WebAssembly module for portable Markdown parsing, mutation, type assessment, and rule assessment.

```text
Generated OpenAPI contract
            ↓
Cloudflare Worker transport
            ↓
Resource handler / repository adapter
            ↓
Durable Object or other RecordStore adapter
            ↓
MarkdownUtilitiesCore.wasm
```

The WASI build and mdtype smoke assessment are implemented. A stable JavaScript/WebAssembly ABI, release artifact packaging, and Workers host integration are not.

Cloudflare Durable Objects remain promising because they provide a coordination boundary and SQLite-backed storage. A Durable Object could serialize mutations, store canonical Markdown, maintain derived JSON and type indexes, and answer indexed queries.

The architecture must avoid a single global Durable Object. Durable Objects should be partitioned around a natural coordination boundary such as a tenant, vault, workspace, or another explicitly designed shard.

The exact partitioning model remains open because it affects write throughput, cross-shard queries, migrations, and how an endpoint finds all records of a type. Workers work should begin after the portable repository semantics and native contract are proven.

## SQLite Direction

SQLite is promising but has not been selected as the universal or mandatory storage backend.

A potential schema could store:

- stable record ID;
- logical path;
- canonical Markdown text or bytes;
- extracted frontmatter as JSON;
- revision or content hash;
- derived type memberships;
- type definition and index format versions;
- validation state; and
- creation and update metadata.

Extracting frontmatter into a SQLite JSON column would enable native JSON queries and indexes without making the extracted JSON canonical. Canonical Markdown and its derived index rows could be updated atomically when they live in the same database transaction.

Because mdtype contracts are versioned, every cached conformance result must identify the type name, type contract version, and evaluator/index format version that produced it. A registry change must invalidate or rebuild affected memberships.

Import/export tooling could mitigate the loss of direct file browsing by converting between SQLite records and an ordinary `.md` folder hierarchy. Any such tooling must preserve Markdown content and logical paths without loss and define conflict behavior explicitly.

Before adopting SQLite, a prototype should test round-trip fidelity, index rebuilding, query performance, transaction behavior, schema migration, import conflicts, and realistic vault sizes.

## Deferred Decisions

The following questions remain intentionally unresolved:

- The standalone server configuration file syntax and location; the transport-neutral model is versioned independently at version `1`.
- Whether OpenAPI is generated as a complete document or composed with maintainer-authored operations.
- The public resource representation and section-to-field projection model.
- Whether the first general representation is domain-specific, generic JSON, or both.
- Create templates and reversible Markdown encoding semantics.
- Stable identity generation and its relationship to logical paths.
- Revision generation and HTTP precondition mapping, including ETags and conditional writes.
- List pagination, filtering, sorting, full-text search, and query limits.
- Which rules run at each read or write lifecycle point.
- The OpenAPI generation and routing toolchain for Workers.
- Whether SQLite, filesystem storage, or another backend is the default for the native server.
- The JavaScript/WebAssembly ABI and release packaging for Core.
- Whether canonical Markdown on Workers lives in Durable Object SQLite, R2, or another store.
- Durable Object sharding and cross-shard query design.
- SQLite table and JSON index schemas.
- Import/export conflict resolution and synchronization semantics.
- Authentication, authorization, tenancy, deployment configuration, rate limiting, and observability.

The mdtype v1 format, current Markdown predicates, logical path normalization, portable type assessment, portable rule assessment, and WASI dependency viability are no longer deferred decisions.

## Implementation Order

Completed prerequisites:

1. **Complete:** Establish the `MarkdownUtilitiesCore` Linux/native boundary.
2. **Complete:** Validate Core and representative mdtype behavior under WASI.
3. **Complete:** Design and implement mdtype v1.
4. **Complete:** Elevate reusable type and rule assessment into Core.
5. **Complete:** Define storage-neutral `MarkdownRecord`, context, revision, and logical path values.
6. **Complete:** Implement the storage-neutral `RecordStore` protocol and in-memory reference store.
7. **Complete:** Implement the immutable generic read snapshot and collision-safe resource indexes.

Recommended next work:

1. Build the `Book` read-only vertical slice with generic Hummingbird 2 handlers registered from the plan.
2. Add the public, read-only mdtype schema introspection required by the OpenAPI generator.
3. Generate OpenAPI 3.1 from the same plan and prove route/contract parity.
4. Specify resource codecs, create templates, revision preconditions, and rule enforcement for mutations.
5. Add create, update, and delete operations with reassessment before commit.
6. Implement `FileRecordStore` and prototype SQLite storage and derived indexes.
7. Ship the conventional native server distribution with contract, concurrency, and migration tests.
8. Define the JavaScript/WebAssembly ABI and prototype the Workers repository adapter.
9. Prototype Durable Object storage and sharding.
10. Run shared HTTP contract tests across native and Workers distributions.

## Non-Goals of This Document

This document does not select a final database, Durable Object topology, authentication system, or deployment provider. Resource-exposure configuration and the `RecordStore` API are implemented library contracts with their own testable acceptance criteria.

Swift OpenAPI Generator, generated server protocols, build plugins, and resource-specific generated Swift code are not part of the server design.

This document records the agreed direction and recommends the smallest next experiment that can invalidate or confirm the endpoint-derivation design before the project commits to production infrastructure.
