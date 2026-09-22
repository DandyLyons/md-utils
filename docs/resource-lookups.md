# Named resource lookups and scoped identity constraints

Server configuration version 2 adds named read lookups. Version 1 configurations
and default item routes continue to work. This feature does not enable mutation
routes, generate UUIDs, repair collisions, or assign slugs; those belong to #82/#154.

Create an empty v2 configuration with `md-utils-server init --schema-version 2`, or
export its schema with `md-utils-server schema --schema-version 2`. Initialization
preserves existing configuration files; when migrating, change serverConfigVersion
explicitly and refresh the matching local schema. Configuration changes require
server restart. Type/rule definition formats are unchanged.

```yaml
serverConfigVersion: "2"
persistentIdentity:
  path: [uuid]
resources:
  - name: books
    route: /books
    operations: [list, get]
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
      - name: slug
        source: frontmatter
        path: [slug]
        format: slug
        slugPolicy: unicode
      - name: filename
        source: filename
      - name: path
        source: logicalPath
    constraints:
      - lookup: slug
        uniqueWithin: resource
        requireValue: false
```

Book must already be a loaded mdtype. Named lookup names contain lowercase ASCII
letters, digits, and hyphens. Each resource supports up to 64 lookups/constraints.
Duplicate names, undeclared constraint references, invalid extractors, and route
overlaps fail startup. Slug formats require explicit slugPolicy (strictASCII,
unicode, or preserve). Frontmatter format also supports string, integer, and uuid.
Only frontmatter extractors accept path/format/slugPolicy. Named lookup and constraint
objects reject unknown fields rather than silently ignoring misspelled restrictions.

## Routes

Resources with get enabled expose both segment and query forms for scalar lookups:

```http
GET /books/9780441172719
GET /books/by/slug/dune
GET /books/by/filename/Reading%20Notes.md
GET /books/by/filename?value=Reading%20Notes.md
GET /books/by/path?value=books%2FReading%20Notes.md
```

Logical-path lookups use query form only. All query forms require exactly one
nonempty value parameter. Use the query form for identifiers containing slash or
other URL-sensitive text; percent-encode values. Values are bounded to 4096 UTF-8
bytes, with the existing 32768-byte URI limit. Filenames retain spaces, Unicode,
case, and extensions. UUID query spelling is canonicalized as for UUID extraction.
Other values remain exact; no slugification or implicit case folding occurs.

Each route enforces resource membership. Unknown lookup values return 404;
ambiguous values return 409 record.lookup-conflict. Invalid requests return 400.
Conflict candidates remain bounded to 1000 records and the response byte budget.
The existing global logical-path fallback remains separate and unchanged.
Runtime routes and generated read OpenAPI derive from the same EndpointPlan.

## Scope and optional identity

Lookup alone requires neither uniqueness nor presence. A declared constraint can
specify uniqueWithin: resource or server, independently of requireValue. Server
scope includes the full configured authoritative Markdown collection, not merely
public resource memberships. Repeated memberships of one file count once.

The optional persistentIdentity declares one shared frontmatter UUID path. UUIDs
are not required in existing files. Present UUIDs are always assessed for server-wide
uniqueness, even if a resource does not expose a named UUID route. A conflicting
unexposed file makes UUID lookup ambiguous but is not included in public candidate
representations or diagnostic paths. Only a count reveals additional holders.

The index is derived from authoritative files. External changes are reconciled by
the existing watcher or explicit refresh; the index cannot prevent external edits.
Collision diagnostics are independent of mdtype conformance. Constraint violations
appear in record diagnostics and shared lookup evidence; they do not silently remove
selected invalid records. Missing optional values are ordinary absence.

## Mutation integration boundary

Planned resources expose protectedIdentityFields and lookupEvidence supplies
resolved values, identity status, uniqueness scope, presence requirements, protection,
and diagnostics. Default identity fields, persistent UUIDs, and frontmatter lookups
with protectedIdentifier: true contribute identity protections. Other lookups do not.
Nested identity paths protect their entire top-level metadata field for #90 codecs.

Evidence is revision/configuration-derived assessment, not permission to commit.
#82 must reacquire authoritative source, preserve complete configured contracts,
resolve document-wide protections, and recheck collection invariants under writer
coordination. No authored FileEditPolicy YAML is added.

## Native publication and portability

Aliases are disk-staged with the existing projection generation and published
consistently. Changed counts are queried against the published generation, including
when only an unexposed holder changes. Cached alias rows contain no bodies. Both
metadata-only and optional FTS modes materialize bounded authoritative source only
for returned documents. The portable snapshot reference implementation provides
equivalent semantics; it is not the native corpus cache.

After refresh, UUID aliases resolve the new path of a moved document. Native storage
handles remain logical paths; this does not introduce a persistent path-move history.
Copied UUIDs conflict, and no file is silently chosen or rewritten. #152 tracks
provenance for later repair. Independent pending drafts remain untouched.

Verification: `swift test --filter 'NamedLookupTests|IndexedMarkdownRepositoryTests'`.
