#!/usr/bin/env bash

# Stop on the first failed command, unset variable, or failed pipeline so a
# partially prepared dependency checkout is never treated as a successful build.
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}../" && pwd)/"
readonly SWIFT_WASM_SDK="${SWIFT_WASM_SDK:-swift-6.3.1-RELEASE_wasm}"
# Patch only the dependency revisions whose source context has been reviewed.
# A package update must be evaluated before these guards are changed.
readonly YAMS_REVISION="51b5127c7fb6ffac106ad6d199aaa33c5024895f"
readonly JSONSCHEMA_REVISION="d14de4b2d9205068c9db89c00d097ca43c897000"

# CI uses the default SDK store, while local verification can point Swift at an
# isolated SDK installation through SWIFT_WASM_SDKS_PATH.
swift_sdk_arguments=(--swift-sdk "${SWIFT_WASM_SDK}")
swift_sdk_list_arguments=()
if [[ -n "${SWIFT_WASM_SDKS_PATH:-}" ]]; then
  swift_sdk_arguments=(
    --swift-sdks-path "${SWIFT_WASM_SDKS_PATH}"
    "${swift_sdk_arguments[@]}"
  )
  swift_sdk_list_arguments=(--swift-sdks-path "${SWIFT_WASM_SDKS_PATH}")
fi

apply_dependency_patch() {
  local checkout_directory="$1"
  local expected_revision="$2"
  local patch_file="$3"
  local patched_source="$4"

  local actual_revision
  actual_revision="$(git -C "${checkout_directory}" rev-parse HEAD)"
  if [[ "${actual_revision}" != "${expected_revision}" ]]; then
    echo "error: refusing to patch ${checkout_directory}/ at unexpected revision ${actual_revision}" >&2
    return 1
  fi

  # SwiftPM can make checkout sources read-only. Only the file named by the
  # reviewed patch is made writable.
  chmod u+w "${checkout_directory}${patched_source}"

  # A successful reverse check means this exact patch is already present. This
  # keeps repeated and incremental WASM builds idempotent.
  if git -C "${checkout_directory}" apply --reverse --check "${patch_file}" 2>/dev/null; then
    return 0
  fi

  # Validate the entire diff before modifying the checkout. Context drift or a
  # partial prior edit fails here rather than leaving a half-applied patch.
  git -C "${checkout_directory}" apply --check "${patch_file}"
  git -C "${checkout_directory}" apply "${patch_file}"
}

cd "${REPOSITORY_ROOT}"

# Fail with an actionable message before dependency resolution or compilation.
if ! swift sdk list "${swift_sdk_list_arguments[@]}" | grep --fixed-strings --line-regexp "${SWIFT_WASM_SDK}" >/dev/null; then
  echo "error: Swift WebAssembly SDK '${SWIFT_WASM_SDK}' is not installed" >&2
  exit 1
fi

swift package resolve

# Yams references a libc decimal-precision constant that WASI does not expose.
apply_dependency_patch \
  ".build/checkouts/Yams/" \
  "${YAMS_REVISION}" \
  "${SCRIPT_DIRECTORY}wasm-patches/yams-6.2.0-wasi.patch" \
  "Sources/Yams/Representer.swift"
# JSONSchema.swift's non-Linux integer check calls an unavailable WASI
# CoreFoundation API, so WASI uses the existing portable fallback.
apply_dependency_patch \
  ".build/checkouts/JSONSchema.swift/" \
  "${JSONSCHEMA_REVISION}" \
  "${SCRIPT_DIRECTORY}wasm-patches/jsonschema-0.6.0-wasi.patch" \
  "Sources/Validators.swift"

# swift-cmark's C sources require wasi-libc's signal and memory-mapping
# compatibility shims. Package.swift links the matching emulation libraries.
swift build \
  "${swift_sdk_arguments[@]}" \
  --target MarkdownUtilitiesCore \
  -Xcc -D_WASI_EMULATED_SIGNAL \
  -Xcc -D_WASI_EMULATED_MMAN

# Running the product through `swift run` executes it with the SDK's configured
# WASM runtime and verifies real parsing behavior, not compilation alone.
swift run \
  "${swift_sdk_arguments[@]}" \
  -Xcc -D_WASI_EMULATED_SIGNAL \
  -Xcc -D_WASI_EMULATED_MMAN \
  MarkdownUtilitiesCoreWasmSmoke
