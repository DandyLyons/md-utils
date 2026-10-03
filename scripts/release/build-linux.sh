#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../"
test "$(uname -m)" = aarch64
version="${1:?Expected prerelease version}"
commit="${2:?Expected source commit}"
# The Python packager validates the version before it is written into resources.
python3 scripts/release/package-linux.py stamp "$version"
swift package resolve --force-resolved-versions
bash scripts/release/patch-jsonschema.sh
swift build -c release --product md-utils --static-swift-stdlib
bin_dir="$(swift build -c release --show-bin-path)"
readelf -h "$bin_dir/md-utils" | grep -q AArch64
ldd "$bin_dir/md-utils" | tee tmp/release-linkage.txt
if grep -q 'not found' tmp/release-linkage.txt || \
    grep -E 'libswift|lib_?Foundation|libdispatch|libBlocksRuntime' tmp/release-linkage.txt; then
    echo 'Release must not require missing libraries or a shared Swift runtime' >&2
    exit 1
fi
python3 scripts/release/package-linux.py package "$version" "$commit" "$bin_dir"
