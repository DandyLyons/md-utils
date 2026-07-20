# MarkdownUtilities Server Architecture

**Status:** Core/native target boundary implemented; server implementation has not started
**Last updated:** 2026-07-18

This document records the architectural direction for exposing Markdown-backed data through conventional HTTP APIs. It distinguishes decisions already made from promising ideas that still require validation.

## Objective

Build an HTTP server framework in which maintainers define ordinary application endpoints and Markdown remains a persistence implementation detail.

API clients should interact with domain resources such as books, documents, or projects. They should not need to know that the server persists those resources as Markdown containing YAML frontmatter and structured body content.

For example, an API might expose `/books/{id}` while internally storing the resource as canonical Markdown. The API resource and its storage representation are deliberately separate concepts.

## Decisions

### Ship Native and Cloudflare Distributions

The project should eventually ship two server solutions sharing the same semantics and portable core:

1. A conventional native Swift server for Linux and other supported server environments.
2. A Cloudflare Workers distribution that uses WebAssembly where necessary.

These are two runtime distributions of the same architecture, not necessarily identical HTTP implementations.

### Use OpenAPI as the HTTP Contract

Server maintainers will define their public API with an OpenAPI document. The OpenAPI contract describes conventional domain-oriented endpoints and representations; it does not expose Markdown-specific operations.

The native Swift server should investigate [Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator) for generated server protocols and transport integration.

The Workers distribution should use the same OpenAPI contract. It may use TypeScript-oriented generation for routing and transport if the Swift-generated OpenAPI runtime is not WebAssembly-compatible. Contract tests should ensure that both distributions implement the same API behavior.

### Use a Portable Core Library

The package should evolve toward three library/application layers:

```text
MarkdownUtilitiesCore
├── Portable Markdown models and parsing
├── Frontmatter conversion
├── Markdown type assessment
├── Rule assessment
└── Structured diagnostics

MarkdownUtilities
├── MarkdownUtilitiesCore
├── Filesystem integration
├── Configuration loading
├── Extended attributes
└── Other platform-specific functionality

md-utils
├── MarkdownUtilities
├── ArgumentParser commands
├── CLI presentation
└── Process exit behavior
```

`MarkdownUtilitiesCore` runs on Linux and compiles to WebAssembly. It avoids direct filesystem access, process execution, CLI dependencies, and platform-specific APIs. Linux support is verified with `Dockerfile.core-linux`; WASI compilation and representative runtime behavior are verified with `scripts/build-wasm.sh`.

`MarkdownUtilities` will contain functionality that is appropriate for native platforms but unavailable or unsuitable in WebAssembly. `md-utils` remains the executable CLI and is not expected to run inside WebAssembly.

Swift can run natively on Linux, so the conventional server does not require WebAssembly. WebAssembly is specifically a portability mechanism for runtimes such as Cloudflare Workers.

The current split and dependency assessment are recorded in [the portability audit](portability-audit.md). The supported SDK, dependency compatibility patches, and WASI smoke workflow are documented in [WebAssembly Support](webassembly.md).

### Make Types and Rules Library Concepts

A native Markdown type system is a prerequisite for the server. It should be implemented before `MarkdownUtilitiesServer`.

Types and rules are distinct:

- A **Markdown type** answers whether a record structurally conforms to a named type such as `Book`.
- A **rule** selects records and applies validation or policy checks to them.

The existing rules implementation currently lives primarily in the `md-utils` executable target. Reusable rule models, matching, checking, and structured results should move into a library target. CLI argument parsing, filesystem command orchestration, formatting, and exit codes should remain in `md-utils`.

Type definitions will live under `.md-utils/types/`. The initial design work is tracked by [Issue #74](https://github.com/DandyLyons/md-utils/issues/74).

### Define Whole-Markdown Types

Markdown types are not merely JSON Schemas. A type may define constraints over:

- YAML frontmatter using JSON Schema;
- headings and their hierarchy;
- required sections;
- suggested sections or headings;
- other Markdown body or AST concepts added in the future;
- the logical path and folder hierarchy associated with a record.

Required constraints affect type conformance. Suggested constraints produce advisory diagnostics without causing conformance to fail.

Type conformance is structural and non-exclusive. One record may simultaneously conform to `Book`, `Document`, and `Publishable`. A query for all `Book` records returns every record conforming to `Book` regardless of its other type memberships.

Structural types may include nominal-like requirements. For example, a `Book` type may use JSON Schema to require a `tags` array containing the literal value `books`. This is still structural conformance because the declaration is part of the required data shape.

Rule applicability must not be confused with type conformance. A rule's path or metadata matcher can select a candidate without that candidate passing the rule's checks. Type queries must be based on successful type assessment.

### Treat Markdown Records as Canonical Data

Canonical Markdown content does not have to exist as an ordinary filesystem file. It may be stored as an exact Markdown string or byte sequence inside another persistence system, including SQLite.

The persistence abstraction should therefore operate on records rather than assuming direct filesystem paths:

```text
MarkdownRecord
├── stable identity
├── logical path
├── canonical Markdown content
└── revision or content hash

RecordStore
├── FileRecordStore
├── SQLiteRecordStore
└── future object-store adapters
```

The logical path preserves hierarchical organization even when the record is stored in a SQLite row or object store rather than a directory on disk.

Parsed JSON, search indexes, and cached type memberships are derived data. They must be rebuildable from canonical Markdown records.

### Keep Markdown Encoding Behind the Persistence Boundary

The earlier `MarkdownRecordCodec` idea should become schema- and type-aware rather than merely converting between strings and generic values.

Conceptually, the persistence layer must support operations such as:

```text
decode canonical Markdown as an expected Markdown type
assess all Markdown types to which a record conforms
validate a proposed create or update before committing it
encode an updated domain representation back to canonical Markdown
return structured errors and advisory diagnostics
```

The precise public API will be designed with the Markdown type system.

## Native Server Architecture

The conventional server will run as a native Swift application on Linux. It should call library APIs directly rather than spawning the `md-utils` CLI.

```text
OpenAPI document
      ↓
Generated Swift server protocol
      ↓
Application handlers
      ↓
Typed Markdown repository
      ↓
MarkdownUtilities / MarkdownUtilitiesCore
      ↓
FileRecordStore or SQLiteRecordStore
```

The HTTP framework and Swift OpenAPI transport have not yet been selected. Storage should remain replaceable so a maintainer can use an ordinary folder hierarchy, SQLite, or a future adapter appropriate to their deployment.

## Cloudflare Workers Architecture

The likely Workers architecture uses a TypeScript shell for HTTP routing, authentication, OpenAPI transport, and Cloudflare bindings. `MarkdownUtilitiesCore` runs as a WebAssembly module for portable Markdown parsing, mutation, type assessment, and rule assessment.

```text
OpenAPI request
      ↓
Cloudflare Worker transport
      ↓
Application handler
      ↓
Durable Object or other record-store adapter
      ↓
MarkdownUtilitiesCore.wasm
```

Cloudflare Durable Objects appear promising because they provide a coordination boundary and SQLite-backed storage. A Durable Object could serialize mutations, store canonical Markdown, maintain derived JSON and type indexes, and answer indexed queries.

The architecture must avoid a single global Durable Object. Durable Objects should be partitioned around a natural coordination boundary such as a tenant, vault, workspace, or another explicitly designed shard.

The exact partitioning model remains open because it affects write throughput, cross-shard queries, migrations, and how an endpoint finds all records of a type.

## SQLite Direction

SQLite is promising but has not been selected as the universal or mandatory storage backend.

A potential schema could store:

- stable record ID;
- logical path;
- canonical Markdown text or bytes;
- extracted frontmatter as JSON;
- revision or content hash;
- derived type memberships;
- validation and index format versions;
- creation and update metadata.

Extracting frontmatter into a SQLite JSON column would enable native JSON queries and indexes without making the extracted JSON canonical. Canonical Markdown and its derived index rows could be updated atomically when they live in the same database transaction.

Import/export tooling could mitigate the loss of direct file browsing by converting between SQLite records and an ordinary `.md` folder hierarchy. Any such tooling must preserve Markdown content and logical paths without loss and define conflict behavior explicitly.

Before adopting SQLite, a prototype should test round-trip fidelity, index rebuilding, query performance, transaction behavior, schema migration, import conflicts, and realistic vault sizes.

## Deferred Decisions

The following questions remain intentionally unresolved:

- The exact Markdown type-definition format under `.md-utils/types/`.
- The complete set of Markdown-native type constraints.
- The representation and normalization of logical paths.
- The HTTP framework for the native Swift server.
- The OpenAPI generation and routing toolchain for Workers.
- Which current Swift package dependencies can compile to WebAssembly.
- Whether SQLite, filesystem storage, or another backend is the default for the native server.
- Whether canonical Markdown on Workers lives in Durable Object SQLite, R2, or another store.
- Durable Object sharding and cross-shard query design.
- SQLite table and JSON index schemas.
- Import/export conflict resolution and synchronization semantics.
- Authentication, authorization, tenancy, deployment configuration, and observability.

## Implementation Order

1. Maintain the established `MarkdownUtilitiesCore` Linux boundary and validate its WebAssembly dependencies.
2. Design and implement the Markdown type system.
3. Elevate reusable rules functionality into the library.
4. Define a storage-neutral `MarkdownRecord` and `RecordStore` abstraction.
5. Prototype SQLite storage, extracted JSON querying, and lossless import/export.
6. Define an OpenAPI example application and generate the native Swift contract.
7. Implement the conventional native server distribution.
8. Prototype the Workers, WebAssembly, and Durable Objects integration.
9. Add shared contract tests across both server distributions.

## Non-Goals of This Document

This document does not select a final database, HTTP framework, Durable Object topology, authentication system, or deployment provider. It records the agreed direction and preserves the remaining uncertainty for explicit future decisions.
