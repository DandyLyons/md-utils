#!/usr/bin/env python3
"""Measure native indexed-server RSS and bounded page reads on a generated corpus.

Run separately for each corpus size so child peak RSS is independent. All generated
files stay under the project's tmp/ directory. No packages or network services needed.
"""
import argparse
import json
import pathlib
import resource
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=100_000)
    parser.add_argument("--body-bytes", type=int, default=4096)
    parser.add_argument("--binary", default=".build/debug/md-utils-server")
    parser.add_argument("--keep", action="store_true")
    args = parser.parse_args()
    if args.count < 1 or args.body_bytes < 16:
        parser.error("count must be positive and body-bytes at least 16")
    project = pathlib.Path(__file__).resolve().parent.parent
    (project / "tmp").mkdir(exist_ok=True)
    root = pathlib.Path(tempfile.mkdtemp(prefix="server-scale-", dir=project / "tmp"))
    server = None
    try:
        config = root / ".md-utils" / "server"
        config.mkdir(parents=True)
        (config / "server.yaml").write_text('''serverConfigVersion: "1"
resources:
  - name: records
    route: /records
    operations: [list, get]
    selection:
      mode: rule
      rule: all
    identityPolicy:
      source: logicalPath
''')
        (root / ".md-utils" / "md-utils.json").write_text(json.dumps({
            "configVersion": "0.2.0", "rules": [{"name": "all", "match": {"paths": ["records/**"]},
                "checks": [{"type": "requiredHeading", "heading": "Record"}]}]
        }))
        records = root / "records"
        records.mkdir()
        body = "# Record\n" + "x" * (args.body_bytes - len("# Record\n"))
        for index in range(args.count):
            (records / f"{index:08d}.md").write_text(f"---\nnumber: {index}\n---\n{body}")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        log_path = root / "server.log"
        started = time.monotonic()
        with log_path.open("w") as log:
            server = subprocess.Popen([str((project / args.binary).resolve()), "serve", "--project-root", str(root),
                                       "--port", str(port)], stdout=log, stderr=subprocess.STDOUT)
            url = f"http://127.0.0.1:{port}/records?limit=1000"
            deadline = started + 1800
            while True:
                if server.poll() is not None:
                    raise RuntimeError(log_path.read_text())
                try:
                    with urllib.request.urlopen(url, timeout=60) as response:
                        data = response.read(64 * 1024 * 1024 + 1)
                    break
                except OSError:
                    if time.monotonic() > deadline:
                        raise RuntimeError("Server startup exceeded 30 minutes")
                    time.sleep(0.25)
            ready_seconds = time.monotonic() - started
            page = json.loads(data)
            assert len(page["records"]) == min(args.count, 1000)
            assert all(record["body"] == body for record in page["records"])
            assert len(data) <= 64 * 1024 * 1024
            read_start = time.monotonic()
            with urllib.request.urlopen(url, timeout=60) as response:
                response.read()
            read_seconds = time.monotonic() - read_start
            server.terminate()
            server.wait(timeout=30)
        peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        # Darwin reports bytes; Linux reports KiB.
        import sys
        peak_bytes = peak if sys.platform == "darwin" else peak * 1024
        print(json.dumps({"count": args.count, "body_bytes": args.body_bytes,
                          "corpus_body_bytes": args.count * args.body_bytes,
                          "startup_and_first_page_seconds": round(ready_seconds, 3),
                          "warm_page_seconds": round(read_seconds, 3),
                          "page_bytes": len(data), "peak_rss_bytes": peak_bytes,
                          "fixture": str(root) if args.keep else None}, indent=2))
    finally:
        if server is not None and server.poll() is None:
            server.kill()
            server.wait()
        if not args.keep:
            shutil.rmtree(root)


if __name__ == "__main__":
    main()
