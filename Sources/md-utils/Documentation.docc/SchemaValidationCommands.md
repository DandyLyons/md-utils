# Schema Validation Commands

Validate Markdown frontmatter against project-level JSON Schema rules.

## Overview

The `schema` command group manages `.md-utils/` project configuration and validates Markdown frontmatter against JSON Schema files. Configuration is read from the current working directory; `md-utils` does not search parent directories for a project root.

Rules match Markdown files by project-relative glob patterns and optional frontmatter conditions. Files can match more than one rule, in which case every matching schema applies.

## Failure Behavior

Invalid YAML frontmatter is reported as an error because schema validation cannot proceed. Files without required frontmatter fail when the matched rule requires frontmatter, and are skipped when it does not.
