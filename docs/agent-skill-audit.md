# Agent skill audit (#198)

The canonical skill is `skill/markdown-utilities/skills/markdown-utilities/`.
Its entrypoint introduces the model and routes tasks; references contain syntax,
examples, persistence behavior, version boundaries, and recovery guidance. The CLI
copy is generated in `Sources/md-utils/Resources/AgentSkill/`.

## Coverage matrix

Every top-level command has an installed reference. `check-agent-skill.py --cli`
recursively visits executable help, checks top-level matrix coverage, and saves
the help inventory to `tmp/agent-skill-help.json`. Help discovery verifies command
availability, not every option combination. Reference names below are relative to
the canonical skill's `references/` directory.

| Commands | Task / reference | Verification |
| --- | --- | --- |
| `survey`, `explore`, `fm`, `types`, `rules`, `rel`, `links` | Scenario-based investigations; discovery-workflows.md | Executed command chains, output handoffs, focused section disclosure, unchanged source bytes |
| `agents` | Complete export/installation; installation.md | Full-tree byte comparison, stdout compatibility, no overwrite |
| `survey` | Folder overview and focused investigations; survey.md | Red-green suites, JSON workflows and recursive help inventory |
| `query` | Typed document filtering, JSONPath, calendar comparisons and snapshots; query.md | Red-green Core/CLI suites, source-independent projected snapshots and executable examples |
| `frontmatter`, `fm` | Metadata, arrays, mapped files, JMESPath; frontmatter.md, batch.md | Two-file author edits/readback, empty arrays, YAML selection |
| `explore` | Progressive document inspection; headings-sections.md | Tree output and help |
| `table-of-contents`, `toc` | Outlines/links; headings-sections.md | Heading output and help |
| `headings` | Promote/demote; headings-sections.md | Help; dedicated command tests |
| `section` | Get/replace/reorder; headings-sections.md | Preview preserves bytes, explicit write changes body |
| `extract` | Extract section; headings-sections.md | Help; dedicated command tests |
| `lines` | Bounded line ranges; headings-sections.md | Help; dedicated command tests |
| `body` | Content without metadata; headings-sections.md | Help; dedicated command tests |
| `convert` | Text/CSV; headings-sections.md | Both conversion examples |
| `links` | Resolve/check/backlink/convert; links.md | Check/backlinks, conversion preview/application |
| `relationships` | Query claims with scoped evidence; relationships.md | Named outgoing query with root and target contract |
| `rules` | Author/select/enforce/repair/migrate; rules.md | Extracted rule example, valid/invalid member, policy compilation |
| `types` | Structural contracts, hints, creation; types.md | Complete type, shared schema, semantic and relationship assessment |
| `config` | Initialize/inspect/migrate; other-commands.md, rules.md | Legacy init, migration preview preserves config |
| `template` | Knap rendering; templates.md, types.md | Named object input renders heading |
| `index` | Refresh/query/FTS/watch/provenance; indexing.md | Refresh, SQL query, status, recursive help |
| `index draft`, `index apply` | Durable intent/recovery; mutations.md | CLI stage/preview/apply/discard and missing-input tests |
| `copy`, `move` | Revision-bound transfers; mutations.md | Transfer integration tests including replay |
| `meta` | Filesystem attributes; other-commands.md | Native read and help |
| `format` | Bullets/emphasis/tables; other-commands.md | Preview and help |
| `slug` | Candidate generation; other-commands.md | Default candidate and help |
| `okf` | Experimental bundle workflows; other-commands.md | Scaffold/report and recursive help |
| Schemas (no authoring command) | JSON Schema resources/profile; schemas.md | Object schema, nullable strings, wikilink pass/fail |
| Standards (upcoming) | Notice only; standards.md | Linked to #191; no proposed authoring syntax |

## Findings and resolutions

Query discovery follow-up (2026-10-28): the entrypoint now introduces
survey → query → explore. `references/query.md` explains path ordering versus
date ranking, and `references/discovery-workflows.md` adds native value/type/rule
selection and a seventh investigation for the latest five sermon notes. The
workflow checks array tags, mixed date kinds, untagged candidates, completeness,
and unlimited candidate retrieval before ranking. Executable fixtures deliberately
reverse filename/date order and compare ranked candidates with a date-window
query. Canonical and bundled references are synchronized; verification uses
`scripts/check-agent-skill.py` and `scripts/verify-agent-skill-examples.py` with
the rebuilt executable. Real-collection investigation used read-only `--no-index`
commands; no source notes or installed skill directories were changed.

Discovery workflow reference integration (2026-10-27): `SKILL.md` routes
step-by-step unfamiliar-collection investigations to `discovery-workflows.md`.
The reference covers six scenarios and links to focused command documentation.
Its 19 primary examples and 11 conditional follow-ups run in an isolated fixture;
checks verify output-derived names/paths, targeted section disclosure, expected
finding statuses, and unchanged source/contract bytes. All 18 canonical/bundled
files, routing/links, the 137-page executable help audit, installed export/example
workflows, and the complete native suite (**1,947 tests**) passed. The generic
skill-creator validator could not import optional PyYAML; the existing CLI YAML
parser plus equivalent metadata/naming/scaffold checks passed without installing
dependencies. Local evidence: `tmp/discovery-skill-full-tests.log`,
`tmp/discovery-skill-check.log`, and `tmp/discovery-skill-examples.log`.

- Query/index/mutation/template/batch details now have focused references, and
  formatting, metadata, slugs, config, OKF, and installation have explicit routing.
- CLI-only installation previously produced dangling links. The complete folder
  is now bundled and exported offline via `agents skill --output-directory`.
  Stdout remains entrypoint-only for compatibility; instructions explain both modes.
- Tests now compare canonical, generated, built, and exported inventories/bytes,
  and verify preservation of customized existing installations.
- Contributor procedures now require focused references and full synchronization
  after reference-only edits. CI runs on all pull requests, including shared-library
  changes that affect CLI behavior.
- Removed unsupported comparative advice about another CLI. Clarified that managed
  copy allocates UUIDs only with a configured persistent identity path.
- A mixed-feature workflow exposed general draft validation failing with an
  unrelated optional named-relationship type loaded. Reproduced with one self-bound
  Person definition, recorded in the executable examples, documented in mutations.md,
  and deferred as a runtime fix to [#199](https://github.com/DandyLyons/md-utils/issues/199).
  The audit does not bypass contracts to make this workflow pass.

## Repeatable verification

```sh
# Synchronize, build, then check routing, packaging, and documented workflows.
python3 scripts/sync-agent-skill.py
python3 scripts/check-agent-skill.py
swift test --filter 'AgentCommandsTests|IndexApplyCommandsTests|TransferCommandsTests'
python3 scripts/check-agent-skill.py --cli .build/debug/md-utils
python3 scripts/verify-agent-skill-examples.py --cli .build/debug/md-utils
```

Example fixtures use isolated project `tmp/` directories and are cleaned after
execution. Scripts require only Python's standard library and the built CLI.
They parse skill YAML via md-utils, check JSON examples and local file links, and
exercise authoring/inspection/batch/query/preview workflows. Swift integration
tests cover durable apply and transfers. The `--cli` option accepts an installed
binary; the export destination does not depend on a repository checkout.
The script also relocates the executable and its resource bundles, marking only
the copied bundle to prove export reads installed resources rather than an absolute
build-tree fallback. It verifies stale-source refusal and renewed draft application.

## Distribution and explicit limits

Direct installation copies the whole canonical folder. SwiftPM `.copy` preserves
the generated folder hierarchy. Native release packaging already copies resource
bundles recursively; installed Linux smoke now exports references and rejects an
existing destination. The resource bundle must accompany the executable, as in
the existing native distribution contract. Knowledge systems need the entrypoint
plus reference uploads; where relative links are unsupported, load by filename.

Local verification is native macOS. Linux runtime/release checks remain CI-only;
WASM remains deferred under project policy and this CLI is not a WASM target.
Third-party installer services are not executed/certified here; offline export and
direct folder copying are the supported alternatives. Hosted publication and
interactive terminal authoring are not claimed by these smoke checks. Dedicated
interactive-authoring, recovery, and codec suites retain those implementation
checks. Exhaustive option combinations, OKF domain modeling, and the unfinished
standards specification are explicit exclusions, not invented guidance.

Native audit results: 123 command help pages inventoried; 16 routed Markdown files;
complete export and refusal checks passed. Focused runs passed 7 agent/apply/transfer
tests, 15 agent/interactive-authoring tests, and 17 durable-draft tests (agent tests
overlap between runs). End-to-end documented workflows passed, with #199 retained
as an expected unavailable result. Linux smoke changes await CI execution.

For future command groups, extend the matrix and installed routing. For changed
semantics, update the focused reference and a representative executable case when
useful. Automated synchronization cannot establish prose accuracy; review actual
help, implementation, and outcomes following AGENTS.md.
