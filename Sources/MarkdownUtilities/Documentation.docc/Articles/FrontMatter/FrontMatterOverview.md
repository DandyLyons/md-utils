# Frontmatter Overview

Understanding YAML frontmatter in Markdown documents.

## Overview

Frontmatter is YAML-formatted metadata placed at the beginning of Markdown documents. It's widely used in static site generators like Hugo and Jekyll, note-taking apps like Obsidian, and content management systems to store structured data alongside Markdown content.

## What is Frontmatter?

Frontmatter consists of YAML data enclosed between triple-dash delimiters (`---`):

```markdown
---
title: My Blog Post
date: 2024-01-24
author: Jane Doe
tags: [swift, programming, tutorial]
published: true
---

# My Blog Post

The actual Markdown content starts here.
```

The frontmatter block must:
- Start at the very beginning of the file
- Be enclosed in `---` delimiters
- Contain valid YAML syntax
- Be separated from the body by a blank line (recommended)

## Common Use Cases

### Static Site Generators

Hugo, Jekyll, and other static site generators use frontmatter for:

```yaml
---
title: "Understanding Swift Concurrency"
date: 2024-01-24T10:00:00Z
draft: false
categories: [programming, swift]
tags: [swift, async-await, concurrency]
author: Jane Doe
description: "A comprehensive guide to Swift concurrency"
---
```

### Note-Taking Apps

Obsidian and similar apps use frontmatter for metadata:

```yaml
---
title: Project Meeting Notes
created: 2024-01-24
tags: [meetings, project-alpha]
status: active
attendees: [Alice, Bob, Charlie]
---
```

### Documentation

Technical documentation often includes:

```yaml
---
title: API Reference
version: 1.0.0
category: reference
last-updated: 2024-01-24
---
```

## YAML Syntax Quick Reference

### Strings

```yaml
# Simple strings
title: My Title

# Quoted strings (for special characters)
title: "Title: With Colon"
title: 'Single quotes work too'

# Multi-line strings
description: |
  This is a multi-line
  description that preserves
  line breaks.
```

### Numbers and Booleans

```yaml
# Numbers
count: 42
price: 19.99

# Booleans
published: true
draft: false
```

### Arrays

```yaml
# Inline array
tags: [swift, programming, tutorial]

# Block array
categories:
  - Programming
  - Swift
  - Tutorial
```

### Objects (Nested Data)

```yaml
# Nested object
author:
  name: Jane Doe
  email: jane@example.com
  twitter: "@janedoe"

# Access in Swift:
# let name = frontmatter.getValue(forKey: "author.name")
```

### Dates

```yaml
# ISO 8601 format
date: 2024-01-24
datetime: 2024-01-24T10:30:00Z

# Alternative formats (interpreted as strings)
published: "January 24, 2024"
```

## Accessing Frontmatter in MarkdownUtilities

### Basic Access

```swift
let document = MarkdownDocument(content: markdown)

// Get a string value
if let title = document.frontmatter.getValue(forKey: "title") as? String {
    print("Title: \(title)")
}

// Get a boolean
if let published = document.frontmatter.getValue(forKey: "published") as? Bool {
    print("Published: \(published)")
}

// Get an array
if let tags = document.frontmatter.getValue(forKey: "tags") as? [String] {
    print("Tags: \(tags.joined(separator: ", "))")
}
```

### Type Safety

Always cast values to the expected type:

```swift
// Safe approach with optional binding
if let count = document.frontmatter.getValue(forKey: "count") as? Int {
    print("Count: \(count)")
} else {
    print("Count is missing or not an integer")
}

// Check if key exists first
if document.frontmatter.hasKey("author") {
    if let author = document.frontmatter.getValue(forKey: "author") as? String {
        print("Author: \(author)")
    }
}
```

## Integration with Popular Tools

### Hugo

Hugo expects specific frontmatter fields:

```yaml
---
title: "Post Title"
date: 2024-01-24T10:00:00Z
draft: false
tags: [tag1, tag2]
categories: [category1]
summary: "Brief description"
---
```

MarkdownUtilities works seamlessly with Hugo's frontmatter format.

### Jekyll

Jekyll uses similar YAML frontmatter:

```yaml
---
layout: post
title: "Post Title"
date: 2024-01-24 10:00:00 +0000
categories: [category1, category2]
tags: [tag1, tag2]
---
```

### Obsidian

Obsidian supports flexible frontmatter:

```yaml
---
tags: [note, important]
created: 2024-01-24
modified: 2024-01-24
status: active
---
```

Obsidian also supports inline fields, but MarkdownUtilities focuses on standard YAML frontmatter.

## Best Practices

### Use Consistent Keys

Standardize field names across your documents:

```yaml
# Good: Consistent naming
title: "My Post"
created: 2024-01-24
modified: 2024-01-24

# Avoid: Inconsistent naming
title: "My Post"
created_date: 2024-01-24
date_modified: 2024-01-24
```

### Choose Appropriate Types

Use the right YAML type for each field:

```yaml
# Good
count: 42          # Number
published: true    # Boolean
tags: [a, b]       # Array

# Avoid
count: "42"        # String (harder to process)
published: "true"  # String (not a boolean)
tags: "a, b"       # String (not an array)
```

### Document Your Schema

Define a schema for your frontmatter:

```swift
// Define expected fields
enum FrontmatterField: String {
    case title
    case date
    case author
    case tags
    case published
}

// Validate against schema
func validate(_ document: MarkdownDocument) -> Bool {
    let required: [FrontmatterField] = [.title, .date]

    for field in required {
        guard document.frontmatter.hasKey(field.rawValue) else {
            return false
        }
    }

    return true
}
```

### Handle Missing Fields Gracefully

Always provide defaults or handle missing fields:

```swift
// Provide default values
let title = document.frontmatter.getValue(forKey: "title") as? String ?? "Untitled"
let tags = document.frontmatter.getValue(forKey: "tags") as? [String] ?? []
let published = document.frontmatter.getValue(forKey: "published") as? Bool ?? false
```

## Common Patterns

### Required vs Optional Fields

```swift
struct PostMetadata {
    // Required fields
    let title: String
    let date: Date

    // Optional fields
    let author: String?
    let tags: [String]?

    init?(from frontmatter: FrontMatter) {
        // Required fields must exist
        guard let title = frontmatter.getValue(forKey: "title") as? String,
              let date = frontmatter.getValue(forKey: "date") as? Date else {
            return nil
        }

        self.title = title
        self.date = date
        self.author = frontmatter.getValue(forKey: "author") as? String
        self.tags = frontmatter.getValue(forKey: "tags") as? [String]
    }
}
```

### Nested Metadata

```yaml
---
author:
  name: Jane Doe
  email: jane@example.com
  social:
    twitter: "@janedoe"
    github: "janedoe"
---
```

```swift
// Access nested values using dot notation
let authorName = document.frontmatter.getValue(forKey: "author.name") as? String
let twitter = document.frontmatter.getValue(forKey: "author.social.twitter") as? String
```

## Next Steps

Learn how to perform CRUD operations on frontmatter:

- <doc:CRUDOperations> - Complete guide to reading, writing, and updating frontmatter

## See Also

- ``FrontMatter``
- ``MarkdownDocument``
- <doc:MarkdownDocument>
