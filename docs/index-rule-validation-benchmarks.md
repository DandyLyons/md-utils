# Automatic indexed rule validation measurements

`scripts/benchmark-rule-validation.py` compares direct validation, first indexed
validation, unchanged indexed validation, and a small update. It uses real
standalone rules, JSON Schema checks for title/status, and a required Markdown
heading. Every indexed phase must match the direct `--include-ok` output, and
the script fails if validation warns that it fell back to source files.

```sh
swift build -c release --product md-utils
python3 scripts/benchmark-rule-validation.py --count 2000
```

Corpora and JSON results are stored under `tmp/rule-validation-benchmark/`.
Each run creates its own corpus and removes it on exit. `--binary`,
`--build-description`, `--count`, and `--repeat` select alternative measurements.
The script creates an empty index before the first indexed validation, so that
phase includes registration and population of the requested rule scope.

Measured on 2026-10-07 using the optimized CLI on macOS 27 ARM64, without
concurrent builds or tests. The corpus contains 2,000 Markdown files with about
800 bytes of body text each; the small update appends text to two files. Corpus
generation warms the filesystem cache. Direct and unchanged phases report the
median of three separate CLI processes; initial and small-update phases run once.

| Phase | Seconds |
| --- | ---: |
| Direct validation | 0.199 |
| Initial indexed validation | 1.178 |
| Unchanged indexed validation | 0.169 |
| Small-update indexed validation | 0.169 |

Unchanged validation was about 15% faster on this small, simple-check corpus.
Initial population was slower. A preceding debug-build measurement was slower
through the index than directly; SQLite and discovery overhead can outweigh saved
evaluation for inexpensive checks. These measurements are not a general speedup
guarantee or a large-collection scalability claim. Document size, rule complexity,
storage, build optimization, and the number of changed files affect the benefit.

Tests separately verify zero hashes/evaluations on ordinary unchanged refreshes,
reevaluation of changed files, and invalidation after definition changes. Use
`--no-index` to compare your collection directly, and `--verify-hashes` when
stat-preserving edits must be detected; hashing every file adds source-read cost.
