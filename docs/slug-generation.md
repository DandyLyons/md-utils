# Slug generation

`md-utils slug 'The Left Hand of Darkness'` prints `the-left-hand-of-darkness`
and a newline to stdout. It reads a required text argument, not a file or stdin.
Quote spaces; use `--` before text beginning with a hyphen. Errors go to stderr
with a nonzero exit status and no slug on stdout.

`--policy unicode` (default) lowercases Unicode letters and numbers.
`--policy strictASCII` lowercases ASCII letters; `--policy preserve` retains
ASCII case. All policies join alphanumeric runs with single hyphens: punctuation,
whitespace, and existing separators delimit runs. ASCII policies reject
non-ASCII letters/numbers rather than transliterating them. Empty or
punctuation-only sources fail; resource slugs never fall back to `section`.

Core's `MarkdownSlugGenerator.generate(from:policy:)` is pure and deterministic.
`resolve(provided:from:policy:)` validates and returns a supplied value unchanged,
and generates only for `nil`. An explicitly empty value is invalid.
`MarkdownSlugPolicy.isValid(_:)` shares the identity validator's existing rules.
For example, a supplied Unicode-policy `my_slug` retains its underscore even
though generation uses hyphens.

For #82 creation integration, the caller selects title or filename text, calls
`resolve`, and persists the result only after coordinated validation and any
configured uniqueness checks. Generation does not reserve a value or promise
uniqueness. Collision rejection or opt-in suffix allocation belongs to that
coordinator. No HTTP creation integration is enabled by #154.

Nothing renames files, changes frontmatter, or synchronizes slugs when titles
change. Filenames remain expressive. Slug lookup alone does not protect a field.
Existing heading anchors retain their historical formatting, `section` fallback,
and per-document numeric suffix behavior through the shared generator.
