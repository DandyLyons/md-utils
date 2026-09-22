# REST mutations and lookup design (#82)

Status: design discussion consolidated on 2026-09-21; updated 2026-09-22. This document records
approved behavior and separates remaining proposals. It does not describe shipped
HTTP mutations or mark issue acceptance criteria complete.

Implementation update: #153's named read lookups and scoped constraint assessment
use server configuration v2; see [the current read contract](resource-lookups.md).
Broader mutation examples below remain design material for #82. Current read syntax
takes precedence over earlier illustrative snippets.

Tracking: [#82](https://github.com/DandyLyons/md-utils/issues/82), within
[#93](https://github.com/DandyLyons/md-utils/issues/93). Existing contracts:
[resource mutation planning](resource-mutations.md),
[indexed server reads](indexed-server-reads.md), and
[collection indexing](collection-index.md).

## Existing foundations

Phase 1 issues #92, #81, #91, #89, #77, #97, and #107 establish the
storage-neutral RecordStore, configurable identity extraction, immutable
EndpointPlan, resource membership and read representations, generic HTTP routing,
shared rule evaluation, and versioned server configuration.

EndpointPlan remains the common source for runtime routes and OpenAPI. Resource
selection, identity policy, and read projection are already configured separately.
The native store currently uses logical paths for canonical identity; persistent
UUID lookup across moves requires new integration, not merely a route alias.

#90 supplies writable codecs, template-based creation planning, preservation-aware
replace/patch, and full configured rule/type reassessment. Its default update policy
preserves previously passing loaded contracts; endpoint-only override remains
explicit. These semantics are retained. DELETE removes the canonical document
across resources, rather than merely removing one membership.

## Approved lookup behavior

- Preserve identityPolicy as the default lookup for the existing item route.
- Add explicitly configured named lookups: UUID, slug, filename, or another
  frontmatter field. Each resource defines its lookup policies.
- Use explicit lookup routes, such as `/books/by/slug/dune`, rather than guessing
  which lookup a string denotes. Exact route grammar remains to be finalized.
- Every lookup respects destination resource membership.
- Resolve every alias to the same canonical record before validation and revision
  checking. A document may be exposed through both books and stories resources.
- Ambiguous lookup returns a conflict, never an arbitrary candidate.

Lookup availability and uniqueness constraints are separate. Declaring a lookup
does not require uniqueness by default. Required uniqueness and its scope are
explicitly configured in the server configuration. Reusable mdrule uniqueness
declarations are deferred; collection uniqueness is not per-record conformance.

Persistent UUIDs must be unique server-wide. One document exposed through multiple
resources counts once. Slugs may repeat across resources. If two documents with the
same slug later belong to one resource requiring unique slugs, a server mutation
introducing that violation is rejected. External changes surface diagnostics and
ambiguous lookup conflicts. Reassessment covers every affected resource.

The existing `md-utils fm unique` command already checks scalar uniqueness,
supports reference-versus-collection checks, and optionally requires values.
Reuse compatible semantics through shared library support; SQLite can accelerate
assessment but cannot replace authoritative-source checks or write coordination.

## Optional UUIDs

### Approved distinction between lookup and protected identity

Default resource identity fields and persistent UUIDs are protected across every
resource selecting the document. Additional lookup fields can be explicitly
designated as protected identifiers. Merely declaring lookup by title or slug does
not protect that field from ordinary edits. Its configured uniqueness and validation
constraints still apply. FileEditPolicy derives these distinctions internally.

UUIDs are not required for every served Markdown document. Existing documents
remain readable through configured identifiers and logical-path fallback without
being rewritten on read.

For a resource opted into server-wide persistent UUIDs, creation automatically
generates and fills the configured UUID frontmatter field. Clients do not have to
request generation separately. Existing documents are not retroactively assigned
UUIDs merely by reading them. The working
proposal stores UUIDs in a configured protected frontmatter field so they survive
index rebuilds and moves. The exact field configuration and migration interface
remain to be finalized. UUID-only storage in the rebuildable index is not the
proposed persistence model.

Persistent UUIDs are immutable through ordinary identity edits. Duplicate-UUID
repair must be a separate, explicit action; its interface remains open.

## Creation and expressive filenames

Creation-enabled resources explicitly configure a destination directory, optional
UUID generation, and how domain identifiers are supplied. Administrator-owned
templates remain the creation mechanism from #90.

Filenames preserve expressive text. Do not slugify, lowercase, strip punctuation,
or replace spaces automatically. Slugs serve normalized lookup needs separately.
Deriving an initial filename from a configured title or slug field is a working
proposal; exact source selection, extension handling, and filename validation
syntax remain open.

For example, a title `The Left Hand of Darkness` can produce
`books/The Left Hand of Darkness.md` while a separately supplied slug is
`the-left-hand-of-darkness`. Title, heading, slug, and filename do not implicitly
synchronize. PUT/PATCH preserve the file path; rename/move is a separate operation.
Slug generation is separately configured as described below.

### Approved slug behavior

- Offer optional generation of a missing frontmatter slug on creation from a
  configured title or filename; share the generator between library, CLI, and server.
- Preserve supplied slugs, subject to format validation. Do not regenerate a stored
  slug automatically when the title or filename changes.
- Generation implies no uniqueness guarantee. Enforce only configured uniqueness
  scopes; ambiguous lookup returns a conflict.
- Where uniqueness is required, reject collisions by default or use an explicitly
  configured suffix allocator with coordinated final checks.
- Lookup alone does not protect a slug. Default identity or explicit protected
  identifier designation requires identity editing.
- Never apply slug normalization to filenames.

Existing HeadingTextExtractor.generateSlug and identity slug-format validation are
foundations, not an already implemented frontmatter generator. Preserve heading
anchor compatibility when extracting shared functionality. Server generation must
match the configured slug format and reject empty/unrepresentable results rather
than silently use the heading-specific fallback `section`.

Reject filename collisions by default, with an optional configured suffix strategy.
Never overwrite an existing file. A suffix resolves only a path collision, not a
required ISBN, slug, or UUID uniqueness violation.

An identical basename in two directories is allowed. Filename lookup conflicts
when multiple selected documents share it. A complete destination-path collision
must reject a managed rename. External tools can overwrite files independently;
the server cannot prevent that. Rename/move changes path and filename lookups and
requires membership reassessment. Stable UUID resolution across moves is intended
new behavior, not a guarantee of the current path-based native store.

## Creation-only identifiers and explicit identity edits

The approved example allows a client to supply ISBN at creation while protecting
it from ordinary PUT/PATCH. The following envelope is illustrative, not an accepted
wire schema:

```json
{
  "identifiers": {"isbn": "9780441172719"},
  "frontmatter": {"title": "Dune"},
  "data": {"description": "A novel set on Arrakis."}
}
```

The host maps the declared identifier into protected frontmatter, validates it,
and checks configured uniqueness before persistence. It does not invent missing
domain values. The ISBN may supply the default item lookup.

Include an explicit identity-edit workflow in this feature design. The proposed
workflow is independently enabled per resource, requires the current revision,
accepts only configured identity fields, validates the complete proposal, checks
all affected uniqueness constraints, and publishes updated mappings. It preserves
filename/title unless separately edited. Old identifier lookup ceases to resolve;
historical aliases are not currently proposed.

Proposed request shape, still subject to review:

```http
POST /books/by/uuid/<uuid>/identity
MD-Utils-If-Revision: <current-revision>
Content-Type: application/json

{"set": {"isbn": "9780441172719"}}
```

UUID is not required to initiate an identity edit. Define an unambiguous,
resource-scoped exact-path addressing mechanism for missing/colliding identifiers;
the existing global path lookup alone does not specify the destination write policy.
Route syntax and repair scope remain open. Ordinary identity editing cannot change
the persistent UUID.

## Approved revision and concurrency contract

Updates, identity edits, and deletes require the revision read by the client.
Revisions identify current content; they do not imply document history, backups,
or undo. Native revisions are source-byte SHA-256 hashes. Clients treat revision
tokens as opaque. Identical restored content has the same native revision.

If the client's revision no longer matches, reject the write without modifying
the file. Representation ETags and publication generations remain distinct from
canonical revisions. Exact header encoding and status mapping remain to be finalized.

- Server and participating CLI mutations coordinate through a shared mutation
  service and check authoritative content immediately before persistence.
- External edits detected before commit cause the mutation to fail.
- Each file is persisted atomically, so readers do not see a partially written file.
- An unrelated editor can race the final check and replacement. Strict conflict
  prevention is promised only within the participating-writer coordination boundary.

This boundary must be reconciled explicitly with RecordStore's atomic revision
comparison contract when implementing the filesystem adapter. Hash-then-rename
alone is not atomic compare-and-swap against arbitrary external writers.

## Approved publication, retries, and recovery

After authoritative persistence, refresh and publish derived index/server state.
If persistence succeeds but publication fails, report a distinct committed,
recovery-pending outcome. Never claim source rollback or return an ordinary
validation failure implying nothing changed.

Creation requires an idempotency key so retries after ambiguous outcomes do not
create a second document. Persist enough operation information to recover pending
publication after restart. Recovery records track completion, not document history.

Retain #82/#141 requirements: bounded source materialization, metadata-only and
optional FTS support, consistent identity/membership/diagnostic publication,
generation-bound cursor invalidation, prevention of older staged refresh overwrites,
and preservation of independent pending drafts. No filesystem/SQLite transaction
is implied. Multi-file operations require explicit partial-completion semantics.

## Concrete configuration proposal for review

Everything in this section is proposed syntax, not loadable configuration for the
current server. Existing selection, identityPolicy, and codec shapes are retained.
The schema-version change, if any, has not been chosen, so the fragment deliberately
omits serverConfigVersion.

Use one optional server-level persistent UUID declaration. Resources explicitly
opt into its use; creation then automatically generates the UUID. This avoids
two resources assigning different persistent UUID fields to the same document.
Approved scope: every authoritative Markdown document within the configured server
collection, including documents not exposed through a resource. Missing UUIDs are
allowed; present malformed or duplicate values produce diagnostics. This scope
requires complete discovery, not merely scanning publicly selected memberships.

```yaml
persistentIdentity:
  source: frontmatter
  path: [uuid]

resources:
  - name: books
    route: /books
    operations: [list, get, create, replace, patch, delete, editIdentity]
    selection:
      mode: type
      type: Book
      searchRoot: books/
    identityPolicy:
      source: frontmatter
      path: [isbn]
      format: string
    lookups:
      - name: uuid
        source: persistentIdentity
      - name: isbn
        source: frontmatter
        path: [isbn]
        format: string
      - name: slug
        source: frontmatter
        path: [slug]
        format: slug
      - name: filename
        source: filename
      - name: path
        source: logicalPath
    constraints:
      - lookup: isbn
        uniqueWithin: resource
        requireValue: true
      - lookup: slug
        uniqueWithin: resource
        requireValue: false
    writable:
      codec:
        frontmatterFields: [title, description]
        bodyWritable: true
        protectedFields: [isbn, slug, uuid]
      identityEdits:
        fields: [isbn, slug]
      creation:
        directory: books/
        filename:
          source: frontmatter
          path: [title]
          extension: .md
          collision: reject
        identifiers:
          - name: isbn
            path: [isbn]
            required: true
          - name: slug
            path: [slug]
            required: false
        template: |
          # Book

          {{ data.description }}

  - name: stories
    route: /stories
    operations: [list, get]
    selection:
      mode: type
      type: Story
      searchRoot: .
    identityPolicy:
      source: frontmatter
      path: [slug]
      format: slug
    lookups:
      - name: uuid
        source: persistentIdentity
      - name: slug
        source: frontmatter
        path: [slug]
        format: slug
```

Book and Story are assumed to be loaded definitions, not types inferred or created
by this configuration. Creation must pass the actual Book definition; the template
is only illustrative. Existing inputSchema support still applies but is omitted
from this example for readability.

The books resource requires ISBNs and makes present slugs unique within books.
Stories can have ambiguous slugs because it declares no uniqueness constraint.
Both resources refer to the same optional UUID field. In this proposed syntax,
declaring a persistentIdentity lookup opts the resource into its use, so creation
automatically fills that field without a second generation flag. Omitting persistentIdentity
disables this persistent UUID facility; other identifiers remain available.

Proposed validation rules:

- A constraint references a declared lookup; it does not itself expose a route.
  `uniqueWithin` accepts `resource` or `server`; absence means no extra constraint.
  `requireValue` is independent of uniqueness and defaults to false.
- A server-scoped constraint evaluates the same extractor across the complete
  collection. It does not mean only the union of exposed resource memberships.
- A persistent UUID lookup cannot weaken server-wide uniqueness or require UUIDs
  implicitly for existing documents. Opting into its use requires persistentIdentity configuration.
- Identifier inputs and identity-edit fields must be explicitly mapped to protected
  metadata. The example restricts edits to literal top-level keys, consistent with
  #90; nested identity editing needs a separate decision.
- Prevent alternate writable resources from bypassing identifier protection using
  the document-level effective edit policy described below. Globally rejecting
  every pair of different resource declarations is superseded by this approach.
- Declared lookup names and routes must pass EndpointPlan collision validation.
  An absent optional lookup value does not prevent other lookups from working.

For filenames, propose treating the selected string as the exact stem and appending
the configured extension once as an explicit operation: a title ending in `.md`
would consequently produce `.md.md`, without hidden stripping. Reject invalid
single-component names with actionable diagnostics; never silently sanitize them.
Filesystem-equivalent names must conflict on the actual target filesystem. An
optional `collision: suffix` would append ` (2)`, ` (3)`, etc. before the extension.
These extension and suffix conventions still need review.

## Concrete request proposal for review

Create with an explicit slug, which is preserved. Optional configured generation
would fill an omitted slug instead:

```http
POST /books
Content-Type: application/json
Idempotency-Key: create-dune-001

{
  "identifiers": {"isbn": "9780441172719", "slug": "dune"},
  "frontmatter": {"title": "Dune"},
  "data": {"description": "A novel set on Arrakis."}
}
```

The proposed result is `books/Dune.md`, with a generated protected UUID and the
supplied ISBN/slug. Ordinary success is 201 after publication, with Location and
the committed canonical revision. Lookup examples:

```http
GET /books/9780441172719
GET /books/by/isbn/9780441172719
GET /books/by/slug/dune
GET /books/by/uuid/<uuid>
GET /books/by/filename/Dune.md
GET /books/by/path?path=books%2FDune.md
```

The proposed exact-path route uses a query parameter to keep slash-containing
paths out of a single route segment. It remains resource-scoped, exact, and subject
to membership. The global read fallback remains available under its existing
configuration. Values are URL-encoded; filenames are not modified to fit URLs.
Scalar identifiers unsuitable for a single segment need an explicit transport
decision rather than silent coercion or normalization.

Apply PUT/PATCH/DELETE to the same item addresses when independently enabled.
For example, a title patch leaves `books/Dune.md` and its slug unchanged:

```http
PATCH /books/by/slug/dune
Content-Type: application/json
MD-Utils-If-Revision: <revision-from-read>

{"frontmatter": {"set": {"title": "Dune: Revised Edition"}}}
```

Correct an ISBN through a stable UUID, using the proposed identity-edit envelope:

```http
POST /books/by/uuid/<uuid>/identity
Content-Type: application/json
MD-Utils-If-Revision: <revision-from-read>

{"set": {"isbn": "9780441172719"}}
```

For a document with a colliding/missing ISBN and no UUID, propose:

```http
POST /books/by/path/identity?path=books%2FDune.md
Content-Type: application/json
MD-Utils-If-Revision: <revision-from-exact-path-read>

{"set": {"isbn": "9780441172719"}}
```

The correction succeeds only if destination validation and all affected constraints
pass. Ordinary identity edits can optionally use explicit `remove` for optional
identifiers; required identifiers cannot be removed successfully. UUID repair is
excluded. Identifier changes must not rerender the creation template.

For recovery, retain the proposed distinct `mutation.publication-pending` response
with `committed: true`, operation identifier, committed path/revision (or deleted
identity), and recovery guidance. The recovery section specifies the working status,
operation-status route, and configurable retention default. Reusing a creation key with a different request must return
a conflict; replaying the same key must resume/report the original operation rather
than allocate another path or UUID. This includes replay through restart.

## Repair, edit policy, and recovery review (2026-09-22)

### Approved direction

- Enforce configured server-wide UUID uniqueness throughout the collection,
  including unexposed documents.
- Make a best-effort determination of the duplicate. Automatically repair when
  evidence is unambiguous; otherwise request user selection. UUID repair remains
  distinct from ordinary identity editing, even when repair is automatic.
- A document has an effective edit policy determined by all mdtypes/mdrules it
  conforms to. Choosing another resource must not bypass it.
- Make idempotency retention configurable with a reasonable default.
- Automatically assign the configured UUID when creating through a resource that
  opts into server-wide UUIDs. No separate generation switch is needed.

### Proposed evidence and repair scenarios

1. A managed copy operation explicitly records its source and destination. The
   source retains its UUID; repair assigns a new UUID to the known copy after
   revision checks and validation. Record the change and its evidence visibly.
2. Refresh discovers a second file with an existing UUID. Prior observation of one
   file helps identify a candidate, but discovery order, mtime, and content equality
   alone are not sufficient proof: moves, restoration, incomplete scans, and swaps
   can produce the same observations. Auto-repair requires a documented evidence
   rule proving an unambiguous copy relationship; otherwise offer a suggested
   target for user selection.
3. A fresh/rebuilt index discovers two holders together. Keep the conflict and
   return candidate choices. A headless server reports repair-required state;
   interactive tooling asks the user rather than blocking an HTTP request on a UI.
4. A candidate changes after analysis. Recheck revisions for affected holders and
   collection uniqueness under writer coordination; abort and reassess rather than
   applying a stale repair. Never rewrite UUID references elsewhere automatically.

Provenance is partial evidence, not canonical identity ownership. A separate GitHub
issue [#152](https://github.com/DandyLyons/md-utils/issues/152) tracks
observation/copy/move evidence and its retention across rebuilds.

### Derived document edit policy (clarified 2026-09-22)

FileEditPolicy is an internal Swift implementation model derived from authoritative
assessment of existing mdtypes/mdrules, resource codecs, identity invariants, and
revision state. It introduces no authored YAML policy interface or new policy
declaration in type/rule schemas. The previous declaration proposal is withdrawn.

The model explains allowed, forbidden, and proposal-dependent edits. A required
title can be changed to another valid title; it is not inferred to be immutable.
Reuse #90's complete-proposal validation and baseline conformance preservation,
including its explicit endpointOnly override. That override does not bypass
protected identifier handling. Previously failing checks remain subject to the
existing remediation semantics rather than becoming invented extra restrictions.

See the dedicated implementation design for derived evidence, resource-specific
capabilities, cross-resource identity protection, and revision-bound invalidation.

### Approved recovery outcomes and proposed retention defaults

The user approved the recovery outcome scenarios on 2026-09-22: original-result
replay after a lost response, committed/pending publication responses, restart
reconciliation, recovery-required on uncertain external changes, and conflicts for
key reuse with a different request. The seven-day default and exact wire names
below remain proposals; configurability is approved.

- Default completed-operation idempotency retention: 7 days, configurable.
  Never expire unresolved operations merely because this interval elapsed.
- Scope a creation key to the server collection, resource, and operation. Bind it
  to the validated request's semantic payload; same key with different input is
  a 409 conflict. Capture allocated path/UUID before persistence for safe recovery.
- Lost response after success: replay returns the original operation receipt and
  committed revision without repeating creation. Make clear that this is the
  original result, not necessarily the document's current state.
- Source committed but publication failed: return 503 with a structured
  `mutation.publication-pending`, `committed: true`, and operation-status link.
  Retry with the same key resumes/reports that operation, never creates another.
- Restart with pending work: reconcile durable intent, committed source evidence,
  and publication state. If external edits make the commit outcome indeterminate,
  preserve evidence and report recovery-required rather than rewriting source or
  asserting rollback. Refresh current authoritative content when safe.
- Proposed status route: `GET /_md-utils/operations/{operationId}`. Show pending,
  completed, or recovery-required state plus committed revision and diagnostics.
- After completed-key expiry, deduplication is no longer guaranteed. Expose expiry
  in receipts and document that clients must inspect state before retrying an old
  create. Retention cleanup must preserve pending recovery and independent drafts.

Exact wire/configuration names and evidence rules remain proposals for review.

## Engineering specification and delivery

The internal derivation/assessment proposal is detailed in
[document edit policies](document-edit-policies-design.md). It supplements this
design without adding a new mdtype/mdrule configuration interface.

Major product decisions are settled. Remaining configuration spelling, header
encoding, schema compatibility, persistence algorithms, and test details are
engineering specification tasks within those decisions, not another approval round.
The concrete examples above remain draft syntax until implemented and validated.
Use the [implementation sequence](rest-mutation-implementation-plan.md) for delivery.
Only a newly discovered behavior tradeoff requires returning to the user.

Proposed verification covers aliases, overlaps, optional/missing/duplicate UUIDs,
expressive filenames and collisions, identity correction, invalid proposals, stale
revisions, coordinated concurrent writers, external edits, atomic failures, restart
recovery, idempotent POST retries, post-commit publication failures, and both native
index storage modes. Existing codec-preservation and conformance tests remain part
of the contract.
