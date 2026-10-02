#!/usr/bin/env python3
"""Restore exact dependency repositories and rebuild, optionally editing JXKit."""
import argparse
import json
import os
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--prepare-only", action="store_true")
parser.add_argument("--edit-jxkit", action="store_true")
options = parser.parse_args()
root = Path(__file__).resolve().parent
project = root / "md-utils"
mirrors = root / "mirrors"
mirrors.mkdir(exist_ok=True)
# Git URL rewrites preserve SwiftPM's original package identities and implicit
# product names. SwiftPM-level mirrors can change legacy inferred names (Yams,
# Rainbow), and do not cover all transitive .git/non-.git URL spellings.
# Configuration and file transport are scoped to these child processes only.
git_config = root / "rebuild-gitconfig"
git_config.write_text("")
entries = json.loads((root / "dependencies.json").read_text())
entries += json.loads((root / "submodules.json").read_text())
for entry in entries:
    mirror = mirrors / f"{entry['identity']}.git"
    if not mirror.exists():
        subprocess.run(["git", "clone", "--bare", str(root / "dependencies" / f"{entry['identity']}.bundle"), str(mirror)], check=True)
    original = entry["url"].removesuffix(".git")
    for spelling in (original, original + ".git"):
        subprocess.run(["git", "config", "--file", str(git_config), "--add",
                        f"url.{mirror.as_uri()}.insteadOf", spelling], check=True)
environment = os.environ.copy()
environment["GIT_CONFIG_GLOBAL"] = str(git_config)
environment["GIT_CONFIG_COUNT"] = "1"
environment["GIT_CONFIG_KEY_0"] = "protocol.file.allow"
environment["GIT_CONFIG_VALUE_0"] = "always"
subprocess.run(["swift", "package", "resolve", "--force-resolved-versions"], cwd=project, env=environment, check=True)
if options.edit_jxkit and not (project / "Packages/JXKit").exists():
    subprocess.run(["swift", "package", "edit", "JXKit"], cwd=project, env=environment, check=True)
if not options.prepare_only:
    subprocess.run(["swift", "build", "-c", "release", "--product", "md-utils", "--static-swift-stdlib"], cwd=project, env=environment, check=True)
