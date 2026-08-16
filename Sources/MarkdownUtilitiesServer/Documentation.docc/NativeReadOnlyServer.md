# Native Read-Only Server

Compose a project snapshot once and expose it through generic Hummingbird 2 routes.

## Startup

`md-utils-server` reads `.md-utils/server.yaml` by default. `--project-root` changes
the root used for records, rules, mdtypes, and schemas; `--config` selects another
YAML file; `--hostname` and `--port` override `127.0.0.1:8080`.

``MarkdownServerProjectLoader`` loads `.md-utils/md-utils.json` when present,
recursively imports `.md` and `.markdown` files outside `.md-utils/` into
``InMemoryRecordStore``, compiles one ``EndpointPlan``, and builds one
``MarkdownServerReadSnapshot``. Any decoding, reference, route, or snapshot failure
stops startup before Hummingbird accepts requests.

The snapshot is immutable. Restart the process to observe filesystem changes.
Hummingbird's `runService()` performs graceful lifecycle shutdown for `SIGINT` and
`SIGTERM`.

## Routing and Responses

``MarkdownServerHTTPAdapter`` registers each route in the plan without generated or
resource-specific Swift code:

- Collection routes return `[GenericMarkdownRecord]`.
- Item routes return one record by the resource's primary identity.
- `/_md-utils/path/**` returns one record by exact nested logical path when fallback
  is enabled.

Not-found results map to `404`. Invalid logical paths map to `400`. Identity and
logical-path collisions map to `409` with every candidate in a stable
``MarkdownServerHTTPErrorEnvelope``. A handler never chooses an arbitrary colliding
record.

Rule-selected invalid candidates remain in successful collection and item responses
with `valid: false` and diagnostics. Missing primary identities remain visible in a
collection but cannot be addressed through the item route. Overlapping resource
membership retains one canonical identity and revision across every representation.

## Performance Boundary

Recursive discovery, Markdown parsing, rule checks, type assessment, and index
construction occur once during startup. Requests read immutable precomputed arrays
and lookup indexes. The first release returns unpaginated collections and stores the
startup import in memory, so it targets bounded project trees rather than an
unbounded or live-updating repository.
