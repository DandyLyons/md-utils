#!/usr/bin/env bash
# Keep release builds and offline source rebuilds on the same reviewed fix.
set -euo pipefail
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checkout_directory="${1:-.build/checkouts/JSONSchema.swift/}"
expected_revision=d14de4b2d9205068c9db89c00d097ca43c897000
actual_revision="$(git -C "$checkout_directory" rev-parse HEAD)"
if [ "$actual_revision" != "$expected_revision" ]; then
    echo "Refusing to patch JSONSchema.swift at unexpected revision $actual_revision" >&2
    exit 1
fi
patch_file="$script_directory/jsonschema-0.6.0-native-containers.patch"
if git -C "$checkout_directory" apply --reverse --check "$patch_file" 2>/dev/null; then
    exit 0
fi
git -C "$checkout_directory" apply --check "$patch_file"
# SwiftPM checkouts can be read-only. Change only the reviewed source file.
chmod u+w "$checkout_directory/Sources/Validators.swift"
git -C "$checkout_directory" apply "$patch_file"
