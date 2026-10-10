#!/usr/bin/env python3
"""Compare unchanged discovery validation with indexed-only validation across broad scopes.

Creates a disposable corpus under the project's tmp/ directory, registers broad
rule scopes, warms both validation modes, and reports median elapsed time. Build
the desired CLI first and pass --binary to compare debug and release builds.
"""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import time
import uuid


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=root / ".build/release/md-utils")
    parser.add_argument("--files", type=int, default=10000)
    parser.add_argument("--scopes", type=int, default=5)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    if min(args.files, args.scopes, args.runs) < 1:
        parser.error("files, scopes, and runs must be positive")
    project = root / "tmp" / f"indexed-only-benchmark-{uuid.uuid4()}"
    settings = project / ".md-utils"
    (settings / "rules").mkdir(parents=True)
    (settings / "types").mkdir()
    (settings / "md-utils.json").write_text(json.dumps({"configVersion": "0.3.0"}))
    (settings / "types/book.mdtype.json").write_text(json.dumps({
        "md-utils-type-schema": "1", "name": "Book", "version": "1",
        "frontmatter": {"schemas": [{"inline": {"type": "object", "required": ["title"]}}]},
        "body": {"requirements": [], "recommendations": []},
        "context": {"requirements": [], "recommendations": []},
    }))
    for scope in range(args.scopes):
        (settings / f"rules/rule-{scope}.mdrule.json").write_text(json.dumps({
            "name": f"rule-{scope}", "match": {"paths": ["**/*.md"]},
            "types": "book.mdtype.json",
        }))
    for index in range(args.files):
        directory = project / "notes" / str(index // 1000)
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"{index}.md").write_text("---\ntitle: Book\n---\n# Book\n")
    binary = str(args.binary.resolve())

    def run(arguments):
        started = time.perf_counter()
        subprocess.run([binary, *arguments, "--project-root", str(project) + "/",
                        "--config", str(settings / "md-utils.json")],
                       cwd=project, check=True, stdout=subprocess.DEVNULL)
        return time.perf_counter() - started

    # Register all scopes with full discovery before measuring unchanged runs.
    for scope in range(args.scopes):
        run(["index", "rule", f"rule-{scope}"])
    results = {"files": args.files, "scopes": args.scopes, "corpus": str(project) + "/"}
    for mode, flags in [("discovery", []), ("indexed_only", ["--indexed-only"])]:
        run(["rules", "validate", *flags])
        samples = [run(["rules", "validate", *flags]) for _ in range(args.runs)]
        results[mode] = {"seconds": samples, "median_seconds": statistics.median(samples)}
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
