#!/usr/bin/env python3
"""Check published schema changes against a Git base revision. Released schemas
remain immutable except for the first additive optional creation field in the
in-development 0.3.0 rule schema. Comparing the remainder structurally prevents
this exception from admitting unrelated edits or later changes to that field.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    args = parser.parse_args()
    paths = subprocess.check_output(
        ["git", "diff", "--name-only", args.base, "--", "site/schemas/*/*.json"],
        text=True,
    ).splitlines()
    rejected = []
    for path in paths:
        previous = subprocess.run(
            ["git", "show", f"{args.base}:{path}"], capture_output=True, text=True,
        )
        if previous.returncode:
            continue  # New schema files have no published baseline to preserve.
        allowed = False
        if path == "site/schemas/0.3.0/mdrule.schema.json" and Path(path).is_file():
            old = json.loads(previous.stdout)
            new = json.loads(Path(path).read_text())
            old_properties = old.get("properties", {})
            new_properties = new.get("properties", {})
            if "creation" not in old_properties and "creation" in new_properties:
                new_properties.pop("creation")
                allowed = new == old
        if not allowed:
            rejected.append(path)
    for path in rejected:
        print(f"Published schema is immutable: {path}; add a new schema version.", file=sys.stderr)
    return 1 if rejected else 0


if __name__ == "__main__":
    sys.exit(main())
