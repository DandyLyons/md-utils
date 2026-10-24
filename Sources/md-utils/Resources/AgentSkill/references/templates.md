# Knap templates

Use `md-utils template render --template ./templates/report.knap --data ./data/report.json --output ./reports/report.md`.
Default document mode accepts a JSON object of named variables and renders the
whole document. Use Knap `yaml`/`yaml_property` for YAML frontmatter; avoid templated
TOML without a serializer. Explicit `--mode body` accepts required `data` and optional
`frontmatter`, serializing the latter separately. Optional `--schema` inserts missing
defaults before validation. Supplied null/false/zero/empty strings are preserved.
Omit `--output` for stdout; warnings go to stderr.

Types and rules can declare creation templates. Read [Types](types.md)
for template metadata, input schemas, filenames, single/bulk creation, and failure
behavior. Creation can save a nonconforming starting document; validate separately
when conformance is required.
