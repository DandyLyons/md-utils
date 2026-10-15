#!/usr/bin/env python3
"""Measure outgoing-query scaling against unrelated document contents.

Create an isolated collection under the project's tmp/ directory, time repeated
CLI invocations with exact and bare-name links, and remove the fixture afterward.
This separates direct destination lookup from required basename discovery without
touching a user's vault or index. No third-party packages are needed.
"""

import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default=".build/debug/md-utils")
    parser.add_argument("--files", type=int, default=1000)
    parser.add_argument("--repeats", type=int, default=5)
    args = parser.parse_args()
    binary = Path(args.binary).resolve()
    temporary = Path("tmp")
    temporary.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="outgoing-benchmark-", dir=temporary) as directory:
        root = Path(directory).resolve()
        (root / "targets").mkdir()
        (root / "targets/target.md").write_text("# Target\n", encoding="utf-8")
        (root / "noise").mkdir()
        for count in (0, args.files):
            # Each unrelated document is large enough to expose eager reads.
            for index in range(count):
                (root / f"noise/{index}.md").write_text("unrelated content\n" * 2048, encoding="utf-8")
            for name, content in (("exact", "[target](targets/target.md)\n"), ("bare", "[[target]]\n")):
                (root / "source.md").write_text(content, encoding="utf-8")
                elapsed = []
                for _ in range(args.repeats):
                    started = time.perf_counter()
                    result = subprocess.run(
                        [str(binary), "rel", "out", "source.md", "--root", str(root), "--json", "--detail", "explain"],
                        capture_output=True, text=True, check=True,
                    )
                    elapsed.append(time.perf_counter() - started)
                    payload = json.loads(result.stdout)
                    assert payload["links"][0]["object"] == "targets/target.md"
                print(json.dumps({"unrelated_files": count, "lookup": name,
                                  "median_seconds": round(statistics.median(elapsed), 4),
                                  "runs_seconds": [round(value, 4) for value in elapsed]}))


if __name__ == "__main__":
    main()
