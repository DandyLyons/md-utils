# Native Read-Only Server

Compile an immutable resource plan and expose bounded indexed reads through generic Hummingbird 2 routes.

## Startup

`md-utils-server` reads `.md-utils/server/server.yaml` by default. `--project-root` changes
the root used for records, rules, mdtypes, and schemas; `--config` selects another
YAML file; `--hostname` and `--port` override `127.0.0.1:8080`.

Run `md-utils-server init` from a project root to create a minimal configuration and
install `.md-utils/server/server.schema.json` for editor validation. Initialization
preserves an existing `server.yaml`. `md-utils-server schema` prints the canonical
bundled JSON Schema. `md-utils-server serve` starts the server explicitly;
`md-utils-server` remains an alias for that default subcommand.

The YAML requires `serverConfigVersion: "1"` and a `resources` array. Each resource
requires a unique `name`, safe absolute `route`, at least one `list` or `get`
operation, an explicit rule- or type-based `selection`, and an `identityPolicy`.
The optional projection defaults to `genericRecord`, operation-ID overrides default
to an empty array, and logical-path fallback defaults to enabled.

``MarkdownServerProjectLoader`` loads `.md-utils/md-utils.json` when present,
recursively imports `.md` and `.markdown` files outside `.md-utils/` into
``InMemoryRecordStore``, compiles one ``EndpointPlan``, and builds one
``MarkdownServerReadSnapshot``. Any decoding, reference, route, or snapshot failure
stops startup before Hummingbird accepts requests.

The native executable instead composes `IndexedMarkdownRepository` from the separate
`MarkdownUtilitiesServerNative` target. It shares the CLI cache, publishes body-free
projections, and watches source files on macOS. Other platforms adopt explicit CLI
index updates. Resource configuration and definition changes require restart.
Hummingbird's `runService()` performs graceful lifecycle shutdown for `SIGINT` and
`SIGTERM`.

## Routing and Responses

``MarkdownServerHTTPAdapter`` registers each route in the plan without generated or
resource-specific Swift code:

- Collection routes return `{records, generation, nextCursor}` with bounded pagination.
- Item routes return one record by the resource's primary identity.
- `/_md-utils/path/**` returns one record by exact nested logical path when fallback
  is enabled.
- `/openapi.json` returns the active deterministic OpenAPI 3.1.1 document.

Not-found results map to `404`. Invalid logical paths map to `400`. Identity and
logical-path collisions map to `409` with bounded candidates and explicit totals in a stable
``MarkdownServerHTTPErrorEnvelope``. A handler never chooses an arbitrary colliding
record.

Rule-selected invalid candidates remain in successful collection and item responses
with `valid: false` and diagnostics. Missing primary identities remain visible in a
collection but cannot be addressed through the item route. Overlapping resource
membership retains one canonical identity and revision across every representation.

Use `md-utils-server openapi --format json|yaml --output <file>` to export the same
contract without importing records or starting Hummingbird. See <doc:GeneratedOpenAPI>.

## Performance Boundary

The executable uses disk-backed projection staging and generation-consistent read
transactions. Source bodies are read only for requested records, checked against
indexed content hashes, and never cached across the corpus in a snapshot. Pages
are limited to 1,000 records and 64 MiB; single source reads are limited to 64 MiB.
Changed sources return `503 record.source-changed`. Failed operational refreshes
retain the last publication and expose `X-Md-Utils-Stale`.

Collection parameters are `limit`, `cursor`, `pathPrefix`, `valid`, and scalar JSON
`filter`. Resources with `searchEnabled: true` additionally offer `q` and require an
FTS-enabled cache. All parameters and errors are generated from the endpoint plan.
