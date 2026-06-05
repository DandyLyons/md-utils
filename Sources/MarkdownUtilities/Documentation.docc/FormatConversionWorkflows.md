# Converting Markdown to Other Formats

Convert Markdown documents to plain text or CSV from Swift code.

## Overview

Format conversion is built around small converter types and option structs. `MarkdownDocument` exposes convenience methods for supported conversions, while concrete converters handle format-specific rendering.

Plain text conversion extracts readable body text from MarkdownSyntax blocks and phrasing content. CSV conversion renders tabular Markdown content into comma-separated values with proper escaping.

## Choosing Options

Use conversion options to control spacing, indentation, code block preservation, and frontmatter inclusion where supported by the selected format.
