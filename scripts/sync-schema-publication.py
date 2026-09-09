#!/usr/bin/env python3
"""Generate public schema copies from canonical bundled resources."""
from __future__ import annotations
import argparse
import re
from pathlib import Path
from shutil import copyfile

PATTERN = re.compile(r"^(?P<version>[^_]+)_(?P<name>.+)\.schema\.json$")

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail when generated copies differ")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    resources, site = root / "Sources/md-utils/Resources", root / "site/schemas"
    found = False
    expected: set[Path] = set()
    for source in sorted(resources.glob("*_*.schema.json")):
        match = PATTERN.match(source.name)
        if match is None:
            continue
        found = True
        version, name = match.group("version"), match.group("name")
        if name not in {"md-utils", "mdrule"}:
            continue
        destinations = [site / version / f"{name}.schema.json"]
        if name == "md-utils" and version in {"0.1.0", "0.2.0"}:
            destinations.append(site / version / f"md-utils-{version}.schema.json")
        expected.update(destinations)
        for destination in destinations:
            if args.check:
                if not destination.exists() or source.read_bytes() != destination.read_bytes():
                    raise SystemExit(f"error: generated schema is out of date: {destination}")
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                copyfile(source, destination)
    if not found:
        raise SystemExit("error: no canonical schema resources found")
    actual = set(site.glob("*/*.schema.json"))
    unexpected = sorted(actual - expected)
    if unexpected:
        raise SystemExit(f"error: public schema has no canonical source: {unexpected[0]}")
    print("schema publication copies are up to date" if args.check else "schema publication copies generated")

if __name__ == "__main__":
    main()
