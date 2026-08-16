# Reading and Mutating Frontmatter

Read, write, and convert YAML or TOML frontmatter while preserving the Markdown body.

## Overview

Frontmatter support starts with `FrontMatterParser`, which detects YAML delimited by `---` or TOML delimited by `+++` and separates it from the body text. `MarkdownDocument` parses either format into the ordered, format-neutral ``FrontMatter`` model and records the source ``FrontMatterFormat``.

Non-Markdown text uses ``WrappedFrontMatterParser`` with a ``FrontMatterSyntax``.
The parser scans LF text for complete host wrappers containing complete YAML or TOML
blocks. It returns the first block's raw frontmatter, format, and snapshot-relative source range,
plus the 1-based opening lines of later complete blocks. Incomplete candidates are
treated as absent. The parser does not model the host content as Markdown and does
not normalize indentation.

Mutation helpers on `MarkdownDocument` update frontmatter values without changing the body or delimiter format. ``FrontMatterConversion`` parses and serializes the neutral value model; `YAMLConversion` remains available for YAML-specific interoperability.

Comments are not part of the neutral value model. Parsing and rendering either YAML or TOML does not guarantee that frontmatter comments survive, so callers should avoid comments in frontmatter that will be mutated.

## Missing and Null Values

A missing key and a key with a YAML null value are distinct states. TOML has no null value and serialization reports the exact unsupported key path. Callers that render frontmatter for user-facing output should preserve the distinction when it matters to downstream tools.

## Errors

Invalid YAML, invalid TOML, and values unsupported by the selected format are reported as thrown errors rather than fatal failures.
