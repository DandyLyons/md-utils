#!/usr/bin/env python3
"""Measure verified relationship cache reuse and invalidation on paired cyclic records.

Creates an isolated corpus under project tmp/, initializes the disposable index,
and compares direct, cold, warm, target-edit, and namespace-change policy validation.
macOS time reports peak resident memory; SQLite reports retained and staged bytes.
No tools are installed. The corpus is retained for inspection, with its path in JSON.
"""
import argparse
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import time
import uuid


def main():
    repository = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=repository / ".build/debug/md-utils")
    parser.add_argument("--files", type=int, default=1000)
    parser.add_argument("--runs", type=int, default=3)
    args = parser.parse_args()
    if args.files < 4 or args.files > 10000 or args.files % 2 or args.runs < 1:
        parser.error("files must be even, between 4 and 10000; runs must be positive")
    root = repository / "tmp" / f"relationship-cache-{uuid.uuid4()}"
    settings = root / ".md-utils"
    (settings / "types").mkdir(parents=True)
    (settings / "rules").mkdir()
    (settings / "md-utils.json").write_text('{"configVersion":"0.3.0"}')
    definition = {
        "md-utils-type-schema": "2", "name": "Person", "version": "1",
        "requires": ["document-relationships"],
        "frontmatter": {"schemas": [{"inline": {"type": "object", "required": ["name"]}}]},
        "body": {"requirements": [], "recommendations": []},
        "context": {"requirements": [], "recommendations": []},
        "relationships": {"friends": {"select": ["friends", {"each": True}],
                                      "target": {"type": "person.mdtype.json"}}},
    }
    (settings / "types/person.mdtype.json").write_text(json.dumps(definition))
    (settings / "rules/people.mdrule.json").write_text(json.dumps({
        "md-utils-rule-schema": "1", "name": "people", "types": "person.mdtype.json",
        "relationshipPolicies": [{"id": "return", "kind": "reciprocity", "scope": "selected",
                                  "relation": {"type": "person.mdtype.json", "name": "friends"}}],
    }))
    for index in range(args.files):
        (root / f"{index:05}.md").write_text(
            f"---\nname: Person {index}\nfriends: ['[[{index ^ 1:05}]]']\n---\n")
    binary = str(args.binary.resolve())
    common = ["--project-root", str(root) + "/", "--config", str(settings / "md-utils.json")]
    database = settings / "index.sqlite"

    def manifest():
        if not database.exists():
            return []
        with sqlite3.connect(database) as db:
            return db.execute("SELECT certificate,generation FROM relationship_cache ORDER BY request").fetchall()

    def measure(label, flags=()):
        print(f"Measuring {label} on {args.files} records", file=sys.stderr, flush=True)
        before = manifest()
        started = time.perf_counter()
        result = subprocess.run(["/usr/bin/time", "-l", binary, "rules", "validate", "people",
                                 "--json", *common, *flags], stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE, text=True, cwd=root)
        elapsed = time.perf_counter() - started
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr)
        peak = re.search(r"(\d+)\s+maximum resident set size", result.stderr)
        if peak is None:
            raise RuntimeError("Peak RSS measurement unavailable: " + result.stderr)
        expected = 0 if label in ("direct", "cold", "unchanged") else 1
        if result.returncode != expected:
            raise RuntimeError(f"Unexpected validation exit for {label}: " + result.stderr)
        after = manifest()
        print(f"  {elapsed:.3f}s; peak RSS {int(peak.group(1))} bytes", file=sys.stderr, flush=True)
        return {"scenario": label, "seconds": elapsed, "exit_status": result.returncode,
                "peak_rss_bytes": int(peak.group(1)),
                "reused_manifest": bool(before) and before == after and "--no-index" not in flags}

    results = [measure("direct", ["--no-index"])]
    subprocess.run([binary, "index", "update", "./", *common], cwd=root, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    results.append(measure("cold"))
    results.extend(measure("unchanged") for _ in range(args.runs))
    # The source of the incoming assertion is unchanged; only its target contract fails.
    (root / "00001.md").write_text("---\nfriends: ['[[00000]]']\n---\n")
    results.append(measure("target_edit"))
    results.append(measure("unchanged_failure"))
    # Keep the corpus at the configured record budget while introducing a duplicate basename.
    (root / "duplicate").mkdir()
    (root / f"{args.files - 1:05}.md").rename(root / "duplicate/00001.md")
    results.append(measure("namespace_change"))
    results.append(measure("unchanged_ambiguity"))
    with sqlite3.connect(database) as db:
        retained = db.execute("SELECT coalesce(sum(bytes),0) FROM relationship_cache").fetchone()[0]
        chunks = db.execute("SELECT coalesce(max(length(payload)),0) FROM relationship_chunks").fetchone()[0]
        staging = db.execute("SELECT count(*) FROM refresh_relationship_chunks").fetchone()[0]
    print(json.dumps({"files": args.files, "corpus": str(root) + "/", "binary": binary,
                      "results": results, "retained_payload_bytes": retained,
                      "largest_chunk_bytes": chunks, "staging_rows_after": staging,
                      "database_bytes": database.stat().st_size}, indent=2))


if __name__ == "__main__":
    main()
