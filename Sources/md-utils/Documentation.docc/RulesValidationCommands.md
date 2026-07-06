# Rules Validation Commands

Validate Markdown files against project-level rules.

## Overview

The `rules` command group manages `.md-utils/` project configuration and validates Markdown files. Configuration is read from the current working directory; `md-utils` does not search parent directories for a project root.

Rules match Markdown files by project-relative glob patterns and optional frontmatter conditions. Files can match more than one rule, in which case every matching check applies.

Version `0.2.0` configs use a `rules` array. Version `0.1.0` configs using `schemaRules` still load as legacy configs.

```bash
md-utils rules init books --path "Books/**/*.md" --tag Book
md-utils rules validate
md-utils rules validate books
md-utils rules list
md-utils rules describe books
```

## Supported Checks

- `frontmatterSchema`: validates parsed YAML frontmatter against a JSON Schema file.
- `requiredHeading`: requires an exact Markdown heading text in the document body.
- `maxBodyLines`: limits Markdown body line count.
- `maxBodyWords`: limits Markdown body word count.

## Frontmatter Predicates

Supported frontmatter matcher operators are `includes`, `notIncludes`, `equals`, `after`, and inclusive `between`. Date predicates support `YYYY-MM-DD` values.

## Failure Behavior

Invalid YAML frontmatter is reported as an error for matched rules because frontmatter predicates and schema checks cannot proceed. Files without required frontmatter fail when the matched `frontmatterSchema` check requires frontmatter, and are skipped for optional frontmatter schema checks.
