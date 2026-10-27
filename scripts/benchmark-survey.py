#!/usr/bin/env python3
"""Measure survey commands serially and retain their JSON for equivalence checks.

Runs the existing debug executable against a supplied collection with --no-index,
so benchmarks neither refresh nor create its cache. Reports elapsed time and exit
status; stores stdout/stderr under the repository's ignored tmp directory. Optional
macOS sampling captures the first command's CPU stacks with the installed sample
tool. No source documents are modified and no software is installed.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("scope", type=Path)
parser.add_argument("--project-root", required=True, type=Path)
parser.add_argument("--label", required=True)
parser.add_argument("--sample", action="store_true")
parser.add_argument("--compare", help="Compare complete JSON and exit status with a prior label")
args = parser.parse_args()
if any(not label.replace("-", "").replace("_", "").isalnum() for label in [args.label, args.compare] if label):
    parser.error("label must contain only letters, digits, underscores, or hyphens")
if args.compare == args.label:
    parser.error("comparison label must differ from the output label")
repo = Path(__file__).resolve().parents[1]
output = repo / "tmp" / ("survey-benchmark-" + args.label)
output.mkdir(parents=True, exist_ok=True)
measurements = []
baseline = repo / "tmp" / ("survey-benchmark-" + args.compare) if args.compare else None
prior = {row["metric"]: row for row in json.loads((baseline / "timings.json").read_text())} if baseline else {}
for metric in ["types", "rules", "overview"]:
    command = [str(repo / ".build/debug/md-utils"), "survey"]
    if metric != "overview":
        command.append(metric)
    command += [str(args.scope.resolve()), "--project-root", str(args.project_root.resolve()),
                "--format", "json", "--no-index", "--no-progress"]
    with (output / (metric + ".json")).open("w") as stdout, (output / (metric + ".err")).open("w") as stderr:
        started = time.perf_counter()
        process = subprocess.Popen(command, cwd=repo, stdout=stdout, stderr=stderr)
        try:
            if args.sample and metric == "types":
                if Path("/usr/bin/sample").is_file():
                    sample = subprocess.run(["/usr/bin/sample", str(process.pid), "2", "1", "-file", str(output / "sample.txt")],
                                            capture_output=True, text=True, check=False)
                    if sample.returncode:
                        print("Sampling unavailable: " + (sample.stderr or sample.stdout).strip(), flush=True)
                else:
                    print("Sampling unavailable: macOS sample is not installed", flush=True)
            status = process.wait()
        except BaseException:
            process.terminate()
            process.wait()
            raise
        elapsed = time.perf_counter() - started
    result = json.loads((output / (metric + ".json")).read_text())
    measurement = {"metric": metric, "seconds": round(elapsed, 3), "exit": status}
    if baseline:
        previous = json.loads((baseline / (metric + ".json")).read_text())
        if result != previous or status != prior[metric]["exit"]:
            changed = sorted(key for key in result.keys() | previous.keys() if result.get(key) != previous.get(key))
            raise SystemExit(f"Result changed for {metric}: fields={changed}, exit={status}")
        measurement["identical_result"] = True
        measurement["speedup"] = round(prior[metric]["seconds"] / elapsed, 2)
    measurements.append(measurement)
    print(json.dumps(measurement), flush=True)
(output / "timings.json").write_text(json.dumps(measurements, indent=2) + "\n")
