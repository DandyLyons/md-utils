# YAML and TOML in `md-utils`

Understand where YAML, TOML and JSON are interchangeable and where their data models or CLI support differ.

## Overview

For most `md-utils` workflows, YAML and TOML are interchangeable. Both represent the JSON-like values used by frontmatter—objects, arrays, strings, numbers, and booleans—and `md-utils` converts both formats through the same format-neutral value model.

YAML frontmatter uses `---` delimiters, while TOML uses `+++`:

```markdown
---
title: Example
tags: [swift, markdown]
---
```

```markdown
+++
title = "Example"
tags = ["swift", "markdown"]
+++
```

Existing frontmatter keeps its format when mutated. Commands that create a block use YAML by default; pass `--frontmatter-format toml` to create TOML. An output option such as `--format toml` changes command output, not the stored frontmatter format.

## Data-model differences

| Edge case | YAML | TOML | `md-utils` behavior |
| --- | --- | --- | --- |
| Null | Has a null value | Has no null value | TOML serialization reports the unsupported key path. `fm touch`, which creates null values, cannot add a key to TOML frontmatter. |
| Document root | The language permits mappings, arrays, and scalars | A TOML document is a table | Frontmatter must be a top-level object in either format; non-object YAML frontmatter is rejected. For generic command output—not frontmatter—`--format toml` wraps an array or scalar root under a stable `value` key. |
| Mapping keys | Can use non-string keys (not supported by `md-utils`) | Keys are strings | The shared frontmatter model requires string keys. Unsupported YAML keys fail instead of being coerced. |
| Date and time | Usually interpreted as strings by `md-utils` | Has offset date-time, local date-time, local date, and local time values | TOML temporal values remain typed while processed as frontmatter. JSON and YAML output represent them as formatted strings. |
| Source syntax | Supports aliases, tags, block scalars, and flow styles | Supports dotted keys, inline tables, and arrays of tables | Mutations preserve values, the Markdown body, and the frontmatter format—not the original spelling, quoting, layout, or other format-specific syntax. |

JSON is a useful common denominator, but it is not identical to either format. In particular, JSON has neither comments nor TOML's native temporal types, and TOML cannot represent YAML or JSON null values.

## Comments

YAML and TOML both allow comments. JSON does not, and neither does the `md-utils fm` data model.

Once an `fm` command mutates frontmatter, however, `md-utils` parses and serializes the complete block. Comments—and syntax choices such as quoting or inline layout—are not guaranteed to survive. Avoid comments in frontmatter that will be managed with `md-utils fm`. Note: Read-only operations do not rewrite a file, and `fm dump --format raw` can return the original frontmatter text.

## CLI-specific differences

Most frontmatter CRUD, array, batch, rules, schema, and Markdown type workflows accept either format. The intentional exceptions are:

- `fm search` accepts YAML frontmatter only and does not support `--format toml`. `fm unique` supports both formats when a JMESPath-based uniqueness check is sufficient.
- Open Knowledge Format commands use YAML because the OKF v0.1 specification defines YAML frontmatter.
- Project configuration files do not currently support TOML. That is a planned feature. See https://github.com/DandyLyons/md-utils/issues/105

Use `fm dump --format raw` when the source representation matters. Use `--format json`, `--format yaml`, or `--format toml` when downstream tools need a particular serialization, and use `--frontmatter-format yaml|toml` only when creating or explicitly converting a stored frontmatter block.

See <doc:FrontmatterCommands> for command details.
