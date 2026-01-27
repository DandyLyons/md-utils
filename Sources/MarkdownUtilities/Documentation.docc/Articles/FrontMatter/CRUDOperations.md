# Frontmatter CRUD Operations

Complete guide to creating, reading, updating, and deleting frontmatter.

## Overview

The ``FrontMatter`` type provides a complete set of CRUD (Create, Read, Update, Delete) operations for managing YAML metadata in Markdown documents. This guide covers all operations with comprehensive examples and error handling patterns.

## Reading Values

### Basic Reading

Get a value from frontmatter using `getValue(forKey:)`:

```swift
let document = MarkdownDocument(content: markdown)

// Get a string value
if let title = document.frontmatter.getValue(forKey: "title") as? String {
    print("Title: \(title)")
}

// Get a number
if let count = document.frontmatter.getValue(forKey: "count") as? Int {
    print("Count: \(count)")
}

// Get a boolean
if let published = document.frontmatter.getValue(forKey: "published") as? Bool {
    print("Published: \(published)")
}

// Get an array
if let tags = document.frontmatter.getValue(forKey: "tags") as? [String] {
    print("Tags: \(tags)")
}
```

### Checking for Keys

Use `hasKey(_:)` to check if a key exists:

```swift
let frontmatter = document.frontmatter

if frontmatter.hasKey("author") {
    print("Document has an author")
}

// Check before accessing
if frontmatter.hasKey("date") {
    let date = frontmatter.getValue(forKey: "date")
    // Process date
}
```

### Type-Safe Reading

Always cast to the expected type and handle type mismatches:

```swift
// Safe approach with guard
guard let title = document.frontmatter.getValue(forKey: "title") as? String else {
    print("Title is missing or not a string")
    return
}

// Safe approach with if-let
if let tags = document.frontmatter.getValue(forKey: "tags") as? [String] {
    print("Tags: \(tags.joined(separator: ", "))")
} else {
    print("No tags found or invalid format")
}

// With default values
let author = document.frontmatter.getValue(forKey: "author") as? String ?? "Unknown"
let wordCount = document.frontmatter.getValue(forKey: "wordCount") as? Int ?? 0
```

### Reading Nested Values

Access nested properties using dot notation:

```swift
// Frontmatter:
// author:
//   name: Jane Doe
//   email: jane@example.com

let authorName = document.frontmatter.getValue(forKey: "author.name") as? String
let authorEmail = document.frontmatter.getValue(forKey: "author.email") as? String

if let name = authorName, let email = authorEmail {
    print("\(name) <\(email)>")
}
```

## Writing Values

### Setting Values

Use `setValue(_:forKey:)` to add or update values:

```swift
var document = MarkdownDocument(content: markdown)

// Set a string
try document.frontmatter.setValue("My Title", forKey: "title")

// Set a number
try document.frontmatter.setValue(42, forKey: "count")

// Set a boolean
try document.frontmatter.setValue(true, forKey: "published")

// Set an array
try document.frontmatter.setValue(["swift", "programming"], forKey: "tags")

// Set a date
try document.frontmatter.setValue(Date(), forKey: "updated")

// Get the modified document
let updatedMarkdown = document.content
```

> Important: `setValue(_:forKey:)` can throw errors. Always use try and handle potential failures.

### Setting Multiple Values

Set multiple values efficiently:

```swift
var document = MarkdownDocument(content: markdown)

do {
    try document.frontmatter.setValue("New Title", forKey: "title")
    try document.frontmatter.setValue("Jane Doe", forKey: "author")
    try document.frontmatter.setValue(Date(), forKey: "updated")
    try document.frontmatter.setValue(true, forKey: "published")

    // Save the modified document
    let updatedContent = document.content
    try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)

} catch {
    print("Error updating frontmatter: \(error)")
}
```

### Setting Nested Values

Create nested structures:

```swift
var document = MarkdownDocument(content: markdown)

// Set nested author information
try document.frontmatter.setValue("Jane Doe", forKey: "author.name")
try document.frontmatter.setValue("jane@example.com", forKey: "author.email")
try document.frontmatter.setValue("@janedoe", forKey: "author.twitter")

// Results in:
// author:
//   name: Jane Doe
//   email: jane@example.com
//   twitter: "@janedoe"
```

### Type Considerations

MarkdownUtilities supports standard Swift types:

```swift
// Strings
try document.frontmatter.setValue("text", forKey: "key")

// Numbers
try document.frontmatter.setValue(42, forKey: "count")
try document.frontmatter.setValue(3.14, forKey: "pi")

// Booleans
try document.frontmatter.setValue(true, forKey: "flag")

// Arrays
try document.frontmatter.setValue([1, 2, 3], forKey: "numbers")
try document.frontmatter.setValue(["a", "b"], forKey: "letters")

// Dates (converted to ISO 8601)
try document.frontmatter.setValue(Date(), forKey: "timestamp")

// Dictionaries
try document.frontmatter.setValue(
    ["name": "Jane", "age": 30],
    forKey: "person"
)
```

## Updating Values

### Conditional Updates

Update values only if they don't exist or meet certain criteria:

```swift
var document = MarkdownDocument(content: markdown)

// Set default value if missing
if !document.frontmatter.hasKey("draft") {
    try document.frontmatter.setValue(true, forKey: "draft")
}

// Update if different
let currentTitle = document.frontmatter.getValue(forKey: "title") as? String
if currentTitle != "New Title" {
    try document.frontmatter.setValue("New Title", forKey: "title")
}

// Update timestamp
try document.frontmatter.setValue(Date(), forKey: "modified")
```

### Batch Updates

Update multiple documents:

```swift
func updateAllDocuments(in directory: URL) throws {
    let fileManager = FileManager.default
    let files = try fileManager.contentsOfDirectory(at: directory,
        includingPropertiesForKeys: nil)

    for fileURL in files where fileURL.pathExtension == "md" {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var document = MarkdownDocument(content: content)

        // Update frontmatter
        try document.frontmatter.setValue(Date(), forKey: "updated")
        try document.frontmatter.setValue("batch-update", forKey: "processedBy")

        // Save
        try document.content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
```

### Transforming Values

Read, transform, and write back:

```swift
var document = MarkdownDocument(content: markdown)

// Append to existing array
if var tags = document.frontmatter.getValue(forKey: "tags") as? [String] {
    tags.append("new-tag")
    try document.frontmatter.setValue(tags, forKey: "tags")
}

// Increment counter
if let count = document.frontmatter.getValue(forKey: "count") as? Int {
    try document.frontmatter.setValue(count + 1, forKey: "count")
}

// Convert to uppercase
if let title = document.frontmatter.getValue(forKey: "title") as? String {
    try document.frontmatter.setValue(title.uppercased(), forKey: "title")
}
```

## Deleting Values

### Removing Keys

Use `removeValue(forKey:)` to delete a key:

```swift
var document = MarkdownDocument(content: markdown)

// Remove a single key
try document.frontmatter.removeValue(forKey: "draft")

// Remove multiple keys
let keysToRemove = ["temp", "scratch", "debug"]
for key in keysToRemove {
    if document.frontmatter.hasKey(key) {
        try document.frontmatter.removeValue(forKey: key)
    }
}
```

### Conditional Removal

Remove keys based on conditions:

```swift
var document = MarkdownDocument(content: markdown)

// Remove if value is nil or empty
if let tags = document.frontmatter.getValue(forKey: "tags") as? [String],
   tags.isEmpty {
    try document.frontmatter.removeValue(forKey: "tags")
}

// Remove deprecated fields
let deprecatedFields = ["old_field", "legacy_property"]
for field in deprecatedFields {
    if document.frontmatter.hasKey(field) {
        try document.frontmatter.removeValue(forKey: field)
    }
}
```

## Renaming Keys

### Basic Renaming

Use `renameKey(from:to:)` to rename a key:

```swift
var document = MarkdownDocument(content: markdown)

// Rename a key
try document.frontmatter.renameKey(from: "old_name", to: "new_name")

// The value is preserved, only the key changes
```

### Bulk Renaming

Rename multiple keys:

```swift
var document = MarkdownDocument(content: markdown)

let renames = [
    "created_date": "created",
    "modified_date": "modified",
    "post_title": "title"
]

for (oldKey, newKey) in renames {
    if document.frontmatter.hasKey(oldKey) {
        try document.frontmatter.renameKey(from: oldKey, to: newKey)
    }
}
```

### Schema Migration

Migrate from one schema to another:

```swift
func migrateSchema(_ document: inout MarkdownDocument) throws {
    // Rename keys for new schema
    if document.frontmatter.hasKey("tags") {
        try document.frontmatter.renameKey(from: "tags", to: "keywords")
    }

    // Convert string to array
    if let category = document.frontmatter.getValue(forKey: "category") as? String {
        try document.frontmatter.setValue([category], forKey: "categories")
        try document.frontmatter.removeValue(forKey: "category")
    }

    // Add version field
    try document.frontmatter.setValue(2, forKey: "schema_version")
}
```

## Error Handling

### Handling Errors Gracefully

CRUD operations can fail for various reasons:

```swift
var document = MarkdownDocument(content: markdown)

do {
    try document.frontmatter.setValue("value", forKey: "key")
} catch {
    print("Failed to set value: \(error.localizedDescription)")
}

// More specific error handling
do {
    try document.frontmatter.setValue(complexValue, forKey: "key")
} catch let error as FrontMatterError {
    // Handle specific frontmatter errors
    print("Frontmatter error: \(error)")
} catch {
    // Handle other errors
    print("Unexpected error: \(error)")
}
```

### Validation Before Writing

Validate values before setting:

```swift
func setTitle(_ title: String, for document: inout MarkdownDocument) throws {
    // Validate
    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw ValidationError.emptyTitle
    }

    guard title.count <= 200 else {
        throw ValidationError.titleTooLong
    }

    // Set if valid
    try document.frontmatter.setValue(title, forKey: "title")
}
```

## Complete CRUD Example

Here's a comprehensive example demonstrating all operations:

```swift
import Foundation
import MarkdownUtilities

// Read a Markdown file
let fileURL = URL(fileURLWithPath: "post.md")
let content = try String(contentsOf: fileURL, encoding: .utf8)
var document = MarkdownDocument(content: content)

// READ operations
print("Current title:", document.frontmatter.getValue(forKey: "title") as? String ?? "None")

if document.frontmatter.hasKey("tags") {
    let tags = document.frontmatter.getValue(forKey: "tags") as? [String] ?? []
    print("Tags:", tags)
}

// CREATE/UPDATE operations
try document.frontmatter.setValue("Updated Title", forKey: "title")
try document.frontmatter.setValue(Date(), forKey: "modified")

// Add new field if missing
if !document.frontmatter.hasKey("author") {
    try document.frontmatter.setValue("Jane Doe", forKey: "author")
}

// Update existing array
if var tags = document.frontmatter.getValue(forKey: "tags") as? [String] {
    tags.append("updated")
    try document.frontmatter.setValue(tags, forKey: "tags")
}

// RENAME operation
if document.frontmatter.hasKey("created_date") {
    try document.frontmatter.renameKey(from: "created_date", to: "created")
}

// DELETE operation
if document.frontmatter.hasKey("draft") {
    let isDraft = document.frontmatter.getValue(forKey: "draft") as? Bool ?? false
    if !isDraft {
        try document.frontmatter.removeValue(forKey: "draft")
    }
}

// Write back to file
try document.content.write(to: fileURL, atomically: true, encoding: .utf8)
print("✓ Document updated successfully")
```

## Best Practices

1. **Always handle errors**: Use do-catch blocks for all CRUD operations
2. **Validate input**: Check values before setting them
3. **Check key existence**: Use `hasKey(_:)` before accessing or removing
4. **Use type-safe casting**: Always cast `getValue` results to expected types
5. **Preserve data integrity**: Make backups before batch operations
6. **Document your schema**: Define expected frontmatter fields clearly

## See Also

- ``FrontMatter``
- ``MarkdownDocument``
- <doc:FrontMatterOverview>
- <doc:MarkdownDocument>
