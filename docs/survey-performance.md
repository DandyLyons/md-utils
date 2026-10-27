# Survey analysis reuse

## Measured bottleneck

The survey contract adapter previously analyzed every selected record separately
for every rule. On the Notes Inputs collection (522 text files, 42 rules), that
meant 21,924 contract analyses, in addition to the metadata observation pass.
Type inventory paid this cost to identify definitions referenced by applicable
or uncertain rules.

The adapter now plans the union of compiled rule analysis requirements once,
analyzes each file once, and reuses that result for all rules. A record's analysis
is released before advancing to the next file; no collection-wide AST cache or
new persistent cache is introduced. Selection still uses the existing checker.
Rule ordering, uncertainty ordering, counts, type relevance, and hints are retained.
Cancellation is checked before/after analysis and between rule assessments.

## Inputs benchmark, 2026-10-27

Debug executable, serial commands, `--no-index --json --no-progress`, macOS.
These are local elapsed-time observations, not release-build or cold-disk claims.

| Command | Before | After, run 1 | After, run 2 |
| --- | ---: | ---: | ---: |
| types | 10.715 s | 1.851 s | 1.894 s |
| rules | 10.680 s | 1.690 s | 1.663 s |
| overview | 10.891 s | 1.822 s | 1.798 s |

Both after runs compared **complete parsed JSON and exit status** against the
baseline and matched exactly. macOS `sample` could not inspect the process in
this environment; the diagnosis instead uses code inspection, instrumented
analysis counts, and end-to-end timing. A second baseline overlapped compilation
and is retained in `tmp` but excluded from this table.

A full-root type survey subsequently returned `complete: true`, 26,241 text
files, 43 type definitions, and no limitations in 68.41 seconds. There is no
completed full-root baseline, so no full-root speedup is claimed. `/usr/bin/time`
printed elapsed/CPU times but failed its restricted kernel resource-stat query;
its wrapper exit status cannot establish the child exit status. The complete JSON
report is retained in `tmp/survey-types-full-root.json`.

Reproduce before/after measurements on the same unchanged collection:

```sh
python3 scripts/benchmark-survey.py /path/to/collection/folder \
  --project-root /path/to/collection --label before
# Build the changed debug executable, then:
python3 scripts/benchmark-survey.py /path/to/collection/folder \
  --project-root /path/to/collection --label after --compare before
```

Outputs and timings remain in ignored `tmp/survey-benchmark-<label>/` directories.
No source documents or collection index are changed. `--sample` optionally uses
the installed macOS sampling tool; sampling failure does not invalidate timings.

## Verification and limits

`SurveyCommandsTests.ruleSurveyAnalyzesEachRecordOnceWithoutChangingSelection`
enforces one analysis per record for rules and type inventory, compares selection
and uncertainty against independently analyzed per-rule inputs, and covers heading
requirements, malformed YAML, unsupported hosts, type relevance, and cancellation.
The repeated-analysis path fails the budget assertion; shared analysis passes it.

This does not eliminate the initial metadata observation parse, change the shared
index policy, optimize type-conformance matching, or skip rule applicability when
reporting type relevance. Those remain possible separately measured improvements.
