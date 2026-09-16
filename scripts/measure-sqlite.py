#!/usr/bin/env python3
"""Measure native GRDB overhead and test copied production sources in isolation.

Every run uses a fresh project-local build directory. The generated package uses
the root lockfile's GRDB pin, but no unrelated CLI/server dependencies or builds.
"""
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
pins = json.loads((ROOT / "Package.resolved").read_text())["pins"]
pin = next(pin for pin in pins if pin["identity"] == "grdb.swift")
version = pin["state"]["version"]
crypto_version = next(pin for pin in pins if pin["identity"] == "swift-crypto")["state"]["version"]
scratch = ROOT / "tmp/"
scratch.mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix="grdb-measure-", dir=scratch))
print(f"Measurement workspace: {work}/", flush=True)

# Copy source, never reuse another build directory. Also run the actual index tests.
for source, destination in [
    ("Sources/MarkdownUtilitiesIndex/", "Sources/MarkdownUtilitiesIndex/"),
    ("IntegrationTests/SQLiteIndexSmoke/", "Sources/SQLiteIndexSmoke/"),
    ("Tests/MarkdownUtilitiesIndexTests/", "Tests/MarkdownUtilitiesIndexTests/"),
]:
    shutil.copytree(ROOT / source, work / destination)
(work / "Sources/Baseline/").mkdir(parents=True)
(work / "Sources/Baseline/main.swift").write_text(
    'import GRDBSQLite\nprint("System SQLite \\(String(cString: sqlite3_libversion()))")\n'
)
(work / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "SQLiteMeasurement",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "GRDB_VERSION"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "CRYPTO_VERSION"),
    ],
    targets: [
        .target(name: "MarkdownUtilitiesIndex", dependencies: [
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "GRDBSQLite", package: "GRDB.swift"),
        ]),
        .executableTarget(name: "SQLiteIndexSmoke", dependencies: [
            "MarkdownUtilitiesIndex", .product(name: "GRDBSQLite", package: "GRDB.swift"),
        ]),
        .executableTarget(name: "Baseline", dependencies: [
            .product(name: "GRDBSQLite", package: "GRDB.swift"),
        ]),
        .testTarget(name: "MarkdownUtilitiesIndexTests", dependencies: ["MarkdownUtilitiesIndex"]),
    ]
)
'''.replace("GRDB_VERSION", version).replace("CRYPTO_VERSION", crypto_version))

def run(arguments):
    print("+", " ".join(map(str, arguments)), flush=True)
    start = time.perf_counter()
    subprocess.run(list(map(str, arguments)), cwd=work, check=True)
    return time.perf_counter() - start

run(["swift", "--version"])
resolve_seconds = run(["swift", "package", "resolve"])
baseline_seconds = run(["swift", "build", "-c", "release", "--product", "Baseline"])
grdb_seconds = run(["swift", "build", "-c", "release", "--product", "SQLiteIndexSmoke"])
warm_seconds = run(["swift", "build", "-c", "release", "--product", "SQLiteIndexSmoke"])
bin_path = Path(subprocess.check_output(
    ["swift", "build", "-c", "release", "--show-bin-path"], cwd=work, text=True
).strip())
run([bin_path / "Baseline"])
run([bin_path / "SQLiteIndexSmoke"])
run(["swift", "test", "--filter", "MarkdownUtilitiesIndexTests"])

sizes = {}
for name in ("Baseline", "SQLiteIndexSmoke"):
    executable = bin_path / name
    stripped = work / f"{name}-stripped"
    shutil.copy2(executable, stripped)
    run(["strip", stripped])
    run([stripped])
    sizes[name] = {"release_bytes": executable.stat().st_size, "stripped_bytes": stripped.stat().st_size}

# Verify dynamic system SQLite linkage and reject accidentally embedded SQLite definitions.
if platform.system() == "Darwin":
    linkage = subprocess.check_output(["otool", "-L", str(bin_path / "SQLiteIndexSmoke")], text=True)
    symbols = subprocess.check_output(["nm", "-gU", str(bin_path / "SQLiteIndexSmoke")], text=True)
else:
    linkage = subprocess.check_output(["ldd", str(bin_path / "SQLiteIndexSmoke")], text=True)
    symbols = subprocess.check_output(["nm", "-g", "--defined-only", str(bin_path / "SQLiteIndexSmoke")], text=True)
print(linkage, flush=True)
if "libsqlite3" not in linkage:
    raise SystemExit("Expected dynamic system SQLite linkage")
if any(line.split()[-1].lstrip("_").startswith("sqlite3_") for line in symbols.splitlines() if line.split()):
    raise SystemExit("Unexpected embedded SQLite definition")

report = {
    "platform": platform.platform(), "grdb_version": version,
    "dependency_resolution_seconds": round(resolve_seconds, 3),
    "clean_baseline_seconds": round(baseline_seconds, 3),
    "clean_grdb_seconds": round(grdb_seconds, 3),
    "warm_noop_seconds": round(warm_seconds, 3), "sizes": sizes,
}
(work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2), flush=True)
