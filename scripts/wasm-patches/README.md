# WASI Dependency Patches

`MarkdownUtilitiesCore` depends on Yams and JSONSchema.swift. The versions pinned
in `Package.resolved` work on Apple platforms and Linux, but each contains a small
source-compatibility gap when compiled for `wasm32-unknown-wasip1`. These patches
are temporary integration shims that let the Core library build for WASI without
maintaining forks of either dependency.

The patches modify only SwiftPM's generated dependency checkouts under
`.build/checkouts/`. They do not modify this package's sources or the dependency
repositories recorded in `Package.resolved`.

## Patches

### Yams 6.2.0

`yams-6.2.0-wasi.patch` changes Yams's floating-point formatting on WASI. Yams
normally passes the C constant `DBL_DECIMAL_DIG` to `String(format:)`, but that
constant is unavailable through the WASI SDK's libc headers. The patch uses `17`
significant decimal digits on WASI, which is the IEEE 754 round-trip requirement
for a binary64 value, while leaving every other platform on Yams's existing path.

This is tracked upstream by
[Yams PR #470: Add WASI platform support for DBL_DECIMAL_DIG](https://github.com/jpsim/Yams/pull/470).
The upstream pull request was still open when this workaround was documented on
July 20, 2026.

### JSONSchema.swift 0.6.0

`jsonschema-0.6.0-wasi.patch` extends JSONSchema.swift's existing Linux-specific
`NSNumber` integer check to WASI. The non-Linux implementation calls
`CFNumberIsFloatType`, which is unavailable in the WASI CoreFoundation overlay.
The Linux fallback determines integer-valued numbers through equality after an
integer conversion and excludes `CFBoolean` values; that implementation also
works on WASI.

No issue or pull request in the
[JSONSchema.swift issue tracker](https://github.com/kylef/JSONSchema.swift/issues?q=is%3Aissue%20WASI)
currently tracks WASI or WebAssembly support. The fallback being extended was
introduced by the upstream
[Linux compatibility commit](https://github.com/kylef/JSONSchema.swift/commit/ff07437b6388f1e121f358c1ff0a1478d078dd1e).

## How the Patches Are Applied

Run the repository's WebAssembly build entry point:

```bash
scripts/build-wasm.sh
```

The script resolves the package graph and then processes each dependency as
follows:

1. It verifies that the checkout's `HEAD` exactly matches the revision recorded
   alongside the patch in `scripts/build-wasm.sh`.
2. It makes the affected generated source file writable.
3. It runs `git apply --reverse --check` to detect an already-applied patch. If
   that succeeds, no further change is made.
4. Otherwise, it runs `git apply --check` before applying the patch. A context
   mismatch stops the build instead of partially modifying the checkout.
5. It builds `MarkdownUtilitiesCore` and runs the WebAssembly smoke executable.

The revision check and reverse check make the process both fail-safe and
idempotent: an unexpected dependency update is never patched, and repeated WASM
builds do not apply the same diff twice.

The script also supplies `_WASI_EMULATED_SIGNAL` and `_WASI_EMULATED_MMAN` as C
compiler definitions. Those settings enable wasi-libc compatibility libraries;
they are build flags rather than source patches and therefore do not appear in
this directory.

## Updating or Removing a Patch

When either dependency changes, the revision guard intentionally fails. Before
updating the recorded revision:

1. Check whether the new release includes the upstream WASI fix.
2. Build and run the WASM smoke executable without the local patch when the fix
   is present.
3. If the build passes, remove the patch file and its
   `apply_dependency_patch` call.
4. If a workaround is still required, regenerate the diff against the new exact
   revision, review its scope, update the revision guard, and rerun the native,
   Linux, and WASM validation workflows.

These patches should remain minimal and platform-conditional so native behavior
continues to be owned by the upstream implementations.
