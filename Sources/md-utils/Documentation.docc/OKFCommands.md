# OKF Commands

Validate and update Open Knowledge Format bundles from the command line.

## Overview

The `okf` command group works with Open Knowledge Format (OKF) bundles. OKF support currently targets the OKF v0.1 draft, which is readable at [GoogleCloudPlatform/knowledge-catalog](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md).

An OKF bundle is a directory of Markdown files with YAML frontmatter. Non-reserved Markdown files are concept documents. Reserved files such as `index.md` and `log.md` have special meanings in the draft specification and are not treated as concept documents.

`md-utils` keeps OKF validation aligned with the v0.1 draft conformance rules. It reports hard conformance failures, but does not reject intentionally permitted content such as unknown `type` values, unknown frontmatter keys, broken links, missing optional fields, or missing `index.md` files.

## Validating a Bundle

Use `okf validate` with a bundle directory path:

```bash
md-utils okf validate ./knowledge/
```

The validator checks hard OKF v0.1 draft conformance requirements:

- Non-reserved Markdown files must contain parseable YAML frontmatter.
- Concept frontmatter must contain a non-empty string `type` field.
- Reserved files are handled separately from concept documents.
- `log.md` date headings must use ISO `YYYY-MM-DD` form when present.

Human-facing output uses color for status labels, paths, and metadata when supported by the terminal. The command exits with a non-zero status when hard validation errors are found.

## Setting Concept Types

Use `okf type set` to assign an explicit user-provided OKF `type` value to matching concept documents:

```bash
md-utils okf type set --type=Book
```

If `--dir` is omitted, the command scans the current directory recursively. To limit the operation to a directory, pass `--dir`:

```bash
md-utils okf type set --type=BigQueryTable --dir=./knowledge/tables/
```

The command skips reserved OKF files such as `index.md` and `log.md`.

## Filtering by Array Membership

Use `--array-key` and `--array-contains` together to update only concept files whose YAML frontmatter array contains a specific string. For example, this sets `type: Book` only on files whose `tags` array contains `Books`:

```bash
md-utils okf type set --type=Book --array-key=tags --array-contains=Books
```

Both filter options are required when either one is present. Files without matching frontmatter are left unchanged.

## Type Safety

`md-utils` never guesses OKF `type` values. The `okf type set` command writes only the explicit `--type` value supplied by the user. This matches the OKF v0.1 draft model, where type values are descriptive producer-defined strings rather than centrally registered values.

## Bundled Schema

The package includes `OKF-concept.schema.json` as a bundled resource. The schema requires a non-empty string `type` field and allows additional frontmatter keys, matching OKF v0.1 draft's permissive consumption model.

## Topics

### Related Commands

- <doc:FrontmatterCommands>
- <doc:SchemaValidationCommands>
