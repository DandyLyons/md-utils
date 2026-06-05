# Reading and Mutating Frontmatter

Read, write, and convert YAML frontmatter while preserving the Markdown body.

## Overview

Frontmatter support starts with `FrontMatterParser`, which detects YAML delimited by `---` markers and separates it from the body text. `MarkdownDocument` then parses that YAML into a Yams mapping for structured access.

Mutation helpers on `MarkdownDocument` update frontmatter values without changing the body. Conversion helpers in `YAMLConversion` translate YAML nodes and mappings to Swift values, JSON, Property List, and YAML output.

## Missing and Null Values

A missing key and a key with a YAML null value are distinct states. Callers that render frontmatter for user-facing output should preserve that distinction when it matters to downstream tools.

## Errors

Invalid YAML and mappings with unsupported keys are reported as thrown errors rather than fatal failures.
