#!/usr/bin/env python3
"""Check skill routing, relative links, bundle synchronization, and CLI coverage.

The standard-library-only checker follows Markdown file links from SKILL.md and
rejects missing, escaped, or unreachable resources. With --cli it recursively
reads executable help and checks every top-level command against the audit matrix,
saving the command inventory under project tmp/ for human review.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skill/markdown-utilities/skills/markdown-utilities"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path)
    args = parser.parse_args()
    subprocess.run(["python3", str(ROOT / "scripts/sync-agent-skill.py"), "--check"], check=True)
    reachable = set()
    pending = [SKILL / "SKILL.md"]
    while pending:
        path = pending.pop().resolve()
        if path in reachable:
            continue
        reachable.add(path)
        for link in re.findall(r"\]\(([^)]+)\)", path.read_text()):
            if "://" in link or link.startswith("#"):
                continue
            target = (path.parent / link.split("#")[0]).resolve()
            if not target.is_relative_to(SKILL.resolve()) or not target.is_file():
                raise SystemExit(f"Invalid local link in {path}: {link}")
            if target.suffix == ".md":
                pending.append(target)
    missing = set(p.resolve() for p in SKILL.rglob("*.md")) - reachable
    if missing:
        raise SystemExit(f"Unreachable references: {missing}")
    print(f"All {len(reachable)} skill Markdown files are reachable with valid local file links")
    if args.cli:
        executable = args.cli.resolve()
        inventory = {}
        pending = [()]
        while pending:
            command = pending.pop()
            if len(command) > 8 or len(inventory) > 500:
                raise SystemExit(f"Unexpected help hierarchy: {command}")
            help_text = subprocess.check_output([str(executable), *command, "--help"], text=True)
            inventory[" ".join(command)] = help_text
            if "SUBCOMMANDS:\n" in help_text:
                # Discussion may contain example SUBCOMMANDS lists; only the final
                # generated section defines the executable's child commands.
                section = help_text.rsplit("SUBCOMMANDS:\n", 1)[1].split("\n\n", 1)[0]
                for line in section.splitlines():
                    match = re.match(r"^  ([A-Za-z][\w-]*)(?:,| \(|\s{2,}|$)", line)
                    if match:
                        pending.append((*command, match.group(1)))
        matrix = (ROOT / "docs/agent-skill-audit.md").read_text()
        for command in inventory:
            if command and " " not in command and f"`{command}`" not in matrix:
                raise SystemExit(f"Missing coverage matrix entry: {command}")
        report = ROOT / "tmp/agent-skill-help.json"
        report.parent.mkdir(exist_ok=True)
        report.write_text(json.dumps(inventory, indent=2) + "\n")
        print(f"Verified {len(inventory)} command help pages; inventory: {report}")


if __name__ == "__main__":
    main()
