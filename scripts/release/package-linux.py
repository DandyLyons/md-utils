#!/usr/bin/env python3
"""Build Linux release archives, including exact dependency source repositories."""

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = (
    "md-utils_md-utils.resources",
    "md-utils_MarkdownUtilitiesServer.resources",
    "SwiftKnap_SwiftKnap.resources",
    "JXKit_JXKit.resources",
)
SERVER_RESOURCES = (
    "md-utils_md-utils-server.resources",
    "md-utils_MarkdownUtilitiesServer.resources",
    "SwiftKnap_SwiftKnap.resources",
    "JXKit_JXKit.resources",
)


def validate_version(version):
    # The initial distribution is deliberately prerelease-only. Schema versions
    # are unrelated, and are never stamped by this script.
    if not re.fullmatch(r"0\.[0-9]+\.[0-9]+-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*", version):
        raise ValueError("Expected a 0.x.y prerelease version, e.g. 0.3.0-linux.1")


def run(*args, cwd=ROOT):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def archive(directory, output):
    destination = output / (directory.name + ".tar.gz")
    with tarfile.open(destination, "w:gz") as tar:
        tar.add(directory, arcname=directory.name)
    with destination.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    destination.with_name(destination.name + ".sha256").write_text(
        f"{digest}  {destination.name}\n"
    )


def bundle_submodules(checkout, bundles, entries):
    modules = checkout / ".gitmodules"
    if not modules.exists():
        return
    records = run("git", "config", "--file", str(modules), "--null", "--get-regexp",
                  r"^submodule\..*\.path$", cwd=checkout)
    for record in records.rstrip("\0").split("\0"):
        _, relative_path = record.split("\n", 1)
        submodule = (checkout / relative_path).resolve()
        submodule.relative_to(checkout.resolve())
        url = run("git", "remote", "get-url", "origin", cwd=submodule)
        revision = run("git", "rev-parse", "HEAD", cwd=submodule)
        name = "submodule-" + hashlib.sha256(url.encode()).hexdigest()[:16]
        # A URL may occur in several parents; retain each required revision.
        name += "-" + revision
        destination = bundles / f"{name}.bundle"
        if not destination.exists():
            run("git", "bundle", "create", str(destination), "--all", cwd=submodule)
        if not any(entry["identity"] == name for entry in entries):
            entries.append({"identity": name, "url": url, "revision": revision})
            bundle_submodules(submodule, bundles, entries)


def package(version, commit, bin_dir):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Expected a full Git source commit")
    output = ROOT / "tmp/release-output"
    stage = ROOT / "tmp/release-stage"
    # Refuse to mix assets from different builds.
    output.mkdir(parents=True, exist_ok=False)
    stage.mkdir(parents=True, exist_ok=False)
    name = f"md-utils-{version}-linux-aarch64-ubuntu24.04"
    binary = stage / name
    binary.mkdir()
    shutil.copy2(bin_dir / "md-utils", binary)
    for resource in RESOURCES:
        shutil.copytree(bin_dir / resource, binary / resource)
    notices = binary / "licenses"
    notices.mkdir()
    shutil.copy2("/usr/share/common-licenses/GPL-3", notices / "GPL-3")
    with urllib.request.urlopen(
        "https://raw.githubusercontent.com/swiftlang/swift/swift-6.3.1-RELEASE/LICENSE.txt",
        timeout=60,
    ) as response:
        (notices / "Swift-LICENSE.txt").write_bytes(response.read())

    source = stage / f"md-utils-{version}-source"
    source.mkdir()
    shutil.copytree(ROOT, source / "md-utils", ignore=shutil.ignore_patterns(
        ".git", ".build", "tmp", ".swiftpm", ".DS_Store",
    ))
    bundles = source / "dependencies"
    bundles.mkdir()
    state = json.loads((ROOT / ".build/workspace-state.json").read_text())
    dependencies = []
    submodules = []
    pins = {pin["identity"]: pin for pin in json.loads((ROOT / "Package.resolved").read_text())["pins"]}
    for dependency in state["object"]["dependencies"]:
        reference = dependency["packageRef"]
        identity = reference["identity"]
        checkout = ROOT / ".build/checkouts" / dependency["subpath"]
        revision = run("git", "rev-parse", "HEAD", cwd=checkout)
        if revision != pins[identity]["state"]["revision"]:
            raise ValueError(f"Unexpected revision for {identity}")
        # Bundles preserve original commit IDs and version tags for offline
        # SwiftPM resolution, without copying Git configuration/credentials.
        run("git", "bundle", "create", str(bundles / f"{identity}.bundle"), "--all", cwd=checkout)
        dependencies.append({"identity": identity, "url": reference["location"], "revision": revision})
        bundle_submodules(checkout, bundles, submodules)
        for path in checkout.rglob("*"):
            if path.is_file() and any(word in path.name.upper() for word in ("LICENSE", "NOTICE", "COPYING")) and ".git" not in path.parts:
                target = notices / identity / path.relative_to(checkout)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
        if identity == "swiftknap":
            shutil.copy2(checkout / "ThirdParty/README.md", notices / identity / "ThirdParty/README.md")
    if set(pins) != {item["identity"] for item in dependencies}:
        raise ValueError("Source archive must include every resolved dependency")
    (source / "dependencies.json").write_text(json.dumps(dependencies, indent=2) + "\n")
    (source / "submodules.json").write_text(json.dumps(submodules, indent=2) + "\n")
    shutil.copy2(ROOT / "scripts/release/rebuild-source.py", source / "rebuild-source.py")
    shutil.copy2(ROOT / "docs/linux-arm64-distribution.md", binary / "INSTALL.md")
    shutil.copy2(ROOT / "scripts/release/REBUILD.md", binary / "SOURCE.md")
    shutil.copy2(ROOT / "scripts/release/REBUILD.md", source / "README.md")
    shutil.copytree(notices, source / "licenses")
    metadata = {
        "version": version, "commit": commit, "swift": run("swift", "--version"),
        "architecture": "aarch64", "baseline": "Ubuntu 24.04 (glibc)",
        "resources": RESOURCES, "dependencies": dependencies, "submodules": submodules,
    }
    (binary / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    shutil.copy2(binary / "build.json", source / "build.json")
    shutil.copy2(ROOT / "tmp/release-linkage.txt", binary / "linkage.txt")
    archive(binary, output)
    server = stage / f"md-utils-server-{version}-linux-aarch64-ubuntu24.04"
    server.mkdir()
    shutil.copy2(bin_dir / "md-utils-server", server)
    for resource in SERVER_RESOURCES:
        shutil.copytree(bin_dir / resource, server / resource)
    shutil.copytree(notices, server / "licenses")
    shutil.copy2(ROOT / "docs/linux-arm64-server-distribution.md", server / "INSTALL.md")
    shutil.copy2(ROOT / "scripts/release/REBUILD.md", server / "SOURCE.md")
    server_metadata = {**metadata, "product": "md-utils-server", "resources": SERVER_RESOURCES}
    (server / "build.json").write_text(json.dumps(server_metadata, indent=2) + "\n")
    shutil.copy2(ROOT / "tmp/release-server-linkage.txt", server / "linkage.txt")
    (source / "server-build.json").write_text(json.dumps(server_metadata, indent=2) + "\n")
    archive(server, output)
    archive(source, output)


if __name__ == "__main__":
    operation, version, *arguments = sys.argv[1:]
    validate_version(version)
    if operation == "stamp" and not arguments:
        (ROOT / "Sources/md-utils/Resources/BuildVersion.txt").write_text(version + "\n")
        (ROOT / "Sources/md-utils-server/Resources/BuildVersion.txt").write_text(version + "\n")
    elif operation == "package" and len(arguments) == 2:
        package(version, arguments[0], Path(arguments[1]))
    else:
        raise SystemExit("Usage: package-linux.py stamp VERSION | package VERSION COMMIT BIN_DIR")
