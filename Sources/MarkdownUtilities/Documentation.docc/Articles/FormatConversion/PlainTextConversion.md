# Plain Text Conversion

Convert Markdown to plain text with customizable formatting options.

## Overview

MarkdownUtilities can convert Markdown documents to plain text, stripping formatting while preserving content structure. This is useful for previews, search indexing, content analysis, and accessibility.

## Basic Conversion

### Default Conversion

Convert with default options:

```swift
import MarkdownUtilities

let markdown = """
# Welcome

This is **bold** and this is *italic*.

## Features

- First item
- Second item
- Third item

```swift
let code = "example"
```

Visit [our website](https://example.com).
"""

let document = MarkdownDocument(content: markdown)
let plainText = document.toPlainText()

print(plainText)
```

**Output:**
```
Welcome

This is bold and this is italic.

Features

First item
Second item
Third item

let code = "example"

Visit our website.
```

### With Custom Options

Configure conversion behavior:

```swift
let options = PlainTextOptions(
    blockSeparator: "\n\n",
    indentLists: true,
    preserveCodeBlocks: true
)

let plainText = document.toPlainText(options: options)
```

## Configuration Options

### Block Separator

Control spacing between block elements:

```swift
// Double newlines (default)
let spaced = document.toPlainText(
    options: PlainTextOptions(blockSeparator: "\n\n")
)

// Single newlines (compact)
let compact = document.toPlainText(
    options: PlainTextOptions(blockSeparator: "\n")
)

// Triple newlines (extra spacing)
let wide = document.toPlainText(
    options: PlainTextOptions(blockSeparator: "\n\n\n")
)
```

**Example:**

```swift
// Input
let md = """
# Title

Paragraph 1.

Paragraph 2.
"""

// With "\n\n" (default)
// Output:
// Title
//
// Paragraph 1.
//
// Paragraph 2.

// With "\n"
// Output:
// Title
// Paragraph 1.
// Paragraph 2.
```

### List Indentation

Control whether list items are indented:

```swift
// With indentation (default)
let indented = document.toPlainText(
    options: PlainTextOptions(indentLists: true)
)

// Without indentation
let flat = document.toPlainText(
    options: PlainTextOptions(indentLists: false)
)
```

**Example:**

```swift
// Input
let md = """
## Items

- Top level
  - Nested item
  - Another nested
- Back to top
"""

// With indentLists: true
// Items
//
// Top level
//   Nested item
//   Another nested
// Back to top

// With indentLists: false
// Items
//
// Top level
// Nested item
// Another nested
// Back to top
```

### Code Block Preservation

Choose whether to preserve or strip code blocks:

```swift
// Preserve code (default)
let withCode = document.toPlainText(
    options: PlainTextOptions(preserveCodeBlocks: true)
)

// Strip code blocks
let noCode = document.toPlainText(
    options: PlainTextOptions(preserveCodeBlocks: false)
)
```

**Example:**

```swift
// Input
let md = """
## Example

Here's some code:

```swift
func hello() {
    print("Hello")
}
```

And some text after.
"""

// With preserveCodeBlocks: true
// Example
//
// Here's some code:
//
// func hello() {
//     print("Hello")
// }
//
// And some text after.

// With preserveCodeBlocks: false
// Example
//
// Here's some code:
//
// And some text after.
```

## Preset Options

### PlainTextPresets

Use predefined configurations:

```swift
// Default preset
let defaultText = document.toPlainText(options: .default)

// Compact preset (single line breaks, no indentation)
let compactText = document.toPlainText(options: .compact)

// Single line (everything on one line)
let singleLine = document.toPlainText(options: .singleLine)
```

### Default Preset

Standard formatting for readability:

```swift
PlainTextOptions(
    blockSeparator: "\n\n",
    indentLists: true,
    preserveCodeBlocks: true
)
```

### Compact Preset

Minimal spacing for dense output:

```swift
PlainTextOptions(
    blockSeparator: "\n",
    indentLists: false,
    preserveCodeBlocks: true
)
```

### Single Line Preset

Everything on one line for previews:

```swift
PlainTextOptions(
    blockSeparator: " ",
    indentLists: false,
    preserveCodeBlocks: false
)
```

## Format Stripping

### What Gets Removed

The conversion strips all Markdown formatting:

| Markdown | Plain Text |
|----------|------------|
| `**bold**` | `bold` |
| `*italic*` | `italic` |
| `~~strikethrough~~` | `strikethrough` |
| `[link](url)` | `link` |
| `![alt](image.png)` | `alt` |
| `` `code` `` | `code` |
| `# Heading` | `Heading` |

### What Gets Preserved

Content structure is maintained:

- Paragraph breaks
- List structure (with optional indentation)
- Heading text
- Link text (URLs removed)
- Image alt text
- Code block content (optional)

## Common Use Cases

### Content Previews

Generate preview text for articles:

```swift
func generatePreview(from document: MarkdownDocument, maxLength: Int = 200) -> String {
    let plainText = document.toPlainText(options: .compact)

    // Get first N characters
    if plainText.count <= maxLength {
        return plainText
    }

    let preview = plainText.prefix(maxLength)

    // Find last space to avoid cutting words
    if let lastSpace = preview.lastIndex(of: " ") {
        return String(preview[..<lastSpace]) + "..."
    }

    return String(preview) + "..."
}

let preview = generatePreview(from: document)
print(preview)
// "This is an article about Swift programming. It covers the basics of..."
```

### Search Indexing

Prepare content for full-text search:

```swift
import Foundation

func indexDocument(_ document: MarkdownDocument) -> [String: Any] {
    // Convert to plain text
    let plainText = document.toPlainText(options: .compact)

    // Extract metadata
    let title = document.frontmatter.getValue(forKey: "title") as? String ?? "Untitled"
    let tags = document.frontmatter.getValue(forKey: "tags") as? [String] ?? []

    // Build search index
    return [
        "title": title,
        "content": plainText,
        "tags": tags,
        "wordCount": plainText.components(separatedBy: .whitespaces).count
    ]
}
```

### Word Count

Calculate accurate word counts:

```swift
func wordCount(for document: MarkdownDocument) -> Int {
    let plainText = document.toPlainText(options: .compact)
    let words = plainText.components(separatedBy: .whitespaces)
    return words.filter { !$0.isEmpty }.count
}

let count = wordCount(for: document)
print("Word count: \(count)")
```

### Content Analysis

Analyze text content:

```swift
import NaturalLanguage

func analyzeContent(_ document: MarkdownDocument) {
    let plainText = document.toPlainText()

    // Language detection
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(plainText)
    if let language = recognizer.dominantLanguage {
        print("Language: \(language.rawValue)")
    }

    // Sentiment analysis
    let tagger = NLTagger(tagSchemes: [.sentimentScore])
    tagger.string = plainText
    let (sentiment, _) = tagger.tag(at: plainText.startIndex,
                                    unit: .paragraph,
                                    scheme: .sentimentScore)
    print("Sentiment: \(sentiment?.rawValue ?? "neutral")")

    // Word frequency
    let words = plainText.lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }

    let frequency = Dictionary(grouping: words, by: { $0 })
        .mapValues(\.count)
        .sorted { $0.value > $1.value }

    print("Top words:")
    for (word, count) in frequency.prefix(10) {
        print("  \(word): \(count)")
    }
}
```

### Email Content

Prepare Markdown for plain-text emails:

```swift
func convertToEmailBody(_ document: MarkdownDocument) -> String {
    let options = PlainTextOptions(
        blockSeparator: "\n\n",
        indentLists: true,
        preserveCodeBlocks: true
    )

    var plainText = document.toPlainText(options: options)

    // Wrap lines at 72 characters (email convention)
    let wrapped = wrapLines(plainText, width: 72)

    return wrapped
}

func wrapLines(_ text: String, width: Int) -> String {
    text.components(separatedBy: .newlines)
        .map { line in
            guard line.count > width else { return line }

            var wrapped: [String] = []
            var current = ""

            for word in line.components(separatedBy: " ") {
                if (current + " " + word).count > width {
                    if !current.isEmpty {
                        wrapped.append(current)
                    }
                    current = word
                } else {
                    current += (current.isEmpty ? "" : " ") + word
                }
            }

            if !current.isEmpty {
                wrapped.append(current)
            }

            return wrapped.joined(separator: "\n")
        }
        .joined(separator: "\n")
}
```

### Accessibility

Generate screen reader-friendly text:

```swift
func accessibilityText(from document: MarkdownDocument) -> String {
    // Use default options for natural reading
    let plainText = document.toPlainText()

    // Add document metadata for context
    var result = ""

    if let title = document.frontmatter.getValue(forKey: "title") as? String {
        result += "Document title: \(title)\n\n"
    }

    if let author = document.frontmatter.getValue(forKey: "author") as? String {
        result += "Author: \(author)\n\n"
    }

    result += plainText

    return result
}
```

## Advanced Techniques

### Preserving Specific Formatting

Custom conversion that preserves certain elements:

```swift
import Markdown

func convertPreservingEmphasis(_ document: MarkdownDocument) -> String {
    let ast = document.parsedContent
    var result = ""

    func process(_ element: Markup) -> String {
        var text = ""

        if let emphasis = element as? Emphasis {
            // Preserve italic with underscores
            text += "_"
            for child in emphasis.children {
                text += process(child)
            }
            text += "_"
        } else if let strong = element as? Strong {
            // Preserve bold with asterisks
            text += "**"
            for child in strong.children {
                text += process(child)
            }
            text += "**"
        } else if let textElement = element as? Text {
            text += textElement.string
        } else {
            for child in element.children {
                text += process(child)
            }
        }

        return text
    }

    for child in ast.children {
        result += process(child) + "\n\n"
    }

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

### Custom Separator Logic

Different separators for different block types:

```swift
import Markdown

func customConversion(_ document: MarkdownDocument) -> String {
    let ast = document.parsedContent
    var result: [String] = []

    for element in ast.children {
        if element is Heading {
            // Extra spacing around headings
            result.append("\n" + element.plainText + "\n")
        } else if element is CodeBlock {
            // Code blocks with markers
            result.append("--- Code ---\n" + element.plainText + "\n--- End Code ---")
        } else if element is BlockQuote {
            // Indent quotes
            let quoted = element.plainText
                .components(separatedBy: .newlines)
                .map { "> \($0)" }
                .joined(separator: "\n")
            result.append(quoted)
        } else {
            result.append(element.plainText)
        }
    }

    return result.joined(separator: "\n\n")
}
```

## Best Practices

### Choose Appropriate Options

Match options to your use case:

```swift
// For reading/display
let readable = document.toPlainText(options: .default)

// For compact storage
let compact = document.toPlainText(options: .compact)

// For one-line previews
let preview = document.toPlainText(options: .singleLine)

// For analysis (preserve structure)
let analysis = document.toPlainText(
    options: PlainTextOptions(
        blockSeparator: "\n",
        indentLists: true,
        preserveCodeBlocks: false
    )
)
```

### Handle Edge Cases

Deal with empty content:

```swift
let plainText = document.toPlainText()

if plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    print("Document has no content")
} else {
    print("Content: \(plainText)")
}
```

### Performance Considerations

Cache converted text when needed:

```swift
class DocumentCache {
    private var plainTextCache: [String: String] = [:]

    func getPlainText(for document: MarkdownDocument) -> String {
        let key = document.content

        if let cached = plainTextCache[key] {
            return cached
        }

        let plainText = document.toPlainText()
        plainTextCache[key] = plainText
        return plainText
    }
}
```

## See Also

- ``PlainTextOptions``
- ``PlainTextPresets``
- ``MarkdownDocument/toPlainText(options:)``
- <doc:MarkdownDocument>
