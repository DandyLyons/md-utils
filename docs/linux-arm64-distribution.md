# Linux ARM64 CLI archives

The Linux CLI distribution targets **Ubuntu 24.04 (Noble), glibc, aarch64**.
The initial planned version is a prerelease, `0.3.0-linux.1`; its tagged publication
is still pending. The CLI release version is
independent of config/schema versions; this preview does not declare the broader
0.3 release or issue #135 complete. Development CI artifacts add `-dev.<commit>`.

The workflow publishes these assets for prerelease tags:

- `md-utils-<version>-linux-aarch64-ubuntu24.04.tar.gz` and `.tar.gz.sha256`
- `md-utils-<version>-source.tar.gz` and `.tar.gz.sha256`

Download from the matching [GitHub release](https://github.com/DandyLyons/md-utils/releases).
Only tagged, verified builds are published. PR/manual builds are CI artifacts.
Other distributions, older glibc, Alpine/musl, and other architectures are outside
this artifact's supported baseline. A separate server artifact is tracked by
[#159](https://github.com/DandyLyons/md-utils/issues/159). See
[platform coverage](building-and-platforms.md) for other build paths and
[release procedures](release-procedures.md) for publishing this preview.

## Downstream Docker installation

After the prerelease is published, this pinned example installs the archive into
a plain Ubuntu ARM64 image. Build on ARM64 or explicitly select `linux/arm64`.

```dockerfile
FROM ubuntu:24.04
ARG MD_UTILS_VERSION=0.3.0-linux.1
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl libsqlite3-0 libjavascriptcoregtk-4.1-0 libcurl4t64 libxml2 \
    && rm -rf /var/lib/apt/lists/*
RUN set -eu; \
    test "$(dpkg --print-architecture)" = arm64; \
    asset="md-utils-${MD_UTILS_VERSION}-linux-aarch64-ubuntu24.04.tar.gz"; \
    base="https://github.com/DandyLyons/md-utils/releases/download/${MD_UTILS_VERSION}"; \
    mkdir -p /opt/md-utils/ /opt/download/; \
    cd /opt/download/; \
    curl --fail --location --remote-name "${base}/${asset}"; \
    curl --fail --location --remote-name "${base}/${asset}.sha256"; \
    sha256sum -c "${asset}.sha256"; \
    tar -xzf "$asset" --strip-components=1 -C /opt/md-utils/; \
    printf '#!/bin/sh\nexec /opt/md-utils/md-utils "$@"\n' > /usr/local/bin/md-utils; \
    chmod 755 /usr/local/bin/md-utils; \
    rm -rf /opt/download/
WORKDIR /work/
RUN md-utils --version && printf '# Hello\n' | md-utils body
CMD ["md-utils", "--help"]
```

The archive has one top-level versioned directory. Preserve its executable and
four SwiftPM resource directories together under `/opt/md-utils/`; the launcher
keeps resource lookup independent of the caller's working directory. `build.json`
records source/toolchain/dependency versions and resource names. `linkage.txt`
records build-time shared-library inspection. `licenses/`, `SOURCE.md`, and
`INSTALL.md` accompany the executable.

Swift 6.3.1 standard/runtime libraries are statically linked. SQLite and
JavaScriptCore remain distribution-provided shared libraries; apt supplies their
transitive dependencies. Curl/XML runtime packages support Foundation consumers.
No Swift compiler is needed for installation. This is not a fully static binary.
OS package updates supply fixes for the shared runtime libraries.

## Source and dependency notices

JXKit is linked into the executable and retains LGPL-3.0. System JavaScriptCore
linkage does not replace JXKit's separate distribution requirements. The companion
source archive includes the application, exact dependency and recursive submodule Git bundles, notices,
and `rebuild-source.py`. Its README documents rebuilding and editing/relinking
JXKit. Publish and retain the matching source archive alongside every binary.
SwiftKnap's Knap/Day.js resources and their notices are included. No new license
is assigned to md-utils by this packaging work.

## CI verification

Linux builds run in CI only. The `Linux ARM64 CLI distribution` workflow uses a
native `ubuntu-24.04-arm` runner and `swift:6.3.1-noble` builder. It builds release
mode with the checked-in lockfile, verifies ELF architecture/linkage, preserves
existing Linux tests, and exports archives. `Dockerfile.release-runtime` installs
the actual checksummed binary archive in `ubuntu:24.04`, with no checkout or
Swift toolchain, and runs `scripts/release/smoke-linux.sh` from `/work/`.

Smoke coverage includes exact version/help, Markdown body extraction, bundled
skill/schema resources, SwiftKnap output, SQLite update/query and FTS5. Missing
resource negative checks establish that lookup cannot fall back to a build tree.
`Dockerfile.release-source` verifies checksums and rebuilds from the source archive
with network disabled, including SwiftPM's editable JXKit path.

CI commands (also recorded in the workflow):

```sh
python3 scripts/release/test-source-bundles.py
docker build -f Dockerfile.release-linux --target artifacts \
  --build-arg RELEASE_VERSION=0.3.0-linux.1 \
  --build-arg SOURCE_COMMIT="$GITHUB_SHA" --output type=local,dest=tmp/artifacts/ .
cp scripts/release/smoke-linux.sh tmp/artifacts/
docker build -f Dockerfile.release-runtime --build-arg RELEASE_VERSION=0.3.0-linux.1 tmp/artifacts/
docker build -f Dockerfile.release-source --build-arg RELEASE_VERSION=0.3.0-linux.1 tmp/artifacts/
```
