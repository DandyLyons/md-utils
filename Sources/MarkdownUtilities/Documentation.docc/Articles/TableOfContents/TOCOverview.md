# Table of Contents Overview

Understanding table of contents generation from Markdown documents.

## Overview

A table of contents (TOC) is a hierarchical navigation structure extracted from a document's headings. MarkdownUtilities provides powerful TOC generation capabilities that analyze your Markdown documents and create structured, navigable outlines.

## What is a Table of Contents?

A TOC is an organized list of headings that provides:

- **Document Navigation**: Quick access to different sections
- **Content Overview**: High-level view of document structure
- **Accessibility**: Screen reader navigation support
- **SEO Benefits**: Improved content structure for search engines

### Example

Given this Markdown:

```markdown
# Introduction

Some content here.

## Getting Started

More content.

### Prerequisites

Details about prerequisites.

### Installation

Installation instructions.

## Usage

How to use the tool.
```

A TOC might look like:

```
- Introduction
  - Getting Started
    - Prerequisites
    - Installation
  - Usage
```

## Use Cases

### Document Navigation

Add clickable navigation to long documents:

```markdown
## Table of Contents

- [Introduction](#introduction)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Usage](#usage)
```

### Site Maps

Generate site structure for static site generators:

```swift
let document = MarkdownDocument(content: pageContent)
let toc = try document.generateTOC()

// Generate sitemap.xml from toc.entries
```

### Document Outlines

Create document outlines for editors or previews:

```swift
let toc = try document.generateTOC()

for entry in toc.entries {
    let indent = String(repeating: "  ", count: entry.level - 1)
    print("\(indent)\(entry.level). \(entry.text)")
}
```

### Content Analysis

Analyze document structure:

```swift
let toc = try document.generateTOC()

// Check heading depth
let maxDepth = toc.entries.map(\.level).max() ?? 0
print("Maximum heading depth: \(maxDepth)")

// Count headings per level
let level2Count = toc.entries.filter { $0.level == 2 }.count
print("Number of level 2 headings: \(level2Count)")
```

## Hierarchical vs Flat Structure

### Hierarchical (Default)

Preserves the document's heading structure:

```
1. Introduction
  1.1. Overview
  1.2. Goals
2. Implementation
  2.1. Architecture
    2.1.1. Components
  2.2. API Design
```

Generated with standard options:

```swift
let toc = try document.generateTOC()
// toc.entries preserves hierarchy through level property
```

### Flat Structure

Returns all headings at the same level:

```swift
let options = TOCOptions(flat: true)
let toc = try document.generateTOC(options: options)

// All entries have the same hierarchical position
// but retain their original level in the level property
```

## The TableOfContents Type

``TableOfContents`` contains:

```swift
public struct TableOfContents {
    /// All TOC entries in document order
    public let entries: [TOCEntry]

    /// The source document content
    public let sourceDocument: String
}
```

### TOCEntry

Each ``TOCEntry`` represents one heading:

```swift
public struct TOCEntry {
    /// Heading level (1-6)
    public let level: Int

    /// Heading text (without Markdown formatting)
    public let text: String

    /// URL-safe slug for linking
    public let slug: String?

    /// Position in source document (if requested)
    public let position: SourcePosition?
}
```

## Basic Generation Example

```swift
import MarkdownUtilities

let markdown = """
# Introduction

Welcome to the guide.

## Getting Started

Let's begin.

### Prerequisites

You'll need these tools.

## Advanced Topics

For experienced users.
"""

let document = MarkdownDocument(content: markdown)
let toc = try document.generateTOC()

// Print the TOC
for entry in toc.entries {
    let indent = String(repeating: "  ", count: entry.level - 1)
    let bullet = entry.level == 1 ? "•" : "-"
    print("\(indent)\(bullet) \(entry.text)")
}

// Output:
// • Introduction
//   - Getting Started
//     - Prerequisites
//   - Advanced Topics
```

## Slug Generation

Slugs are URL-safe identifiers for linking to headings:

```swift
let toc = try document.generateTOC()

for entry in toc.entries {
    if let slug = entry.slug {
        print("[\(entry.text)](#\(slug))")
    }
}

// Output:
// [Introduction](#introduction)
// [Getting Started](#getting-started)
// [Prerequisites](#prerequisites)
```

Slugs are generated automatically by:
1. Converting to lowercase
2. Replacing spaces with hyphens
3. Removing special characters
4. Ensuring uniqueness

### Example Slug Transformations

| Heading Text | Generated Slug |
|-------------|----------------|
| `Getting Started` | `getting-started` |
| `API Reference` | `api-reference` |
| `FAQ & Support` | `faq-support` |
| `v2.0 Changes` | `v20-changes` |

## Position Tracking

Track heading positions in the source document:

```swift
let options = TOCOptions(includePosition: true)
let toc = try document.generateTOC(options: options)

for entry in toc.entries {
    if let pos = entry.position {
        print("\(entry.text) at line \(pos.line), column \(pos.column)")
    }
}
```

This is useful for:
- **Editor Integration**: Jump to heading in source
- **Error Reporting**: Reference specific locations
- **Diff Tools**: Track heading changes

## Common Patterns

### Generating Markdown TOC

```swift
func generateMarkdownTOC(from document: MarkdownDocument) throws -> String {
    let toc = try document.generateTOC()

    var lines: [String] = ["## Table of Contents", ""]

    for entry in toc.entries {
        let indent = String(repeating: "  ", count: entry.level - 1)
        let link = entry.slug.map { "[\(entry.text)](#\($0))" } ?? entry.text
        lines.append("\(indent)- \(link)")
    }

    return lines.joined(separator: "\n")
}
```

### Filtering by Level

```swift
let toc = try document.generateTOC()

// Get only major sections (level 1 and 2)
let majorSections = toc.entries.filter { $0.level <= 2 }

// Get subsections (level 3+)
let subsections = toc.entries.filter { $0.level >= 3 }
```

### Validating Structure

```swift
func validateDocumentStructure(_ document: MarkdownDocument) throws {
    let toc = try document.generateTOC()

    // Check for missing level 1 heading
    guard toc.entries.contains(where: { $0.level == 1 }) else {
        throw ValidationError.missingMainHeading
    }

    // Check for too many nesting levels
    let maxLevel = toc.entries.map(\.level).max() ?? 0
    guard maxLevel <= 4 else {
        throw ValidationError.tooManyLevels(maxLevel)
    }

    // Check for skipped levels (e.g., h1 → h3)
    for (index, entry) in toc.entries.enumerated() {
        if index > 0 {
            let prevLevel = toc.entries[index - 1].level
            let levelJump = entry.level - prevLevel
            guard levelJump <= 1 else {
                throw ValidationError.skippedLevel(
                    from: prevLevel,
                    to: entry.level
                )
            }
        }
    }
}
```

## Next Steps

Learn how to generate and customize TOC output:

- <doc:GeneratingTOC> - Detailed generation guide with all options

## See Also

- ``TableOfContents``
- ``TOCEntry``
- ``TOCOptions``
- ``MarkdownDocument/generateTOC(options:)``
