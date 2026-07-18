# Converting Markdown to Other Formats

Convert Markdown documents to plain text from Swift code.

## Overview

Format conversion is built around small converter types and option structs. `MarkdownDocument` exposes convenience methods for supported conversions, while concrete converters handle format-specific rendering.

Plain text conversion extracts readable body text from MarkdownSyntax blocks and phrasing content.

## Choosing Options

Use conversion options to control spacing, indentation, code block preservation, and frontmatter inclusion.
