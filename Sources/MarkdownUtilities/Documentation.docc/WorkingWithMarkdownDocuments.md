# Working with Markdown Documents

Create a `MarkdownDocument` when you need structured access to a Markdown file's YAML frontmatter and body content.

## Overview

`MarkdownDocument` accepts raw Markdown text and separates an optional YAML frontmatter block from the document body. Frontmatter is parsed into a Yams mapping so callers can inspect and mutate structured values, while the body remains available as plain text for extraction, formatting, and conversion workflows.

When callers need syntax-aware access to the body, `MarkdownDocument.parseAST()` parses the body with MarkdownSyntax and returns a fresh syntax tree for each call.

## Common Workflow

```swift
let document = try MarkdownDocument(content: markdown)
let body = document.body
let ast = try await document.parseAST()
```

Use this workflow before applying frontmatter, section, heading, table-of-contents, or format conversion operations.
