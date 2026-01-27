# Generating Table of Contents

Complete guide to TOC generation with all configuration options.

## Overview

MarkdownUtilities provides flexible TOC generation through the ``MarkdownDocument/generateTOC(options:)`` method. This guide covers all configuration options, output formats, and advanced use cases.

## Basic Generation

### Default Options

Generate a TOC with default settings:

```swift
import MarkdownUtilities

let markdown = """
# Main Title

## Section 1

### Subsection 1.1

## Section 2

### Subsection 2.1

### Subsection 2.2
"""

let document = MarkdownDocument(content: markdown)
let toc = try document.generateTOC()

// Access entries
for entry in toc.entries {
    print("Level \(entry.level): \(entry.text)")
}
```

Default behavior:
- Includes all heading levels (1-6)
- Preserves hierarchical structure
- Generates slugs for all headings
- Does not include position information

### With Custom Options

Configure TOC generation with ``TOCOptions``:

```swift
let options = TOCOptions(
    minLevel: 2,
    maxLevel: 4,
    includePosition: true,
    generateSlugs: true,
    flat: false
)

let toc = try document.generateTOC(options: options)
```

## Configuration Options

### Heading Level Filtering

Control which heading levels are included:

```swift
// Only include h2 and h3
let options = TOCOptions(minLevel: 2, maxLevel: 3)
let toc = try document.generateTOC(options: options)

// Only h1 (main sections)
let mainSections = try document.generateTOC(
    options: TOCOptions(minLevel: 1, maxLevel: 1)
)

// h2 through h4 (common for documentation)
let docTOC = try document.generateTOC(
    options: TOCOptions(minLevel: 2, maxLevel: 4)
)
```

**Use cases:**
- Skip h1 when it's the page title
- Limit depth for cleaner navigation
- Extract specific heading levels for analysis

### Slug Generation

Control whether to generate URL-safe slugs:

```swift
// With slugs (default)
let options = TOCOptions(generateSlugs: true)
let toc = try document.generateTOC(options: options)

for entry in toc.entries {
    if let slug = entry.slug {
        print("Link: [\(entry.text)](#\(slug))")
    }
}

// Without slugs (faster for analysis)
let noSlugs = TOCOptions(generateSlugs: false)
let plainTOC = try document.generateTOC(options: noSlugs)
// entry.slug will be nil
```

**Slug examples:**

| Heading | Generated Slug |
|---------|----------------|
| Getting Started | `getting-started` |
| API v2.0 | `api-v20` |
| FAQ & Support | `faq-support` |
| 2024 Updates | `2024-updates` |

### Position Tracking

Include source position information:

```swift
let options = TOCOptions(includePosition: true)
let toc = try document.generateTOC(options: options)

for entry in toc.entries {
    if let position = entry.position {
        print("\(entry.text) at line \(position.line), col \(position.column)")
    }
}
```

**Position information includes:**
- Line number in source document
- Column offset
- Byte offset (for efficient seeking)

**Use cases:**
- Editor integration (jump to heading)
- Source mapping
- Diff tools
- Error reporting

### Flat vs Hierarchical

Control the structure of returned entries:

```swift
// Hierarchical (default) - preserves document structure
let hierarchical = try document.generateTOC()

// Flat - all entries at same level
let flat = try document.generateTOC(
    options: TOCOptions(flat: true)
)
```

> Note: Even in flat mode, each entry's `level` property still reflects its original heading level.

## Working with TOC Entries

### Entry Properties

Each ``TOCEntry`` provides:

```swift
let entry = toc.entries[0]

// Heading level (1-6)
let level = entry.level

// Plain text (Markdown formatting removed)
let text = entry.text

// URL-safe slug (if generated)
let slug = entry.slug

// Source position (if tracked)
let position = entry.position
```

### Iterating Entries

Process all entries:

```swift
let toc = try document.generateTOC()

for entry in toc.entries {
    // Process each entry
    print("\(entry.level): \(entry.text)")
}
```

### Filtering Entries

Filter by level or content:

```swift
let toc = try document.generateTOC()

// Get only h2 headings
let h2Entries = toc.entries.filter { $0.level == 2 }

// Get entries containing specific text
let apiEntries = toc.entries.filter {
    $0.text.lowercased().contains("api")
}

// Get top-level sections
let topLevel = toc.entries.filter { $0.level == 1 }
```

### Building Nested Structures

Convert flat entries to nested structure:

```swift
struct TOCNode {
    let entry: TOCEntry
    var children: [TOCNode] = []
}

func buildHierarchy(from entries: [TOCEntry]) -> [TOCNode] {
    var roots: [TOCNode] = []
    var stack: [TOCNode] = []

    for entry in entries {
        let node = TOCNode(entry: entry)

        // Pop stack until we find the parent level
        while let last = stack.last, last.entry.level >= entry.level {
            stack.removeLast()
        }

        if let parent = stack.last {
            var parentCopy = parent
            parentCopy.children.append(node)
            stack[stack.count - 1] = parentCopy
        } else {
            roots.append(node)
        }

        stack.append(node)
    }

    return roots
}
```

## Output Formats

### Markdown List

Generate Markdown TOC:

```swift
func formatAsMarkdown(_ toc: TableOfContents) -> String {
    var lines = ["## Table of Contents", ""]

    for entry in toc.entries {
        let indent = String(repeating: "  ", count: entry.level - 1)
        let link = entry.slug.map { "[\(entry.text)](#\($0))" } ?? entry.text
        lines.append("\(indent)- \(link)")
    }

    return lines.joined(separator: "\n")
}

let markdown = formatAsMarkdown(toc)
print(markdown)
```

**Output:**
```markdown
## Table of Contents

- [Introduction](#introduction)
  - [Getting Started](#getting-started)
    - [Installation](#installation)
  - [Usage](#usage)
```

### Plain Text

Simple indented outline:

```swift
func formatAsPlainText(_ toc: TableOfContents) -> String {
    toc.entries.map { entry in
        let indent = String(repeating: "  ", count: entry.level - 1)
        return "\(indent)\(entry.text)"
    }.joined(separator: "\n")
}
```

### HTML

Generate HTML navigation:

```swift
func formatAsHTML(_ toc: TableOfContents) -> String {
    var html = "<nav class=\"toc\">\n<ul>\n"

    var currentLevel = 0

    for entry in toc.entries {
        // Close nested lists if needed
        while currentLevel > entry.level {
            html += "</ul>\n</li>\n"
            currentLevel -= 1
        }

        // Open nested lists if needed
        while currentLevel < entry.level {
            if currentLevel > 0 {
                html += "\n<ul>\n"
            }
            currentLevel += 1
        }

        // Add the entry
        let link = entry.slug.map { "<a href=\"#\($0)\">\(entry.text)</a>" } ?? entry.text
        html += "<li>\(link)</li>\n"
    }

    // Close remaining lists
    while currentLevel > 0 {
        html += "</ul>\n"
        if currentLevel > 1 {
            html += "</li>\n"
        }
        currentLevel -= 1
    }

    html += "</ul>\n</nav>"
    return html
}
```

### JSON

Export as JSON for APIs:

```swift
import Foundation

struct TOCEntryJSON: Codable {
    let level: Int
    let text: String
    let slug: String?
}

func formatAsJSON(_ toc: TableOfContents) throws -> String {
    let entries = toc.entries.map { entry in
        TOCEntryJSON(
            level: entry.level,
            text: entry.text,
            slug: entry.slug
        )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(entries)
    return String(data: data, encoding: .utf8) ?? ""
}
```

## Advanced Use Cases

### Validating Document Structure

Check for structural issues:

```swift
func validateTOCStructure(_ toc: TableOfContents) throws {
    // Ensure document starts with h1
    guard let first = toc.entries.first, first.level == 1 else {
        throw ValidationError.missingH1
    }

    // Check for level skipping
    for i in 1..<toc.entries.count {
        let prev = toc.entries[i - 1]
        let curr = toc.entries[i]

        // Level should not increase by more than 1
        if curr.level > prev.level + 1 {
            throw ValidationError.skippedLevel(
                from: prev.level,
                to: curr.level,
                heading: curr.text
            )
        }
    }

    // Ensure reasonable depth
    let maxLevel = toc.entries.map(\.level).max() ?? 0
    guard maxLevel <= 4 else {
        throw ValidationError.tooDeep(maxLevel)
    }
}
```

### Generating Section Numbers

Add numbering to headings:

```swift
func addSectionNumbers(to toc: TableOfContents) -> [(number: String, entry: TOCEntry)] {
    var counters = [0, 0, 0, 0, 0, 0]  // For levels 1-6
    var numbered: [(String, TOCEntry)] = []

    for entry in toc.entries {
        let level = entry.level - 1

        // Increment current level
        counters[level] += 1

        // Reset deeper levels
        for i in (level + 1)..<counters.count {
            counters[i] = 0
        }

        // Build number string
        let numbers = counters[0...level].filter { $0 > 0 }
        let numberString = numbers.map(String.init).joined(separator: ".")

        numbered.append((numberString, entry))
    }

    return numbered
}

// Usage
let numbered = addSectionNumbers(to: toc)
for (number, entry) in numbered {
    print("\(number). \(entry.text)")
}
// Output:
// 1. Introduction
// 1.1. Getting Started
// 1.1.1. Installation
// 2. Usage
```

### Creating Navigation Trees

Build a navigable tree structure:

```swift
class TOCTreeNode {
    let entry: TOCEntry
    var children: [TOCTreeNode] = []
    weak var parent: TOCTreeNode?

    init(entry: TOCEntry) {
        self.entry = entry
    }

    func addChild(_ child: TOCTreeNode) {
        children.append(child)
        child.parent = self
    }

    // Get all ancestors
    var ancestors: [TOCTreeNode] {
        var nodes: [TOCTreeNode] = []
        var current = parent
        while let node = current {
            nodes.insert(node, at: 0)
            current = node.parent
        }
        return nodes
    }

    // Get breadcrumb path
    var breadcrumb: String {
        let path = ancestors.map(\.entry.text) + [entry.text]
        return path.joined(separator: " > ")
    }
}

func buildNavigationTree(from toc: TableOfContents) -> [TOCTreeNode] {
    var roots: [TOCTreeNode] = []
    var stack: [TOCTreeNode] = []

    for entry in toc.entries {
        let node = TOCTreeNode(entry: entry)

        // Find parent
        while let last = stack.last, last.entry.level >= entry.level {
            stack.removeLast()
        }

        if let parent = stack.last {
            parent.addChild(node)
        } else {
            roots.append(node)
        }

        stack.append(node)
    }

    return roots
}
```

### Extracting Specific Sections

Get content for a specific section:

```swift
func extractSection(
    matching heading: String,
    from document: MarkdownDocument
) throws -> String? {
    let options = TOCOptions(includePosition: true)
    let toc = try document.generateTOC(options: options)

    // Find the heading
    guard let index = toc.entries.firstIndex(where: { $0.text == heading }),
          let startPos = toc.entries[index].position else {
        return nil
    }

    // Find the next heading at the same or higher level
    let currentLevel = toc.entries[index].level
    let nextIndex = toc.entries[(index + 1)...]
        .firstIndex(where: { $0.level <= currentLevel })

    let endPos = nextIndex.flatMap { toc.entries[$0].position }

    // Extract content between positions
    let lines = document.content.components(separatedBy: .newlines)

    if let endPos = endPos {
        return lines[startPos.line..<endPos.line].joined(separator: "\n")
    } else {
        return lines[startPos.line...].joined(separator: "\n")
    }
}
```

## Performance Considerations

### Caching TOCs

Cache generated TOCs when processing multiple times:

```swift
class DocumentProcessor {
    private var tocCache: [String: TableOfContents] = [:]

    func getTOC(for document: MarkdownDocument) throws -> TableOfContents {
        let key = document.content

        if let cached = tocCache[key] {
            return cached
        }

        let toc = try document.generateTOC()
        tocCache[key] = toc
        return toc
    }
}
```

### Minimal Options for Speed

Use minimal options when performance matters:

```swift
// Fast: No slugs, no positions
let fast = try document.generateTOC(
    options: TOCOptions(
        generateSlugs: false,
        includePosition: false
    )
)

// Slower: Full tracking
let detailed = try document.generateTOC(
    options: TOCOptions(
        generateSlugs: true,
        includePosition: true
    )
)
```

## See Also

- ``TableOfContents``
- ``TOCEntry``
- ``TOCOptions``
- ``MarkdownDocument/generateTOC(options:)``
- <doc:TOCOverview>
