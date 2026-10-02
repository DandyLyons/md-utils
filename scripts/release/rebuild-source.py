#!/usr/bin/env python3
"""Restore exact dependency repositories and rebuild, optionally editing JXKit."""
import json
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent
project = root / "md-utils"
mirrors = root / "mirrors"
mirrors.mkdir(exist_ok=True)
for dependency in json.loads((root / "dependencies.json").read_text()):
    identity = dependency["identity"]
    mirror = mirrors / f"{identity}.git"
    if not mirror.exists():
        subprocess.run(["git", "clone", "--bare", str(root / "dependencies" / f"{identity}.bundle"), str(mirror)], check=True)
    subprocess.run(["swift", "package", "config", "set-mirror", "--original", dependency["url"], "--mirror", mirror.as_uri()], cwd=project, check=True)
subprocess.run(["swift", "package", "resolve", "--force-resolved-versions"], cwd=project, check=True)
if "--prepare-only" not in sys.argv:
    subprocess.run(["swift", "build", "-c", "release", "--product", "md-utils", "--static-swift-stdlib"], cwd=project, check=True)
