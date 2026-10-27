# Changelog

## Unreleased

- Folder surveys now provide compact colored summaries, key prevalence, per-file
  assessment reasons, focused investigation hints, and delayed progress feedback.
  Rule surveys share file analysis across rules, improving measured Inputs-folder
  performance about sixfold. Functional standards discovery remains upcoming.
- **Breaking:** Survey output selection is `--format text|json|json-pretty`;
  `--json` is removed. Malformed-frontmatter filtering uses `--fm-format yaml|toml`.
- Survey text-file budgets now handle skipped attachments and Markdown-only
  snapshot scope consistently. Recursive type matching uses revision-bound sources
  and rejects changed source bytes; unsupported snapshot configuration overrides
  report unavailable. Local type matching shares parsing across types, improving
  the measured three-type query about 1.9×. The verification matrix and extension
  proposals are documented separately.

- **Breaking:** Knap (through SwiftKnap) replaces the previous template engine for
  library, CLI, and server creation. Rewrite existing templates using Knap; there
  is no compatibility mode or automatic translation. `template render` retains
  its JSON `data`/`frontmatter` envelope and document validation.
- Knap Markdown filters, structured diagnostics, nonfatal warnings, and execution
  limits are available. Integers outside ±9,007,199,254,740,991 must be strings.
- Swift 6.3 is now required. Linux template consumers require SwiftKnap's documented
  native build/runtime packages and resource bundles; see `docs/template-rendering.md`.
