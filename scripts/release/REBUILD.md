# Corresponding source and rebuilding

This archive accompanies the binary with the same version. `md-utils/` contains
the application source and stamped version; `dependencies/` contains Git bundles
with the exact dependency commits and tags, including unmodified JXKit. Bundles
include source, not executable build products. `dependencies.json` records their
original URLs and revisions. `licenses/` contains distribution notices.

Use Ubuntu 24.04 ARM64 with Swift 6.3.1 and install `git`, `python3`, `pkg-config`,
`libsqlite3-dev`, and `libjavascriptcoregtk-4.1-dev`. From this extracted directory:

```sh
python3 rebuild-source.py
```

The script restores local Git mirrors, resolves the supplied lockfile, and builds
`md-utils/.build/release/md-utils`. Dependency sources come from the archive.
The Swift toolchain and OS development packages are separate prerequisites.

To modify and relink JXKit:

```sh
python3 rebuild-source.py --prepare-only
cd md-utils/
swift package edit JXKit
# Edit the JXKit sources in Packages/JXKit/.
swift build -c release --product md-utils --static-swift-stdlib
```

Install the rebuilt executable and the four resource directories listed in
`build.json` together, as described in `md-utils/docs/linux-arm64-distribution.md`.
There is no signature or installation restriction on replacing this executable.
JXKit retains LGPL-3.0. Both LGPL-3.0 and GPL-3.0 license texts and upstream
notices accompany the binary and source archives. This packaging change does
not assign a new license to the application.
