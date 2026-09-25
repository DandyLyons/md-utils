# Changelog

## Unreleased

- **Breaking:** Knap (through SwiftKnap) replaces the previous template engine for
  library, CLI, and server creation. Rewrite existing templates using Knap; there
  is no compatibility mode or automatic translation. `template render` retains
  its JSON `data`/`frontmatter` envelope and document validation.
- Knap Markdown filters, structured diagnostics, nonfatal warnings, and execution
  limits are available. Integers outside ±9,007,199,254,740,991 must be strings.
- Swift 6.3 is now required. Linux template consumers require SwiftKnap's documented
  native build/runtime packages and resource bundles; see `docs/template-rendering.md`.
