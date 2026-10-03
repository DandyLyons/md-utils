#!/usr/bin/env python3
"""Exercise the installed server from the host; the runtime needs no test tools."""

import argparse
import json
import os
import signal
import socket
import sqlite3
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


def run(*args, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True)


def fixture(root):
    (root / ".md-utils/server").mkdir(parents=True)
    (root / "books").mkdir()
    (root / ".md-utils/md-utils.json").write_text(json.dumps({
        "configVersion": "0.2.0", "schemaDirectory": ".md-utils/schemas/",
        "rules": [{"name": "books", "match": {"paths": ["books/**"]},
                   "checks": [{"type": "requiredHeading", "heading": "Book"}]}],
    }))
    (root / ".md-utils/server/server.yaml").write_text('''serverConfigVersion: "3"
persistentIdentity: {path: [uuid]}
resources:
  - name: books
    route: /books
    operations: [list, get]
    selection: {mode: rule, rule: books}
    identityPolicy: {source: frontmatter, path: [slug], format: string}
    writable:
      codec: {frontmatterFields: [title], bodyWritable: true}
      creation: {template: "{{ 'Book' | h1 }}\\n{{ data.text | bold }}"}
    mutations:
      operations: [create]
      creation:
        directory: books/
        filenameField: title
        identifiers: [slug]
''')
    (root / "books/seed.md").write_text("---\nslug: seed\ntitle: Seed\n---\n# Book\nInstalled archive\n")


def exercise(base, root):
    def request(path, payload=None, key=None):
        headers = {"Content-Type": "application/json"}
        if key:
            headers["Idempotency-Key"] = key
        data = json.dumps(payload).encode() if payload is not None else None
        with urllib.request.urlopen(urllib.request.Request(base + path, data=data, headers=headers), timeout=5) as response:
            return response.status, response.headers, json.load(response)

    deadline = time.monotonic() + 45
    while True:
        try:
            _, _, page = request("/books")
            break
        except (OSError, urllib.error.URLError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.2)
    assert len(page["records"]) == 1, page
    assert page["generation"]
    _, headers, record = request("/books/seed")
    assert headers["MD-Utils-Revision"].startswith("r1.")
    assert record["frontmatter"]["title"] == "Seed", record
    assert "Installed archive" in record["body"], record
    _, _, contract = request("/openapi.json")
    assert contract["openapi"].startswith("3.1.")
    assert "get" in contract["paths"]["/books"]
    assert "post" in contract["paths"]["/books"]
    payload = {"frontmatter": {"title": "Created"}, "identifiers": {"slug": "created"},
               "data": {"text": "Knap from installed resources"}}
    status, _, receipt = request("/books", payload, "archive-create")
    assert status == 201, (status, receipt)
    assert receipt["state"] == "completed", receipt
    _, _, created = request("/books/created")
    assert "# Book" in created["body"]
    assert "**Knap from installed resources**" in created["body"]
    assert (root / "books/Created.md").is_file()
    _, _, replay = request("/books", payload, "archive-create")
    assert replay["id"] == receipt["id"]
    _, _, filtered = request('/books?filter=%7B%22title%22%3A%22Created%22%7D')
    assert len(filtered["records"]) == 1, filtered
    database = root / ".md-utils/index.sqlite"
    assert database.read_bytes()[:16] == b"SQLite format 3\x00"
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
        assert connection.execute("SELECT count(*) FROM current_documents").fetchone()[0] == 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--image")
    mode.add_argument("--executable", type=Path, help="Native host verification without Docker")
    parser.add_argument("--version", required=True)
    options = parser.parse_args()
    Path("tmp").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="server-archive-", dir="tmp") as temporary:
        root = Path(temporary).resolve()
        fixture(root)
        container = None
        process = None
        with (root / "server.log").open("w+") as log:
            try:
                if options.image:
                    # A real bind mount contains the collection and all writable state.
                    container = run("docker", "run", "--detach", "--user", f"{os.getuid()}:{os.getgid()}", "--publish", "127.0.0.1::8080",
                                    "--mount", f"type=bind,src={root},dst=/collection", options.image).stdout.strip()
                    address = run("docker", "port", container, "8080/tcp").stdout.strip()
                    executable = "/opt/md-utils-server/md-utils-server"
                    assert run("docker", "exec", container, executable, "--version").stdout.strip() == options.version
                    schema = run("docker", "exec", container, executable, "schema", "--schema-version", "3").stdout
                else:
                    executable = str(options.executable.resolve())
                    assert run(executable, "--version").stdout.strip() == options.version
                    schema = run(executable, "schema", "--schema-version", "3").stdout
                    with socket.socket() as listener:
                        listener.bind(("127.0.0.1", 0))
                        port = listener.getsockname()[1]
                    address = f"127.0.0.1:{port}"
                    process = subprocess.Popen([executable, "serve", "--project-root", str(root) + "/",
                                                "--config", ".md-utils/server/server.yaml",
                                                "--hostname", "127.0.0.1", "--port", str(port)], stdout=log, stderr=log)
                assert "properties" in json.loads(schema)
                exercise("http://" + address, root)
                if container:
                    run("docker", "stop", "--time", "15", container)
                    state = json.loads(run("docker", "inspect", container).stdout)[0]["State"]
                    assert state["ExitCode"] == 0 and not state["OOMKilled"], state
                    # New processes in an image without build-tree fallbacks must fail
                    # when their required resource bundles are hidden.
                    result = run("docker", "run", "--rm", "--entrypoint", "/bin/sh", options.image,
                                 "-c", "mv /opt/md-utils-server/md-utils_MarkdownUtilitiesServer.resources /hidden; "
                                 f"{executable} schema --schema-version 3", check=False)
                    assert result.returncode != 0, "Schema loaded without its resource bundle"
                else:
                    process.send_signal(signal.SIGTERM)
                    assert process.wait(timeout=15) == 0
                print("Server archive: version, schemas, readiness, reads, OpenAPI, SQLite, Knap creation, replay, and SIGTERM passed")
            finally:
                if container:
                    logs = run("docker", "logs", container, check=False)
                    print(logs.stdout + logs.stderr)
                    run("docker", "rm", "--force", container, check=False)
                if process and process.poll() is None:
                    process.kill()
                    process.wait()
                log.seek(0)
                print(log.read())


if __name__ == "__main__":
    main()
