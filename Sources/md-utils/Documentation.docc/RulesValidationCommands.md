# Rules Validation Commands

Validate Markdown files against project-level rules.

## Overview

The `rules` command group manages `.md-utils/` project configuration and validates Markdown files. Configuration is read from the current working directory; `md-utils` does not search parent directories for a project root.

Use `md-utils config init` to create the project configuration along with empty `.md-utils/schemas/` and `.md-utils/types/` directories. Initialization does not add a rule or type.

Rules match Markdown files by project-relative glob patterns, optional file metadata conditions, optional frontmatter conditions, optional whole-frontmatter queries, and optional document conditions. Files can match more than one rule, in which case every matching check applies.

Version `0.2.0` configs use a `rules` array. Version `0.1.0` configs using `schemaRules` still load as legacy configs.

```bash
md-utils config init
md-utils rules add books --path "Books/**/*.md" --tag Book
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

Field predicates under `rules[].match.frontmatter` are all-of predicates for one frontmatter key. Multiple operators on one key are implicit AND.

Supported operators are `equals`, `doesntEqual`, `includes`, `notIncludes`, `hasKey`, `doesntHaveKey`, `regex`, `startsWith`, `endsWith`, `contains`, `empty`, `emptyString`, `emptyArray`, `emptyObject`, `notEmpty`, `in`, `notIn`, `greaterThan`, `greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`, `after`, `onOrAfter`, `before`, `onOrBefore`, inclusive `between`, and `typeIs`.

Missing keys are distinct from value inequality. A missing key does not match `doesntEqual`, `notIncludes`, or `notIn`. Only `doesntHaveKey` intentionally matches a missing key.

`contains` is string containment. `includes` is array membership.

Date/time predicates support date-only `YYYY-MM-DD` operands and RFC 3339 date-time operands with `Z` or numeric offsets, such as `2020-01-01T12:00:00Z` and `2020-01-01T07:00:00-05:00`. Date-only operands compare at date precision. Date-time operands compare at date-time precision. A value with more precision can match a less precise rule; a value with less precision does not match a more precise rule.

Whole-frontmatter predicates live under `rules[].match.frontmatterQuery`. Version `0.2.0` supports `jmespath`, evaluated with the same truthiness behavior as `md-utils fm search`.

Logical grouping predicates `all`, `any`, and `not` are deferred to config schema `0.3.0`.

## Document Predicates

Supported document matcher operators are `hasHeading`, `headingRegex`, `hasHeadingAtLevel`, `hasSection`, `bodyContains`, `bodyRegex`, `hasWikilink`, `lineCount`, and `wordCount`.

`hasBrokenWikilink` is deferred until resolver context and performance behavior are designed.

## File Predicates

Supported file metadata matcher operators are `pathRegex`, `filenameEquals`, `extensionIn`, `modifiedAfter`, and `modifiedBefore`. File predicates are evaluated before file contents are parsed.

`pathRegex`, `headingRegex`, `bodyRegex`, and frontmatter `regex` use Swift `NSRegularExpression` syntax.

## Failure Behavior

Invalid YAML frontmatter is reported as an error for matched rules because frontmatter predicates and schema checks cannot proceed. Files without required frontmatter fail when the matched `frontmatterSchema` check requires frontmatter, and are skipped for optional frontmatter schema checks.
