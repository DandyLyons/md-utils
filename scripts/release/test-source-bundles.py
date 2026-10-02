#!/usr/bin/env python3
"""Regression: nested submodule sources survive loss of upstream repositories."""
import os
import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
packager = runpy.run_path(str(ROOT / "scripts/release/package-linux.py"))


def git(directory, *args, env=None):
    return subprocess.check_output(["git", *args], cwd=directory, env=env, text=True).strip()


class SourceBundleTests(unittest.TestCase):
    def test_recursive_submodules_rebuild_without_original_repositories(self):
        (ROOT / "tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="source-bundle-test-", dir=ROOT / "tmp") as temporary:
            root = Path(temporary)
            environment = os.environ.copy()
            environment["GIT_ALLOW_PROTOCOL"] = "file"
            environment["GIT_CONFIG_GLOBAL"] = str(root / "gitconfig")
            environment["GIT_CONFIG_NOSYSTEM"] = "1"
            (root / "gitconfig").write_text("")
            for name in ("leaf", "child", "parent"):
                repository = root / name
                repository.mkdir()
                git(repository, "init", "--initial-branch=main", env=environment)
                git(repository, "config", "user.name", "Packaging test", env=environment)
                git(repository, "config", "user.email", "packaging@example.invalid", env=environment)
                (repository / "source.txt").write_text(name + "\n")
                git(repository, "add", ".", env=environment)
                git(repository, "commit", "-m", "Fixture source", env=environment)
                git(root, "config", "--file", str(root / "gitconfig"),
                    f"url.{repository.as_uri()}.insteadOf", f"https://example.invalid/{name}.git", env=environment)
            for parent, child in (("child", "leaf"), ("parent", "child")):
                git(root / parent, "submodule", "add", f"https://example.invalid/{child}.git", "nested", env=environment)
                git(root / parent, "commit", "-am", "Add nested source", env=environment)
            git(root / "parent", "submodule", "update", "--init", "--recursive", env=environment)
            bundles = root / "bundles"
            bundles.mkdir()
            entries = []
            packager["bundle_submodules"](root / "parent", bundles, entries)
            self.assertEqual(len(entries), 2)
            repeated_entries = []
            packager["bundle_submodules"](root / "parent", bundles, repeated_entries)
            self.assertEqual(repeated_entries, entries)
            git(root / "parent", "bundle", "create", str(bundles / "parent.bundle"), "--all", env=environment)
            (root / "gitconfig").write_text("")
            for entry in entries:
                mirror = root / (entry["identity"] + ".git")
                git(root, "clone", "--bare", str(bundles / (entry["identity"] + ".bundle")), str(mirror), env=environment)
                git(root, "config", "--file", str(root / "gitconfig"),
                    f"url.{mirror.as_uri()}.insteadOf", entry["url"], env=environment)
            for name in ("leaf", "child", "parent"):
                (root / name).rename(root / (name + "-unavailable"))
            git(root, "clone", "--recurse-submodules", str(bundles / "parent.bundle"), "restored", env=environment)
            self.assertEqual((root / "restored/nested/nested/source.txt").read_text(), "leaf\n")


if __name__ == "__main__":
    unittest.main()
