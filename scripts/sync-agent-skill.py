#!/usr/bin/env python3
"""Synchronize the canonical installed skill into the CLI resource bundle.

Copy the entire skill tree, preserving reference paths. Check mode compares all
file names and bytes without writing, so CI detects additions, deletions, and
stale copies rather than checking only SKILL.md. No third-party packages are used.
"""

import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "skill/markdown-utilities/skills/markdown-utilities"
DESTINATION = ROOT / "Sources/md-utils/Resources/AgentSkill"


def files(directory):
    """Reject links and inventory regular files relative to a skill root."""
    result = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise SystemExit(f"Unexpected skill symlink: {path}")
        if path.is_file():
            result[path.relative_to(directory)] = path.read_bytes()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Report drift without writing")
    args = parser.parse_args()
    expected = files(SOURCE)
    if not expected or Path("SKILL.md") not in expected:
        raise SystemExit("Canonical skill is missing")
    if args.check:
        if expected != files(DESTINATION):
            raise SystemExit("Skill bundle is out of sync; run python3 scripts/sync-agent-skill.py")
        print(f"Skill bundle matches all {len(expected)} canonical files")
        return
    # Replace only the generated resource directory; canonical files remain untouched.
    if DESTINATION.is_symlink():
        raise SystemExit("Refusing to replace a symlinked bundle directory")
    if DESTINATION.exists():
        shutil.rmtree(DESTINATION)
    shutil.copytree(SOURCE, DESTINATION)
    print(f"Synchronized {len(expected)} skill files")


if __name__ == "__main__":
    main()
