# Building and distributing md-utils

Use Swift 6.3 or later for native source builds, with a matching compiler and
SDK. Linux CI pins `swift:6.3.1-noble`; WASI requires exactly Swift 6.3.1 and its
matching WebAssembly SDK. Let SwiftPM manage `Package.resolved`; do not edit it
by hand.

## Platform and distribution matrix

| Platform | Build and validation | Distribution |
| --- | --- | --- |
| macOS | Primary development platform; full native test suite. Manifest minimum is macOS 13; native SQLite CI uses macOS 26. Every older OS/compiler combination is not tested. | Source/SwiftPM and Mint. No automated binary archive, universal binary, signing, or notarization pipeline. |
| Ubuntu 24.04 x86_64 | Swift 6.3.1 container CI builds the native server and runs server/template and SQLite/index checks. | Source builds; no prebuilt x86_64 release archive. |
| Ubuntu 24.04 aarch64 | Native ARM64 CI builds the release CLI, runs native server/template/index checks, installs the archive without Swift, and rebuilds its source offline. | CLI prerelease binary/source archives. Initial tag `0.3.0-linux.1` is planned; publication requires a tag push. Separate server packaging is pending [#159](https://github.com/DandyLyons/md-utils/issues/159). |
| WASI, `wasm32-unknown-wasip1` | Core builds and its smoke module executes under WasmKit with the Swift 6.3.1 WASI SDK. | Build output only; no packaged release, stable JavaScript ABI, browser integration, or Workers deployment. |
| Other Apple SDKs | Manifest declares iOS 16, tvOS 16, watchOS 9, and Mac Catalyst 16 minimums. These do not establish support for every product or dependency. | No native CLI/server distribution or CI validation for these SDKs. |
| Other Linux distributions, Alpine/musl, Windows, Android | No verified distribution baseline. | No supported binary artifact. |

Core has no native filesystem, SQLite, or SwiftKnap dependency. Native products
have additional requirements below. File watching uses macOS FSEvents; on Linux
use explicit `md-utils index update` refreshes. See the
[portability audit](portability-audit.md) for library boundaries.

## Native source builds

From a checkout on macOS, select the intended Swift toolchain and run:

```sh
swift --version
swift build --product md-utils
swift build --product md-utils-server
swift test
swift run md-utils --help
swift run md-utils-server --help
```

For optimized executables:

```sh
swift build -c release --product md-utils
swift build -c release --product md-utils-server
swift build -c release --show-bin-path
```

Run products from the reported directory, or preserve their SwiftPM resource
bundles alongside them when installing elsewhere. macOS uses `.bundle/`
directories and Linux uses `.resources/` directories. Copying only the executable
loses schemas, skill text, or template resources. Do not share `.build/` between
branches/worktrees. Source builds report the checked-in
`Sources/md-utils/Resources/BuildVersion.txt` value; tagging alone does not change it.

Ubuntu native CLI/server source builds additionally need `libsqlite3-dev`,
`libjavascriptcoregtk-4.1-dev`, and `pkg-config`. Release packaging also uses
Python 3, Git, and binutils. Project Linux builds and validation run **in CI
only**; use the workflows below instead of local Docker builds.

For installation without a Swift toolchain, use the
[Ubuntu ARM64 archive instructions](linux-arm64-distribution.md). That archive
links Swift's runtime statically but uses Ubuntu's shared SQLite,
JavaScriptCore, Curl, and XML libraries. Ordinary `swift build -c release` does
not apply the archive's static Swift linking or packaging steps.

## CI coverage and Docker recipes

Workflows use path filters on pull requests; consult the linked YAML for exact
triggers. All four verification workflows support manual dispatch. Dispatching
the ARM64 workflow verifies and uploads CI artifacts but does not publish a release.

| Workflow | Actual verification |
| --- | --- |
| [Native SQLite](../.github/workflows/sqlite-index.yml) | macOS smoke/tests/measurements; x86_64 Linux builds [Dockerfile.sqlite-index](../Dockerfile.sqlite-index). |
| [Native Server Linux](../.github/workflows/server-linux.yml) | Runs Swift build, focused tests, and route smoke directly inside a Swift Noble container. |
| [Linux ARM64 CLI distribution](../.github/workflows/release-linux-arm64.yml) | Builds [Dockerfile.release-linux](../Dockerfile.release-linux), tests the checksummed archive in [Dockerfile.release-runtime](../Dockerfile.release-runtime), then checks offline source rebuilding and editable JXKit in [Dockerfile.release-source](../Dockerfile.release-source). |
| [WebAssembly Core](../.github/workflows/webassembly.yml) | Installs the matching WASI SDK, then runs [scripts/build-wasm.sh](../scripts/build-wasm.sh). |

[Dockerfile.core-linux](../Dockerfile.core-linux) is an isolated Core build/smoke
recipe; no current workflow invokes it directly. Likewise,
[Dockerfile.server-linux](../Dockerfile.server-linux) is a native server/CLI
build-and-install recipe, not the command used by the Native Server Linux job.
Its final image still contains Swift. Only the ARM64 release-runtime recipe
checks installation in plain Ubuntu without a Swift toolchain or checkout.

For WASI prerequisites, compatibility patches, and output paths, follow
[WebAssembly support](webassembly.md). Native CLI/server, indexing, and template
rendering are outside that WASI target.

## Publishing

Follow [release procedures](release-procedures.md) for tags, artifact verification,
source/notices retention, and publication. CLI versions, project config versions,
server config versions, and index cache formats evolve independently. A Linux
prerelease does not change any schema default.
