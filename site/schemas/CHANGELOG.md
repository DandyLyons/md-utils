# Config Schema Changelog

This changelog describes changes between versions of the md-utils project
configuration schema, from most recent to least recent. Versioned schema URLs
are immutable after publication.

## 0.2.1 — Pending publication

[View the 0.2.1 schema](./0.2.1/md-utils.schema.json)

Changes from 0.2.0:

- Adds the optional top-level `frontmatter` configuration introduced for
  delimiter-wrapped YAML metadata in non-Markdown files
  ([issue #98](https://github.com/DandyLyons/md-utils/issues/98)).
- Adds `frontmatter.useBuiltInPresets` for enabling or disabling the shipped
  extension-to-syntax mappings.
- Adds `frontmatter.syntaxes` for reusable project-defined opening and closing
  comment delimiters.
- Adds `frontmatter.extensionMappings` for mapping file extensions to built-in
  or project-defined syntax names.
- Leaves the `rules` model and its matching and checking semantics unchanged
  from 0.2.0.

## 0.2.0 — 2026-07-10

[View the 0.2.0 schema](./0.2.0/md-utils.schema.json)

Changes from 0.1.0:

- Replaces `schemaRules` with the more general `rules` array as part of the
  schema-to-rules command redesign
  ([issue #66](https://github.com/DandyLyons/md-utils/issues/66)).
- Replaces each rule's single schema fields with a `checks` array.
- Adds the `frontmatterSchema`, `requiredHeading`, `maxBodyLines`, and
  `maxBodyWords` check types.
- Expands rule applicability beyond paths and basic frontmatter matching to
  include excluded paths, file metadata predicates, whole-frontmatter JMESPath
  queries, and Markdown document predicates.
- Adds richer frontmatter operators, including presence, equality, collection,
  string, numeric, type, and precision-aware date/time comparisons.
- Keeps 0.1.0 available as a separately supported legacy schema; migration to
  0.2.0 rewrites legacy `schemaRules` into the generalized rule model.

Relevant implementation history:

- [Introduce schema 0.2.0](https://github.com/DandyLyons/md-utils/commit/2677e978f2172da4acd36b3269d0277a35841772)
- [Add document matchers](https://github.com/DandyLyons/md-utils/commit/897bd20)
- [Expand rule matchers and schema documentation](https://github.com/DandyLyons/md-utils/commit/66ee9e250875ad2bf63e04e93c7bf69c75a60e63)

## 0.1.0 — 2026-07-05

[View the 0.1.0 schema](./0.1.0/md-utils.schema.json)

- Establishes the first explicitly versioned md-utils project configuration
  schema.
- Defines project-level `schemaDirectory` and `schemaRules` fields.
- Supports path selection and basic frontmatter matchers for schema validation.
- Separates the config schema version from the md-utils CLI release version.
- Establishes bundled-schema validation and immutable, versioned website paths.

Relevant implementation history:

- [Add versioned config schema support](https://github.com/DandyLyons/md-utils/commit/a4a3ff260f7a9a350bfbc2313eac9c4de057569a)
- [Publish versioned config schemas](https://github.com/DandyLyons/md-utils/commit/e8e57fa10bba6c6f2b1c9e188e972de7106cd452)
