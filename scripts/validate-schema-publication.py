#!/usr/bin/env python3
"""Validate md-utils public schema publication files."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path


CURRENT_VERSION = "0.1.0"
SCHEMA_FILE = "md-utils.schema.json"
BUNDLED_SCHEMA_FILE = f"{CURRENT_VERSION}_md-utils.schema.json"
VERSIONED_SCHEMA_FILE = f"md-utils-{CURRENT_VERSION}.schema.json"
VERSIONED_SCHEMA_URL = (
    f"https://dandylyons.github.io/md-utils/schemas/{CURRENT_VERSION}/{SCHEMA_FILE}"
)
LATEST_SCHEMA_URL = "https://dandylyons.github.io/md-utils/schemas/latest/md-utils.schema.json"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def load_json(path: Path) -> dict:
    return json.loads(read_text(path))


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def compare_files(left: Path, right: Path) -> None:
    if read_text(left) != read_text(right):
        fail(f"schema files differ: {left} and {right}")


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check-published",
        action="store_true",
        help="also compare local schema files with currently published Pages endpoints",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    bundled = repo_root / "Sources/md-utils/Resources" / BUNDLED_SCHEMA_FILE
    versioned = repo_root / "site/schemas" / CURRENT_VERSION / SCHEMA_FILE
    named_versioned = repo_root / "site/schemas" / CURRENT_VERSION / VERSIONED_SCHEMA_FILE

    for path in [bundled, versioned, named_versioned]:
        if not path.exists():
            fail(f"missing schema file: {path}")

    compare_files(bundled, versioned)
    compare_files(bundled, named_versioned)

    schema = load_json(bundled)
    if schema.get("$id") != VERSIONED_SCHEMA_URL:
        fail(f"schema $id must be {VERSIONED_SCHEMA_URL}")

    if args.check_published:
        local_schema = load_json(versioned)
        for url in [VERSIONED_SCHEMA_URL, LATEST_SCHEMA_URL]:
            if fetch_json(url) != local_schema:
                fail(f"published schema differs from local schema: {url}")

    print("schema publication files are valid")


if __name__ == "__main__":
    main()
