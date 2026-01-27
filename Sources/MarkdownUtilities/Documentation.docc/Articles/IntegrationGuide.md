# Integration Guide

Detailed instructions for integrating MarkdownUtilities into your project.

## Overview

This guide covers everything you need to know about adding MarkdownUtilities to your Swift project, including platform requirements, dependency configuration, and common integration patterns.

## Requirements

MarkdownUtilities has the following requirements:

- **Swift**: 6.2 or later
- **macOS**: 13.0 or later
- **iOS**: 16.0 or later
- **tvOS**: 16.0 or later
- **watchOS**: 9.0 or later
- **Package Manager**: Swift Package Manager (SPM)

## Adding the Dependency

### For Applications

Add MarkdownUtilities to your app's Package.swift dependencies:

```swift
// Package.swift
let package = Package(
    name: "MyApp",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    dependencies: [
        .package(url: "https://github.com/yourusername/md-utils.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "MarkdownUtilities", package: "md-utils")
            ]
        )
    ]
)
```

### For Libraries

If you're building a library that uses MarkdownUtilities:

```swift
// Package.swift
let package = Package(
    name: "MyLibrary",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "MyLibrary", targets: ["MyLibrary"])
    ],
    dependencies: [
        .package(url: "https://github.com/yourusername/md-utils.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MyLibrary",
            dependencies: [
                .product(name: "MarkdownUtilities", package: "md-utils")
            ]
        )
    ]
)
```

### For Xcode Projects

1. Open your project in Xcode
2. Go to File → Add Package Dependencies...
3. Enter the repository URL: `https://github.com/yourusername/md-utils.git`
4. Choose the version requirements
5. Select "MarkdownUtilities" from the available products
6. Add it to your target

## Importing the Module

Import MarkdownUtilities in your Swift files:

```swift
import MarkdownUtilities

// Now you can use MarkdownDocument and other types
let document = MarkdownDocument(content: "# Hello")
```

## Common Integration Patterns

### File-Based Processing

Read Markdown files from disk and process them:

```swift
import Foundation
import MarkdownUtilities

func processMarkdownFile(at url: URL) throws {
    // Read file content
    let content = try String(contentsOf: url, encoding: .utf8)

    // Parse as Markdown document
    var document = MarkdownDocument(content: content)

    // Modify frontmatter
    try document.frontmatter.setValue(Date(), forKey: "processed")

    // Write back to file
    try document.content.write(to: url, atomically: true, encoding: .utf8)
}
```

### Directory Scanning

Process all Markdown files in a directory:

```swift
import Foundation
import MarkdownUtilities

func processDirectory(at url: URL) throws {
    let fileManager = FileManager.default

    guard let enumerator = fileManager.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return
    }

    for case let fileURL as URL in enumerator {
        // Check if it's a Markdown file
        guard fileURL.pathExtension == "md" else { continue }

        // Process the file
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let document = MarkdownDocument(content: content)

        // Your processing logic here
        print("Processing: \(fileURL.lastPathComponent)")
    }
}
```

### Stream Processing

Process Markdown content from streams or APIs:

```swift
import MarkdownUtilities

func processMarkdownFromAPI(content: String) -> String {
    var document = MarkdownDocument(content: content)

    // Extract plain text for preview
    let preview = String(document.toPlainText().prefix(200))

    // Return preview
    return preview + "..."
}
```

### Validation

Validate Markdown documents for required frontmatter:

```swift
import MarkdownUtilities

struct ValidationError: Error {
    let message: String
}

func validateBlogPost(_ document: MarkdownDocument) throws {
    // Check required fields
    let requiredFields = ["title", "date", "author"]

    for field in requiredFields {
        guard document.frontmatter.hasKey(field) else {
            throw ValidationError(message: "Missing required field: \(field)")
        }
    }

    // Validate title is not empty
    if let title = document.frontmatter.getValue(forKey: "title") as? String,
       title.trimmingCharacters(in: .whitespaces).isEmpty {
        throw ValidationError(message: "Title cannot be empty")
    }

    print("✓ Document is valid")
}
```

### Batch Processing

Process multiple documents with error handling:

```swift
import MarkdownUtilities

func batchProcess(files: [URL]) {
    var successCount = 0
    var errors: [(URL, Error)] = []

    for fileURL in files {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            var document = MarkdownDocument(content: content)

            // Process document
            try document.frontmatter.setValue(Date(), forKey: "updated")

            // Save
            try document.content.write(to: fileURL, atomically: true, encoding: .utf8)
            successCount += 1

        } catch {
            errors.append((fileURL, error))
        }
    }

    print("Processed \(successCount) files successfully")
    if !errors.isEmpty {
        print("Errors: \(errors.count)")
        for (url, error) in errors {
            print("  - \(url.lastPathComponent): \(error)")
        }
    }
}
```

## Platform Considerations

### macOS

MarkdownUtilities works great for:
- Static site generators
- Documentation tools
- Content management systems
- Markdown editors

### iOS/iPadOS

Ideal for:
- Note-taking apps
- Markdown editors
- Blog writing apps
- Documentation viewers

### tvOS and watchOS

While supported, MarkdownUtilities is primarily designed for macOS and iOS. Consider the limited storage and processing capabilities of these platforms.

## Performance Tips

For optimal performance when processing large numbers of files:

1. **Minimize parsing**: Cache ``MarkdownDocument`` instances when possible
2. **Batch operations**: Group file operations to reduce I/O overhead
3. **Selective processing**: Only parse the parts you need (frontmatter vs full AST)
4. **Use generators**: For TOC generation, use appropriate level filters

## Next Steps

- <doc:GettingStarted> - Quick start guide
- <doc:MarkdownDocument> - Learn about the core type
- <doc:FrontMatter/CRUDOperations> - Master frontmatter operations

## See Also

- ``MarkdownDocument``
- ``FrontMatter``
