# Working with MarkdownDocument

Deep dive into the core MarkdownDocument type.

## Overview

``MarkdownDocument`` is the foundation of MarkdownUtilities. It represents a complete Markdown document with optional YAML frontmatter, providing a rich API for parsing, manipulation, and rendering.

## Document Structure

A ``MarkdownDocument`` consists of two main parts:

1. **Frontmatter**: Optional YAML metadata at the document's beginning
2. **Body**: The actual Markdown content

```markdown
---
title: My Document
date: 2024-01-24
---

# Heading

Content goes here.
```

## Creating Documents

### From String Content

The most common way to create a document:

```swift
let markdown = """
---
title: My Document
---

# Hello World
"""

let document = MarkdownDocument(content: markdown)
```

### From File

Read a Markdown file from disk:

```swift
import Foundation

let fileURL = URL(fileURLWithPath: "/path/to/document.md")
let content = try String(contentsOf: fileURL, encoding: .utf8)
let document = MarkdownDocument(content: content)
```

### Without Frontmatter

Documents don't require frontmatter:

```swift
let markdown = """
# Just Markdown

No frontmatter here.
"""

let document = MarkdownDocument(content: markdown)
// document.frontmatter will be empty but still accessible
```

## Accessing Content

### Getting the Full Document

Access the complete document as a string:

```swift
let document = MarkdownDocument(content: markdown)
let fullContent = document.content
```

### Getting the Body

Access just the Markdown content without frontmatter:

```swift
let document = MarkdownDocument(content: markdown)
let body = document.body

// body contains only the Markdown content:
// # Hello World
```

### Getting Frontmatter

Access the frontmatter directly:

```swift
let document = MarkdownDocument(content: markdown)
let frontmatter = document.frontmatter

// Check if frontmatter exists
if frontmatter.hasKey("title") {
    print("Document has a title")
}
```

## Parsing to AST

Convert Markdown to an abstract syntax tree for advanced processing:

```swift
import Markdown

let document = MarkdownDocument(content: markdown)

// Parse body to AST
let ast = document.parsedContent

// Traverse the AST
for child in ast.children {
    if let heading = child as? Heading {
        print("Found heading: \(heading.plainText)")
    }
}
```

The parsed content is a `Document` from the [swift-markdown](https://github.com/apple/swift-markdown) library, giving you full access to the AST for complex transformations.

## Modifying Documents

### Updating Frontmatter

Modify frontmatter and get the updated document:

```swift
var document = MarkdownDocument(content: markdown)

// Update a field
try document.frontmatter.setValue("New Title", forKey: "title")

// Add a new field
try document.frontmatter.setValue(["swift", "markdown"], forKey: "tags")

// Get the modified document
let updatedContent = document.content
```

The `content` property automatically reconstructs the document with the modified frontmatter.

### Updating Body Content

Replace the body while preserving frontmatter:

```swift
var document = MarkdownDocument(content: markdown)

// Create new body content
let newBody = """
# Updated Heading

New content here.
"""

// Reconstruct document with new body
let newContent = """
\(document.frontmatter.rawContent)

\(newBody)
"""

document = MarkdownDocument(content: newContent)
```

## Round-Trip Editing

Parse, modify, and render while preserving structure:

```swift
// Original document
let original = """
---
title: Original
author: Jane
---

# Content

Some text.
"""

// Parse
var document = MarkdownDocument(content: original)

// Modify
try document.frontmatter.setValue("Modified", forKey: "title")
try document.frontmatter.setValue(Date(), forKey: "updated")

// Render back to string
let modified = document.content

// Save to file
try modified.write(to: fileURL, atomically: true, encoding: .utf8)
```

## Advanced Operations

### Generating Table of Contents

Extract document structure:

```swift
let document = MarkdownDocument(content: markdown)

// Generate TOC with options
let options = TOCOptions(
    minLevel: 2,
    maxLevel: 4,
    includePosition: true
)

let toc = try document.generateTOC(options: options)

// Process entries
for entry in toc.entries {
    print("\(String(repeating: "  ", count: entry.level - 1))\(entry.text)")
}
```

See <doc:TableOfContents/GeneratingTOC> for complete TOC documentation.

### Converting to Plain Text

Strip formatting for previews or search indexing:

```swift
let document = MarkdownDocument(content: markdown)

// Default conversion
let plainText = document.toPlainText()

// Custom options
let options = PlainTextOptions(
    blockSeparator: "\n\n",
    indentLists: true,
    preserveCodeBlocks: true
)
let customPlainText = document.toPlainText(options: options)
```

See <doc:FormatConversion/PlainTextConversion> for conversion options.

### Extracting Headings

Get all headings from a document:

```swift
import Markdown

let document = MarkdownDocument(content: markdown)
let ast = document.parsedContent

var headings: [(level: Int, text: String)] = []

for element in ast.children {
    if let heading = element as? Heading {
        headings.append((heading.level, heading.plainText))
    }
}

for (level, text) in headings {
    let prefix = String(repeating: "#", count: level)
    print("\(prefix) \(text)")
}
```

## Best Practices

### Always Handle Errors

Frontmatter operations can throw errors:

```swift
do {
    var document = MarkdownDocument(content: markdown)
    try document.frontmatter.setValue("value", forKey: "key")
    print("Success")
} catch {
    print("Error: \(error)")
}
```

### Use Value Types

``MarkdownDocument`` is a value type (struct), so modifications create new instances:

```swift
let original = MarkdownDocument(content: markdown)
var modified = original  // Creates a copy

try modified.frontmatter.setValue("New", forKey: "title")

// original is unchanged
// modified has the new title
```

### Cache Parsed Content

If you're working extensively with the AST, cache the parsed content:

```swift
let document = MarkdownDocument(content: markdown)
let ast = document.parsedContent  // Cache this

// Perform multiple AST operations on the cached ast
// instead of calling parsedContent repeatedly
```

### Validate Input

Always validate frontmatter values match your schema:

```swift
func validateDocument(_ document: MarkdownDocument) -> Bool {
    // Check required fields
    guard document.frontmatter.hasKey("title"),
          document.frontmatter.hasKey("date") else {
        return false
    }

    // Check types
    guard document.frontmatter.getValue(forKey: "title") is String else {
        return false
    }

    return true
}
```

## Common Patterns

### Template Processing

Create documents from templates:

```swift
func createFromTemplate(title: String, author: String) -> MarkdownDocument {
    let template = """
    ---
    title: \(title)
    author: \(author)
    date: \(Date())
    draft: true
    ---

    # \(title)

    Write your content here.
    """

    return MarkdownDocument(content: template)
}

let newDoc = createFromTemplate(title: "My Post", author: "Jane Doe")
```

### Metadata Extraction

Extract all metadata for indexing:

```swift
struct DocumentMetadata {
    let title: String?
    let author: String?
    let tags: [String]?
    let wordCount: Int
}

func extractMetadata(from document: MarkdownDocument) -> DocumentMetadata {
    let title = document.frontmatter.getValue(forKey: "title") as? String
    let author = document.frontmatter.getValue(forKey: "author") as? String
    let tags = document.frontmatter.getValue(forKey: "tags") as? [String]

    let plainText = document.toPlainText()
    let wordCount = plainText.split(separator: " ").count

    return DocumentMetadata(
        title: title,
        author: author,
        tags: tags,
        wordCount: wordCount
    )
}
```

## See Also

- ``MarkdownDocument``
- ``FrontMatter``
- <doc:FrontMatter/CRUDOperations>
- <doc:TableOfContents/GeneratingTOC>
- <doc:FormatConversion/PlainTextConversion>
