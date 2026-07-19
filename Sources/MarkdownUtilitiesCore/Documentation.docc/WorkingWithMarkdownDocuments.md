# Working with Markdown Documents

Create a `MarkdownDocument` when you need structured access to Markdown content whose YAML can be parsed.

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

## Documents and Records

A `MarkdownDocument` is a parsed interpretation of text. Its frontmatter, body, and AST all come from that text. It deliberately has no identity, path, revision, database table, or object-store key.

A `MarkdownRecord` is the canonical, addressable resource. It owns the original Markdown string plus optional identity, revision, and external `MarkdownRecordContext`. A record can therefore exist when its YAML is invalid and no `MarkdownDocument` can be initialized.

Use a record when assessing types or rules. Parse a document directly when the operation requires only successfully parsed content.
