# Getting Started with MarkdownUtilities

Learn how to integrate and use MarkdownUtilities in your Swift projects.

## Overview

MarkdownUtilities is a Swift library that makes it easy to work with Markdown documents. This guide will help you get started quickly with parsing Markdown files, accessing frontmatter, and performing common operations.

## Installation

Add MarkdownUtilities as a dependency to your Swift package:

```swift
// Package.swift
let package = Package(
    name: "YourPackage",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    dependencies: [
        .package(url: "https://github.com/yourusername/md-utils.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "YourTarget",
            dependencies: [
                .product(name: "MarkdownUtilities", package: "md-utils")
            ]
        )
    ]
)
```

## Your First Markdown Document

Here's a simple example that demonstrates the core functionality:

```swift
import MarkdownUtilities

// Create a Markdown document with frontmatter
let markdown = """
---
title: My First Document
author: Jane Doe
tags: [swift, markdown]
---

# Welcome

This is a **Markdown** document with frontmatter.
"""

// Parse the document
let document = MarkdownDocument(content: markdown)

// Access frontmatter
if let title = document.frontmatter.getValue(forKey: "title") as? String {
    print("Title: \(title)")  // Prints: Title: My First Document
}

// Get the body content (without frontmatter)
let body = document.body
print(body)
// Prints:
// # Welcome
//
// This is a **Markdown** document with frontmatter.
```

## Common Operations

### Reading Frontmatter

Access frontmatter values using type-safe getters:

```swift
let document = MarkdownDocument(content: markdown)

// Get a string value
if let title = document.frontmatter.getValue(forKey: "title") as? String {
    print("Title: \(title)")
}

// Get an array value
if let tags = document.frontmatter.getValue(forKey: "tags") as? [String] {
    print("Tags: \(tags.joined(separator: ", "))")
}

// Check if a key exists
if document.frontmatter.hasKey("author") {
    print("Document has an author")
}
```

### Modifying Frontmatter

Update frontmatter values and render the modified document:

```swift
var document = MarkdownDocument(content: markdown)

// Set a new value
try document.frontmatter.setValue("Updated Title", forKey: "title")

// Add a new field
try document.frontmatter.setValue(Date(), forKey: "updated")

// Get the modified document
let updatedMarkdown = document.content
```

### Generating a Table of Contents

Extract headings and create a TOC:

```swift
let document = MarkdownDocument(content: markdown)

// Generate TOC with default options
let toc = try document.generateTOC()

// Access TOC entries
for entry in toc.entries {
    let indent = String(repeating: "  ", count: entry.level - 1)
    print("\(indent)- \(entry.text)")
}
```

### Converting to Plain Text

Strip Markdown formatting and extract plain text:

```swift
let document = MarkdownDocument(content: markdown)

// Convert with default options
let plainText = document.toPlainText()
print(plainText)

// Convert with custom options
let compactText = document.toPlainText(options: .compact)
```

## Next Steps

Now that you've learned the basics, explore these topics:

- <doc:IntegrationGuide> - Detailed integration instructions
- <doc:MarkdownDocument> - Deep dive into the core type
- <doc:FrontMatter/CRUDOperations> - Complete frontmatter reference
- <doc:TableOfContents/GeneratingTOC> - Advanced TOC generation

## See Also

- ``MarkdownDocument``
- ``FrontMatter``
- ``TableOfContents``
