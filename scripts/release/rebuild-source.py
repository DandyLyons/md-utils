#!/usr/bin/env python3
"""Restore exact dependency repositories and rebuild, optionally editing JXKit."""
import json
import os
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent
project = root / "md-utils"
mirrors = root / "mirrors"
mirrors.mkdir(exist_ok=True)
# URL rewrites and file transport are scoped to this rebuild process, never the
# user's global Git configuration. Submodule fetching inherits these settings.
submodules = json.loads((root / "submodules.json").read_text())
git_config = root / "submodule-gitconfig"
git_config.write_text("")
for submodule in submodules:
    mirror = mirrors / f"{submodule['identity']}.git"
    if not mirror.exists():
        subprocess.run(["git", "clone", "--bare", str(root / "dependencies" / f"{submodule['identity']}.bundle"), str(mirror)], check=True)
    subprocess.run(["git", "config", "--file", str(git_config), "--add",
                    f"url.{mirror.as_uri()}.insteadOf", submodule["url"]], check=True)
environment = os.environ.copy()
environment["GIT_CONFIG_GLOBAL"] = str(git_config)
environment["GIT_CONFIG_COUNT"] = "1"
environment["GIT_CONFIG_KEY_0"] = "protocol.file.allow"
environment["GIT_CONFIG_VALUE_0"] = "always"
for dependency in json.loads((root / "dependencies.json").read_text()):
    identity = dependency["identity"]
    mirror = mirrors / f"{identity}.git"
    if not mirror.exists():
        subprocess.run(["git", "clone", "--bare", str(root / "dependencies" / f"{identity}.bundle"), str(mirror)], check=True)
    subprocess.run(["swift", "package", "config", "set-mirror", "--original", dependency["url"], "--mirror", mirror.as_uri()], cwd=project, env=environment, check=True)
subprocess.run(["swift", "package", "resolve", "--force-resolved-versions"], cwd=project, env=environment, check=True)
if "--prepare-only" not in sys.argv:
    subprocess.run(["swift", "build", "-c", "release", "--product", "md-utils", "--static-swift-stdlib"], cwd=project, env=environment, check=True)
