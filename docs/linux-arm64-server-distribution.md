# Linux ARM64 server archives

`md-utils-server` archives target **Ubuntu 24.04 (Noble), glibc, aarch64**.
They install independently of the CLI and need no Swift toolchain. Alpine/musl,
older glibc, and other architectures are not supported by these archives.
Swift 6.3.1 runtime libraries are statically linked; Ubuntu supplies shared
SQLite, JavaScriptCore, Curl, and XML libraries and their transitive dependencies.

Verified prerelease tag builds publish:

- `md-utils-server-<version>-linux-aarch64-ubuntu24.04.tar.gz` and its `.sha256`
- `md-utils-<version>-source.tar.gz` and its `.sha256`, shared with the CLI

The server archive includes its executable, four SwiftPM resource directories
(server version, server schemas, SwiftKnap, JXKit), `build.json`, `linkage.txt`,
installation/rebuilding instructions, and dependency notices. Keep the executable
and resource directories together. The CLI executable and CLI resource bundle
are not included. The source archive contains exact dependency and recursive
submodule Git bundles, including JXKit sources and offline relinking instructions.
See [rebuilding](../scripts/release/REBUILD.md). Artifact versions are independent
of server configuration and schema versions.

## Pinned Docker installation

The example pins the proposed **`0.3.0-linux-prerelease.3`** candidate. It is not
a claim that this tag has been published: use it only after the matching server
assets are available on the [release page](https://github.com/DandyLyons/md-utils/releases),
or replace it with a later verified server artifact version. Existing CLI-only
releases cannot supply a server archive.

```dockerfile
FROM ubuntu:24.04
ARG MD_UTILS_VERSION=0.3.0-linux-prerelease.3
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl libsqlite3-0 libjavascriptcoregtk-4.1-0 libcurl4t64 libxml2 \
    && rm -rf /var/lib/apt/lists/*
RUN set -eu; \
    test "$(dpkg --print-architecture)" = arm64; \
    asset="md-utils-server-${MD_UTILS_VERSION}-linux-aarch64-ubuntu24.04.tar.gz"; \
    base="https://github.com/DandyLyons/md-utils/releases/download/${MD_UTILS_VERSION}"; \
    mkdir -p /opt/md-utils-server/ /opt/download/; \
    cd /opt/download/; \
    curl --fail --location --remote-name "${base}/${asset}"; \
    curl --fail --location --remote-name "${base}/${asset}.sha256"; \
    sha256sum -c "${asset}.sha256"; \
    tar -xzf "$asset" --strip-components=1 -C /opt/md-utils-server/; \
    rm -rf /opt/download/
WORKDIR /collection/
EXPOSE 8080
STOPSIGNAL SIGTERM
ENTRYPOINT ["/opt/md-utils-server/md-utils-server"]
CMD ["serve", "--project-root", "/collection/", "--config", ".md-utils/server/server.yaml", "--hostname", "0.0.0.0", "--port", "8080"]
```

The direct entrypoint makes the server PID 1 and delivers Docker's SIGTERM to
Hummingbird. Build this image on ARM64, or use explicitly configured ARM64
emulation. CI uses native ARM64 execution.

## Collection, configuration, and persistent state

Prepare a host collection with `books/` and `.md-utils/server/` directories.
Save this as `.md-utils/md-utils.json`:

```json
{"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[
  {"name":"books","match":{"paths":["books/**"]},"checks":[{"type":"requiredHeading","heading":"Book"}]}
]}
```

Save this as `.md-utils/server/server.yaml`:

```yaml
serverConfigVersion: "3"
resources:
  - name: books
    route: /books
    operations: [list, get]
    selection: {mode: rule, rule: books}
    identityPolicy: {source: frontmatter, path: [slug], format: string}
    writable:
      codec: {frontmatterFields: [title], bodyWritable: true}
      creation: {template: "{{ 'Book' | h1 }}\n{{ data.text | bold }}"}
    mutations:
      operations: [create]
      creation:
        directory: books/
        filenameField: title
        identifiers: [slug]
```

For read-only HTTP operation, omit `writable` and `mutations`. Even then,
`.md-utils/` must be writable for index refresh and publication. For writes,
`books/` must also be writable. Persist the entire collection, including
`.md-utils/`: it holds configuration, SQLite and its WAL/SHM files, locks,
durable mutation receipts/recovery state, and any pending drafts. SQLite is a
rebuildable cache; durable receipts and drafts are separate state and must not
be discarded with it. Do not mount only the SQLite file.

The following mounts the collection and a separate read-only server config
directory. The host UID/GID must be able to write the mounted collection/state.

```sh
docker build --platform linux/arm64 -t my-md-utils-server .
docker run --detach --name books-server --user "$(id -u):$(id -g)" \
  --publish 127.0.0.1:8080:8080 \
  --mount "type=bind,src=$(pwd)/collection/,dst=/collection/" \
  --mount "type=bind,src=$(pwd)/server-config/,dst=/collection/.md-utils/server/,readonly" \
  my-md-utils-server
# server-config/ contains the server.yaml shown above.
curl --fail http://127.0.0.1:8080/books
curl --fail http://127.0.0.1:8080/openapi.json
curl --fail http://127.0.0.1:8080/books \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: first-book' \
  --data '{"frontmatter":{"title":"Example"},"identifiers":{"slug":"example"},"data":{"text":"Created through Knap"}}'
docker stop --time 15 books-server
docker start books-server
```

Use a successful configured collection GET as the readiness check; startup
refreshes the index before listening. `--hostname 0.0.0.0` allows container port
forwarding; the executable otherwise defaults to `127.0.0.1`. Override the CMD
to change `--port`, `--config`, or `--project-root`. See
[REST mutations](rest-mutations.md) for revision and recovery contracts.

Linux has **no filesystem watcher**. Server-managed writes publish their changes.
After external file edits, restart this standalone server to perform startup
refresh, or explicitly refresh using a separately installed compatible CLI's
`md-utils index update`. Requests do not discover external edits. Configuration
and rule/type changes require restart. No CLI is needed for normal server
startup, reads, or mutations. See [indexed reads](indexed-server-reads.md).

## Verification and publication

The [ARM64 workflow](../.github/workflows/release-linux-arm64.yml) builds both
products in release mode, checks ELF architecture/shared linkage, retains the
existing Linux server/template/index/config tests and route smoke checks, and
exports separate archives. `Dockerfile.release-server-runtime` installs only
the checksummed server archive into plain Ubuntu with documented runtime packages.
The host's Python standard-library harness requires no test tools in that image.

`scripts/release/smoke-server.py` starts the installed server against a bind-mounted
collection and explicit config. It verifies version/schema resources, readiness,
collection/item reads and revision headers, generated OpenAPI, SQLite-backed
filtering and persisted rows, opted-in Knap creation, idempotent replay, and clean
SIGTERM exit. A missing-schema-bundle negative check rejects build-tree fallback.
The image has no source checkout, CLI, or Swift toolchain. Offline source CI also
rebuilds the server with editable JXKit and runs the same HTTP/template smoke.

Linux builds and execution run **in CI only**. PR/manual runs upload verification
artifacts; publication requires a fresh prerelease tag push after verification.
See [release procedures](release-procedures.md). Do not close distribution
acceptance criteria for tagged publication until the assets actually exist.
