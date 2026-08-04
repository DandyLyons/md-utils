# Read Snapshots

Build immutable resource collections and collision-safe lookups from canonical Markdown records.

## Overview

`MarkdownServerReadSnapshotBuilder` is the transport-neutral read-side composition layer. It combines a `RecordStore`, an `EndpointPlan`, the compiled rules referenced by that plan, and a `MarkdownTypeRegistry`. The resulting `MarkdownServerReadSnapshot` contains no store handle and performs no parsing during lookup, so one value can be shared safely by concurrent HTTP handlers.

Snapshot construction follows one bounded startup pipeline:

1. Revalidate that every rule and type referenced by the plan is present.
2. Enumerate the record store in deterministic bounded pages.
3. Apply resource search roots, type path requirements, and rule `paths` and `excludePaths` before content parsing.
4. Parse each surviving record once and reuse its frontmatter, body, headings, and parse diagnostics.
5. Assess loaded Markdown types, resource rules, expected types, and configured identities from that shared analysis.
6. Build immutable resource collections, primary-identity indexes, and the global logical-path index.

The snapshot is intentionally rebuilt rather than updated in place. Hot reload and persistent derived indexes belong to later server layers.

```swift
let snapshot = try await MarkdownServerReadSnapshotBuilder(
  store: store,
  plan: plan,
  ruleRegistry: ruleRegistry,
  typeRegistry: registry
).build()

let books = snapshot.resource(named: "books")
let dune = books?.lookup(primary: MarkdownRecordIdentity(rawValue: "dune"))
```

## Selection and Validity

The three endpoint-plan selection modes retain distinct semantics:

- Type selection includes only records that conform to the selected type beneath its configured search root.
- Rule selection includes every applicable record. Its membership is valid only when the rule's required checks pass.
- Rule selection with an expected type also includes every applicable record, even when the expected type fails. Its membership is valid only when both the rule and type pass.

Recommendations remain diagnostics but do not invalidate conformance or rule checks. Type conformance is non-exclusive, so one parsed record can conform to several types and participate in several resources without being parsed again.

## Generic Record Representation

`GenericMarkdownRecord` is a JSON-ready projection of canonical read state. It preserves the store identity and revision, logical path, safely parsed user frontmatter, Markdown body, resource memberships, validity, and structured diagnostics. Reserved `$md-utils` metadata is not included in user frontmatter.

Membership metadata is many-to-many. Each `GenericMarkdownResourceMembership` contains the resource-derived identity and identity status, the selecting rule when present, the selected or expected type, all assessed type memberships, and resource-local validity. The envelope's `valid` property is true only when all represented memberships are valid; callers serving one resource should inspect the membership with that resource name.

Malformed YAML does not make the canonical record disappear. When frontmatter delimiters can be separated safely, the body remains available, frontmatter is omitted, and a parsing diagnostic explains the failure. Parser-originated problems appear once in the unified diagnostic list rather than being repeated through every rule and type assessment.

## Identity and Lookup

Canonical identity and resource identity are separate. The envelope reports collection-wide status for the store-supplied canonical identity, while each membership reports status under that resource's configured `MarkdownRecordIdentityPolicy`. Missing, invalid, and duplicate resource identities therefore do not change type or rule validity.

`MarkdownResourceReadSnapshot.lookup(primary:)` and `MarkdownServerReadSnapshot.lookup(logicalPath:)` return `MarkdownServerReadLookupResult`. Callers must switch exhaustively over `record`, `notFound`, and `conflict`. A conflict retains every candidate and never chooses the first matching record.

Repeated occurrences of an identical canonical value during paging are removed. Distinct records sharing an identity or logical path remain visible so their collision can be diagnosed. One canonical record selected by several resources is represented once with several memberships and is not treated as a collision.

## Failure Boundaries

Compile rules before creating the endpoint plan or snapshot. Missing capabilities, invalid JMESPath syntax, and unresolved schema resources are `MarkdownRuleCompilationError` startup failures. Definition drift and repeated continuation tokens produce `MarkdownServerReadSnapshotBuildError` before a snapshot is published. Store failures remain `RecordStoreError`, and cancellation remains `CancellationError`. Invalid YAML, failed rule checks, nonconforming expected types, and identity problems are record diagnostics rather than snapshot-build failures.
