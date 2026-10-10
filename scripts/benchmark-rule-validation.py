#!/usr/bin/env python3
"""Compare direct and automatic indexed rule validation with real schema/body checks.

Build first, then pass --binary if measuring a debug or alternative build.
Disposable corpora and results stay under the project's tmp/ directory.
"""
import argparse
import json
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=ROOT / ".build/release/md-utils")
    parser.add_argument("--count", type=int, default=2000)
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--build-description", default="release")
    args = parser.parse_args()
    if args.count < 1 or args.repeat < 1:
        parser.error("--count and --repeat must be positive")
    binary = args.binary.resolve()
    output = ROOT / "tmp/rule-validation-benchmark"
    output.mkdir(parents=True, exist_ok=True)
    project = output / f"corpus-{uuid.uuid4()}"
    project.mkdir()
    results = {
        "platform": platform.platform(), "machine": platform.machine(),
        "binary": str(binary), "build_description": args.build_description,
        "documents": args.count, "repeat": args.repeat,
        "warm_filesystem_cache": True, "phases": [],
    }

    def run(arguments):
        start = time.perf_counter()
        completed = subprocess.run([str(binary), *arguments], cwd=project,
                                   capture_output=True, text=True, check=True)
        elapsed = time.perf_counter() - start
        if "index validation unavailable" in completed.stderr:
            raise RuntimeError(completed.stderr)
        return elapsed, completed.stdout

    def measure(phase, extra, expected=None, repeats=None):
        times = []
        for _ in range(repeats or args.repeat):
            elapsed, text = run(["rules", "validate", "books", "--include-ok", *extra])
            if expected is not None and text != expected:
                raise RuntimeError(f"Validation output differs in {phase}")
            times.append(elapsed)
        results["phases"].append({"phase": phase, "seconds": times,
                                  "median_seconds": statistics.median(times)})
        return text

    try:
        settings = project / ".md-utils"
        (settings / "types").mkdir(parents=True)
        (settings / "rules").mkdir()
        (settings / "md-utils.json").write_text(json.dumps({"configVersion": "0.3.0"}))
        (settings / "types/book.mdtype.json").write_text(json.dumps({
            "md-utils-type-schema": "1", "name": "Book", "version": "1",
            "frontmatter": {"schemas": [{"inline": {
                "type": "object", "required": ["title", "status"],
                "properties": {"title": {"type": "string"},
                               "status": {"enum": ["draft", "published"]}},
            }}]},
            "body": {"requirements": [{"id": "title", "heading": {"text": "Book"}}],
                     "recommendations": []},
            "context": {"requirements": [], "recommendations": []},
        }))
        (settings / "rules/books.mdrule.json").write_text(json.dumps({
            "name": "books", "match": {"paths": ["notes/**"]}, "types": "book.mdtype.json",
        }))
        notes = project / "notes"
        notes.mkdir()
        for index in range(args.count):
            (notes / f"{index:08d}.md").write_text(
                f"---\ntitle: Book {index}\nstatus: draft\n---\n# Book\n" + "Some book text.\n" * 50)
        direct = measure("direct", ["--no-index"])
        run(["index", "field", "list"])
        measure("initial-indexed", [], expected=direct, repeats=1)
        measure("unchanged-indexed", [], expected=direct)
        changed = max(1, args.count // 1000)
        for index in range(changed):
            with (notes / f"{index:08d}.md").open("a") as file:
                file.write("Changed text.\n")
        measure("small-update-indexed", [], expected=direct, repeats=1)
        results["small_update_files"] = changed
        destination = output / "results.json"
        destination.write_text(json.dumps(results, indent=2) + "\n")
        print(json.dumps(results, indent=2))
        print(f"Results: {destination}")
    finally:
        shutil.rmtree(project)


if __name__ == "__main__":
    main()
