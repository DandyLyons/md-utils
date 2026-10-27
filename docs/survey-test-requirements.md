# Survey behavioral test requirements

These requirements precede implementation. A checked item requires a passing
behavioral test, not merely an implementation branch. Red-green evidence and any
remaining work belong in the progress section.

## Portable observations and statistics

- [x] YAML/TOML and supported non-Markdown extraction retain absent, empty,
  malformed, unsupported and parsed states without treating hint diagnostics as
  malformed YAML. LF/CRLF behavior follows the existing parser.
- [x] Literal dotted/slashed keys, nested objects and arrays have distinct paths;
  invalid JSON Pointers fail explicitly; absent indices/keys are missing.
- [x] Null, booleans, integers, non-integer numbers, strings, arrays, objects, and
  native temporal values stay distinct, including after serialization.
- [x] Key prevalence counts documents, ranks deterministically, and shows exact
  denominators, exclusions and display truncation.
- [x] Whole-value distributions preserve typed equality, object-order equivalence,
  array ordering and array-element document/occurrence counting.
- [x] Outlier minimum sample/share boundaries are tested; missing/null are separate;
  no finding implies an authored requirement.

## Scope and execution

- [x] CLI registration, default overview, all focused commands, metric replacement,
  unknown metrics, incompatible flags and numerical option boundaries are tested.
- [x] Recursive scope union/deduplication, exclusions, nonrecursive mode,
  Markdown-only mode, file-list-only input, LF/NUL lists and root confinement work.
- [ ] Hidden entries/symlinks are skipped visibly, including symlink ancestors;
  explicit missing/unreadable inputs are not silently omitted.
- [ ] Large input and computation budgets produce incomplete results, never
  silent sampling or unbounded allocation.
- [x] Finding malformed files succeeds; unreadable files/missing snapshot evidence
  fail with partial results; invalid usage fails separately; cancellation propagates.

## Contracts and relationships

- [ ] Rule applicability remains distinct from conformance; uncovered/overlaps
  retain unknown selection and no-config versus invalid-config distinctions.
- [ ] Type inventory distinguishes discovered and referenced types, includes the
  type-matches hint, and never performs implicit all-type assessment.
- [ ] Optional type matching retains pass/fail/unavailable and recursive evidence.
- [ ] Relationship summaries reuse named/ordinary/outgoing semantics, preserve
  self-links and selected-folder boundary information, and expose coverage limits.
- [x] Standards explicitly report unsupported, without pretending no standards exist.

## Index and output

- [ ] Direct/cached results are equivalent; changed/deleted/new files refresh;
  definition changes invalidate; stat-preserving edits honor hash verification.
- [ ] No absent index is created; failed cache warns/falls back; cancellation does
  not fall back; missing required scopes are refreshed without unrelated scans.
- [ ] Snapshot-only access is read-only, with no source/config/stat/discovery calls,
  including after source deletion; identity/generation and evidence gaps are shown.
- [ ] Publication is atomic and generation-bound; failures cannot expose mixed or
  stale evidence as current. Raw values/kinds and presence survive cache roundtrip.
- [ ] JSON is a single versioned document with metric completion, provenance,
  totals/truncation and executable hints; diagnostics stay on stderr.
- [ ] Text and JSON agree on findings; hints retain quoting, configuration and
  scope, warn about broader validation, and do not propose nonexistent commands.
- [x] Canonical/bundled Agent Skill workflow examples and actual executable help
  match implementation; Linux remains CI-only and WASM verification deferred.

## Progress

Requirements were recorded before production code. Functional standards support
is separately tracked in [#202](https://github.com/DandyLyons/md-utils/issues/202).
The broad checklist remains open until each entire requirement has dedicated
coverage; related passing tests are not presented as proof of every boundary.

### Completed red-green cycles (2026-10-26)

- Portable observations/statistics: missing APIs produced the initial red build;
  nine tests became green. Additional red tests exposed swallowed cancellation and
  insufficient temporal-kind distinctions. All eleven portable tests now pass.
- CLI/scope: missing runner tests were initially red. Subsequent red tests drove
  directory cache refresh/snapshot reads, binary coverage parity, rejection of
  unrelated options, and bounded relationship summaries. Tests also verify
  malformed findings succeed, missing snapshot evidence is unavailable, and rule
  selection does not require type conformance.
- Executable verification exposed subcommand names being consumed as paths.
  Strengthened tests asserted the selected command rather than just successful
  parsing, reproduced the defect, and passed after restoring default dispatch.
- Partial-read tests first failed for unreadable siblings and missing explicit
  configuration; both are now green. LF/NUL lists, exclusions and root confinement
  have focused coverage.

- Additional cache tests exercise stat-preserving edits with explicit hash
  verification, cancelled publication retaining old extraction, permission-denied
  files, and input-budget exhaustion. Tests also drove scoped hints and complete
  JSON request context. A named-relationship fixture exposed concatenated-name
  collisions; grouping now preserves separate type/relation identities.

The combined native run passed 151 tests across ten suites:

```bash
swift test --disable-automatic-resolution --filter 'MarkdownSurveyTests|SurveyCommandsTests|CLIEntryTests|IndexCommandsTests|RulesIndexedValidationTests|MarkdownSemanticScalarTests|ResourceCodecTests|AgentCommandsTests|MarkdownRelationshipTests|CollectionRelationshipQueryTests'
```

Red/green logs remain in project `tmp/` (not committed), including
`survey-core-red.log`, `survey-cache-red.log`, `survey-boundaries-red.log`,
`survey-temporal-red.log`, `survey-routing-red.log`, `survey-partial-red.log`, and
`survey-final-tests.log`. Installed-skill workflows verify JSON statistics,
malformed findings, the standards placeholder, index publication and snapshot
reads after deleting sources, plus bundle export/relocation. The help audit reads
137 pages. `md-utils help survey` resolves group help; `survey --help` describes
the default overview and points to focused commands.

### Current limits and remaining verification

Value-investigation iteration: ordinary directory scalar-value rows offer one
frontmatter dump/filter example with typed jq arguments, preferring the most
frequent displayed non-null value. The owner chose jq over fm search syntax.
JSON hints expose an
optional `pipeTo` argument array; shell output escapes both stages. Null predicates
require key presence. Restricted scopes do not get misleading broader pipelines.
Focused hint and renderer regressions were run; the owner's `Status = ✅ Read`
query returned 150 frontmatter objects. The full suite remains deferred during
iteration.

Human-output iteration: the `values` renderer now shows counts, percentages,
typed values, denominators, and truncation. The JSON fallback was also present in
malformed-fm, rules, types, uncovered, overlaps, type-matches, and relationships;
these now render nested findings with totals and omissions. The structured JSON
contract is unchanged. Hints quote only shell-unsafe arguments. Cache fallback is
a stderr performance advisory rather than a warning.

Focused rendering/quoting, non-text, and investigation-hint tests pass. The two
requested `Status` commands complete successfully against the owner's collection.
All thirteen subcommands were exercised in an isolated fixture, including real
malformed frontmatter and contracts; 28 printed examples also passed. No full
suite was run for this iteration. Evidence: `tmp/survey-render-green.log` and
`tmp/survey-human-metrics.txt`.

Iteration after initial commit: a focused regression creates an 81 MiB PDF,
two other non-text attachments, and a later Markdown document. Text and JSON
commands must succeed, count three skipped non-text files, and include the later
document. Existing text-budget exhaustion remains incomplete. Classification
parity also covers a PDF whose bytes happen to be valid UTF-8. Native cache
fingerprint v4 invalidates older classification evidence. Only focused tests
were run for this iteration at the owner's request.

The owner's Inputs collection now completes in both modes: 522 text files,
four non-text files skipped, no unreadable files. The previous scan stopped at
an 81 MiB PDF after counting three skips. Its existing cache cannot supply all
attachment observations and falls back to direct reads; snapshot-only behavior
is unchanged. JSON adds `coverage.skippedNonText`, retaining `skippedBinary`
as a schema-v1 compatibility alias. Human key output reports counts and kinds
instead of an internal JSON dump, without suggesting value distributions when
the property is absent.

Pre-commit verification on 2026-10-27: the complete native `swift test
--disable-automatic-resolution` run passed **1,922 tests across 183 suites** in
eight test products. The 137-page executable help audit and all 17 canonical/
bundled skill file checks also passed. Full-suite output is retained locally in
`tmp/survey-precommit-tests.log`.

Follow-up full CLI target verification reproduced two issues in the existing
`CLIHelpTests` inventory test: the 14 new survey help pages were absent from
`docs/cli-help-audit.md`. Updating that inventory resolved both issues without
changing test assertions. `swift test --disable-automatic-resolution --filter
md_utilsTests` then passed **720 tests in 61 suites**. Red/green logs are
`tmp/survey-target-recheck.log` and `tmp/survey-target-recheck-green.log`.

- Contract inventory/rule coverage/type matching lack dedicated survey snapshot
  projections: index-only explicitly reports unavailable, never reads sources.
- Recursive directory surveys reuse the index. Explicit-file and nonrecursive
  surveys read directly. Contract metrics consume source records after any refresh
  and do not claim a snapshot ID for those records.
- Relationship summaries use the Markdown engine; non-Markdown relationship
  assessment is explicitly excluded. Custom-config relationship queries report
  unavailable rather than silently using another configuration.
- Invalid usage follows existing ArgumentParser exit 64, replacing proposed exit 2.
  Linux is CI-only and WASM verification is deferred by project policy.
- Large-population performance and multi-process stress benchmarks have not been
  run. Controlled budget/interruption tests and existing index regressions are not
  presented as production-scale benchmark evidence. Unchecked broad requirements
  remain tracked in #200 rather than being marked complete without full coverage.
