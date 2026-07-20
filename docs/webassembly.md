# WebAssembly Support

`MarkdownUtilitiesCore` supports WebAssembly through the official Swift WASI SDK. The supported baseline is:

- Swift toolchain: Swift 6.3.1
- Swift SDK: `swift-6.3.1-RELEASE_wasm`
- target: `wasm32-unknown-wasip1`

The WebAssembly target remains computation-focused. It parses and renders supplied Markdown content, mutates document structures, and performs type and rule assessment without owning filesystem, network, or host runtime behavior.

## Install the SDK

The Swift toolchain and WebAssembly SDK versions must match exactly. Install the official Swift 6.3.1 SDK with:

```bash
swift sdk install \
  https://download.swift.org/swift-6.3.1-release/wasm-sdk/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE_wasm.artifactbundle.tar.gz \
  --checksum bd47baa20771f366d8beed7970afaa30742b2210097afd15f85427226d8f4cf2
```

Confirm that SwiftPM can discover it:

```bash
swift sdk list
```

## Build and Run

Run the repeatable build and runtime verification:

```bash
scripts/build-wasm.sh
```

The script:

1. verifies that the matching WebAssembly SDK is installed;
2. resolves the versions in `Package.resolved`;
3. applies version-checked WASI compatibility patches to the Yams and JSONSchema SwiftPM checkouts;
4. compiles `MarkdownUtilitiesCore` for WASI; and
5. builds and runs `MarkdownUtilitiesCoreWasmSmoke.wasm` with Swift's bundled WasmKit runtime.

To use an SDK extracted outside SwiftPM's default SDK directory, provide its parent directory with a trailing slash:

```bash
SWIFT_WASM_SDKS_PATH=/path/to/swift-sdks/ scripts/build-wasm.sh
```

Debug artifacts are written beneath `.build/wasm32-unknown-wasip1/debug/`. The smoke artifact is currently about 69 MB in an unoptimized debug build; this is not a release-size target.

## Compatibility Patches

The current resolved dependencies need two narrow source-level adaptations:

- Yams 6.2.0 uses `DBL_DECIMAL_DIG`, which is not imported into Swift by the WASI Foundation module. The WASI branch uses 17 significant decimal digits, the round-trip requirement for an IEEE 754 binary64 value.
- JSONSchema.swift 0.6.0 passes `NSNumber` directly to `CFNumberIsFloatType` outside Linux. WASI uses the package's existing Linux-compatible integer check instead.

The patches live in `scripts/wasm-patches/`. The build script verifies the exact dependency revisions before applying them and fails rather than patching an unknown version. Both changes are conditional on `os(WASI)` and do not alter native behavior.

CoreFoundation also requires the WASI signal and memory-mapping emulation definitions while compiling. The smoke target links the corresponding `wasi-emulated-signal` and `wasi-emulated-mman` libraries only on WASI.

## Smoke Coverage

`IntegrationTests/WasmCoreSmoke/` verifies representative behavior across the dependency boundary:

- YAML frontmatter parsing and floating-point serialization through Yams and libYAML;
- Markdown AST parsing of headings, task lists, and tables through MarkdownSyntax and swift-cmark;
- Markdown rendering; and
- draft 2020-12 JSON Schema and Markdown type assessment.

The root package owns the smoke target, so it uses the same `Package.resolved` versions as the library. A separate path-dependent integration package would resolve its own transitive dependency versions.

## Current Scope

This workflow produces and executes a WASI module. It does not yet define a stable JavaScript ABI, optimize or package a release artifact, or integrate with a specific JavaScript or Workers host. Those layers should build on the verified Core module without introducing host I/O into `MarkdownUtilitiesCore`.
