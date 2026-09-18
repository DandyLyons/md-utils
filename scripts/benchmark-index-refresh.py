#!/usr/bin/env python3
"""Reproducible end-to-end refresh benchmark; all disposable data is under tmp/.

Build first: swift build -c release --product md-utils
Run: python3 scripts/benchmark-index-refresh.py --counts 100000
Each phase runs a fresh CLI process and records its own peak RSS with time(1).
"""
import argparse
import json
import platform
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--counts", nargs="+", type=int, default=[100000])
    parser.add_argument("--binary", type=Path, default=ROOT / ".build/release/md-utils")
    parser.add_argument("--swift", default="swift", help="Compiler executable used to build the measured binary")
    parser.add_argument("--output", type=Path, default=ROOT / "tmp/index-refresh-benchmark/")
    parser.add_argument("--build-description", default="release")
    parser.add_argument("--reuse-corpus", action="store_true",
                        help="Reset a previous generated corpus in the output directory before measuring")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    binary = args.binary.resolve()
    report = {
        "platform": platform.platform(), "machine": platform.machine(),
        "python": platform.python_version(),
        "swift": subprocess.check_output([args.swift, "--version"], text=True).strip(),
        "sqlite_observer": sqlite3.sqlite_version,
        "build_description": args.build_description,
        "budgets": {"peak_rss_bytes": 268435456, "seconds_per_100000_documents": 600},
        "distribution": {"1024_bytes": 90, "8192_bytes": 9, "65536_bytes": 1},
        "directory_fanout": 1000,
        "results": [],
    }
    if platform.system() == "Darwin":
        report["hardware"] = subprocess.check_output(
            ["sysctl", "-n", "machdep.cpu.brand_string", "hw.memsize"], text=True).strip()
    result_path = args.output / "results.json"

    def measure(project, count, mode, phase, arguments):
        log = args.output / f"{count}-{mode}-{phase}.time.txt"
        database = project / ".md-utils/index.sqlite"
        command = [str(binary), "index", *arguments, "--project-root", str(project)]
        timer = ["/usr/bin/time", "-l"] if platform.system() == "Darwin" else ["/usr/bin/time", "-v"]
        def cache_bytes():
            size = 0
            for path in database.parent.glob("index.sqlite*"):
                try:
                    size += path.stat().st_size
                except FileNotFoundError:
                    pass  # Journals can disappear between directory enumeration and stat.
            return size

        peak_disk = 0
        started = time.monotonic()
        with log.open("w") as output:
            process = subprocess.Popen(timer + command, cwd=project, stdout=output, stderr=output)
            while process.poll() is None:
                peak_disk = max(peak_disk, cache_bytes())
                time.sleep(0.25)
        elapsed = time.monotonic() - started
        peak_disk = max(peak_disk, cache_bytes())
        output = log.read_text()
        if process.returncode:
            raise RuntimeError(f"Benchmark failed: {command}\n{output}")
        if platform.system() == "Darwin":
            match = re.search(r"(\d+)\s+maximum resident set size", output)
            rss = int(match.group(1)) if match else None
        else:
            match = re.search(r"Maximum resident set size \(kbytes\): (\d+)", output)
            rss = int(match.group(1)) * 1024 if match else None
        with sqlite3.connect(database) as connection:
            staged = connection.execute("SELECT count(*) FROM refresh_files").fetchone()[0]
            documents = connection.execute("SELECT count(*) FROM documents").fetchone()[0]
            encoding = connection.execute("SELECT value FROM index_metadata WHERE key='metadata_encoding'").fetchone()
        result = {"documents": count, "mode": mode, "phase": phase,
                  "seconds": round(elapsed, 3), "peak_rss_bytes": rss,
                  "peak_database_and_journal_bytes": peak_disk,
                  "database_bytes": database.stat().st_size,
                  "remaining_staged_files": staged, "published_documents": documents,
                  "metadata_encoding": encoding}
        counts = re.search(r"Index: (\d+) evaluated, (\d+) cached, (\d+) hashed", output)
        if counts:
            result.update(zip(["evaluated", "cached", "hashed"], map(int, counts.groups())))
            changed = 0 if phase == "unchanged" else max(1, count // 1000) if phase == "small-update" else count
            expected_evaluations = 2 * count if phase == "overlap" else changed
            if result["hashed"] != changed or result["evaluated"] != expected_evaluations:
                raise RuntimeError(f"Unexpected extraction reuse: {result}")
        else:
            raise RuntimeError(f"Missing CLI refresh counters: {output}")
        result["within_memory_budget"] = rss is not None and rss <= report["budgets"]["peak_rss_bytes"]
        result["within_time_budget"] = elapsed <= 600 * count / 100000
        if staged != 0 or documents != count:
            raise RuntimeError(f"Incomplete publication: {result}")
        report["results"].append(result)
        result_path.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(result), flush=True)

    for count in args.counts:
        project = args.output / f"corpus-{count}/"
        project.mkdir(exist_ok=args.reuse_corpus)
        if args.reuse_corpus and (project / ".md-utils/").exists():
            shutil.rmtree(project / ".md-utils/")
        corpus_bytes = 0
        print(f"Generating {count} documents in {project}/", flush=True)
        for index in range(count):
            directory = project / "notes" / f"{index // 1000:04d}"
            if index % 1000 == 0:
                directory.mkdir(parents=True, exist_ok=True)
            size = 1024 if index % 100 < 90 else 8192 if index % 100 < 99 else 65536
            header = f"---\ntitle: Document {index}\nstatus: draft\nordinal: {index}\n---\n# Document {index}\n\n"
            prose = "A collection note about engineering, records, search, and reliable incremental updates.\n"
            text = (header + prose * ((size // len(prose)) + 1))[:size]
            (directory / f"{index:07d}.md").write_text(text)
            corpus_bytes += size
        report.setdefault("corpora", {})[str(count)] = {"source_bytes": corpus_bytes}
        for mode in ["metadata", "fts"]:
            if mode == "fts":
                # A fresh FTS cache measures initial indexing independently.
                shutil.rmtree(project / ".md-utils/")
                subprocess.run([str(binary), "index", "search", "enable", "--project-root", str(project)], check=True)
            measure(project, count, mode, "initial", ["update", "notes/"])
            measure(project, count, mode, "rebuild", ["update", "--rebuild"])
            measure(project, count, mode, "unchanged", ["update"])
            for index in range(max(1, count // 1000)):
                path = project / "notes" / f"{index // 1000:04d}" / f"{index:07d}.md"
                with path.open("a") as handle:
                    handle.write("\nSmall update.\n")
            measure(project, count, mode, "small-update", ["update"])
            measure(project, count, mode, "overlap", ["update", "./", "--rebuild"])
        shutil.rmtree(project)
    print(f"Results: {result_path}", flush=True)


if __name__ == "__main__":
    main()
