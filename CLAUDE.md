# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

md-utils is a Swift package for parsing and manipulating Markdown files. It provides:

1. **MarkdownUtilities Library** - Core library for working with Markdown content
2. **md-utils CLI** - Command-line tool for performing operations on Markdown files
3. **markdown-utilities Agent Skill** - [PLANNED] Claude Code skill for instructing LLMs to use md-utils

## Status

This project is in **early development**. The initial SPM scaffolding is complete, but most features are yet to be implemented.

## Requirements

- **Swift 6.2** or later (as defined in Package.swift)
- **Architecture**: Swift 6 with native Swift Testing framework

## Build and Test Commands

```bash
# Build the entire package
swift build

# Build specific targets
swift build --target MarkdownUtilities
swift build --target md-utils

# Run tests
swift test

# Run tests for specific targets
swift test --filter MarkdownUtilitiesTests
swift test --filter md-utilsTests

# Run the CLI tool in development
swift run md-utils <command>
swift run md-utils --help
```

## Architecture

### Core Library (MarkdownUtilities)

**`MarkdownDocument`** (Sources/MarkdownUtilities/MarkdownDocument.swift)
- Central data structure representing a Markdown document
- Separates YAML frontmatter from body content
- Frontmatter parsed into `Yams.Node.Mapping` for structured access
- Body available as `String` for text processing
- Supports parsing body into Markdown AST via `parseAST()` method
- AST parsing uses MarkdownSyntax library returning `Root` structure

**Frontmatter Handling:**
- Uses `FrontMatterParser` to separate `---` delimited YAML frontmatter
- Frontmatter parsed into `Yams.Node.Mapping` during initialization
- Gracefully handles documents with no frontmatter (empty mapping)

**Markdown AST Parsing:**
MarkdownDocument supports parsing body text into a Markdown AST using the MarkdownSyntax library:
- AST parsing via `parseAST()` method (async throws)
- Returns `Root` structure containing parsed AST
- Parses fresh each time - no caching
- User can store returned AST if needed

Example:
```swift
let doc = try MarkdownDocument(content: markdownText)
let ast = try await doc.parseAST()

if let heading = ast.children.first as? Heading {
  print("First heading level: \(heading.depth)")
}
```

### CLI Tool (md-utils)

**Entry Point** (Sources/md-utils/CLIEntry.swift)
- Uses swift-argument-parser
- Main command: `md-utils`
- Conforms to `AsyncParsableCommand` to support async subcommands
- Subcommands defined in Sources/md-utils/Commands/

**Current Subcommands:**
- `toc` (GenerateTOC) - Generate table of contents for Markdown files

**CLI Pattern** (Following FrontRange)
- Each subcommand is a struct conforming to `AsyncParsableCommand`
- Uses `@OptionGroup var options: GlobalOptions` pattern for shared options
- GlobalOptions handles common flags like `--recursive`, `--include-hidden`, `--extensions`

### Implemented Features

1. **Front Matter Parsing** - YAML frontmatter separated and parsed into structured data
2. **Markdown AST Parsing** - Body text parsed into Abstract Syntax Tree for programmatic manipulation
3. **Table of Contents Generation** - Generate TOC for Markdown files with multiple output formats
   - Library: `TOCGenerator`, `TOCRenderer`, `TOCEntry`, `TableOfContents`
   - CLI: `md-utils toc` command
   - Supports hierarchical and flat structures
   - Multiple output formats: Markdown, JSON, plain text, HTML
   - Configurable heading levels, slug generation

### Planned Features (from README)

The following features are documented in README but **NOT YET IMPLEMENTED**:

1. **Heading Manipulation** - Promote/demote headings while maintaining structure (AST foundation ready)
2. **Section Operations** - Reorder, extract, inject sections (AST foundation ready)
3. **Content Selection** - Select by heading or line range (AST foundation ready)
4. **Validation** - Link validation, Markdown flavor compliance (AST foundation ready)
5. **Format Conversion** - HTML, plain text, rich text, XML (AST foundation ready)
6. **File Metadata** - Read/write file metadata

## Dependencies

### Current Dependencies

- **MarkdownSyntax** (1.3.0+) - Swift Markdown parsing and syntax tree
- **swift-parsing** (0.14.1+) - Parser combinators
- **swift-argument-parser** (1.6.1+) - CLI argument parsing
- **PathKit** (1.0.1+) - File path handling
- **Yams** (6.1.0+) - YAML parsing and serialization

### Transitive Dependencies

These are pulled in by the above packages:
- **swift-case-paths** - Case path utilities (from swift-parsing)
- **xctest-dynamic-overlay** - Testing utilities (from swift-parsing)
- **swift-cmark** - CommonMark C library (from MarkdownSyntax)

## Testing Patterns

### Test Framework: Swift Testing

**IMPORTANT**: This project uses **native Swift Testing framework**, NOT XCTest.

**Test Naming Convention**: Tests MUST use raw identifiers (backticks) for function names:

```swift
@Test
func `Initialize MarkdownDocument with content`() async throws {
  // Test implementation
}
```

**DO NOT** use this pattern:
```swift
// WRONG - Don't do this!
@Test("Initialize MarkdownDocument with content")
func initializeWithContent() async throws {
  // ...
}
```

### Test Structure

- **Suites**: Use `@Suite` with descriptive names
- **Tests**: Use `@Test` with raw identifier function names
- **Assertions**: Use `#expect()` macro (not XCTAssert)
- **Async**: All tests are marked `async throws`
- **Type Checking**: Use `is` keyword for type assertions only
- **Unwrapping Optionals**: Use `try #require()` to unwrap optionals (replaces XCTest's `XCTUnwrap`)

**Unwrapping with #require:**
```swift
// CORRECT - Use #require to unwrap optionals
let heading = try #require(root.children[0] as? Heading)
#expect(heading.depth == .h1)

// WRONG - Don't use optional chaining
let heading = root.children[0] as? Heading
#expect(heading?.depth == .h1)
```

**Type Checking with `is`:**
```swift
// Use `is` when you only need to verify type, not access properties
#expect(root.children[1] is Paragraph)
```

**Example:**
```swift
@Suite("MarkdownDocument Tests")
struct MarkdownDocumentTests {

  @Test
  func `Initialize MarkdownDocument with content`() async throws {
    let content = "# Hello World\n\nThis is a test."
    let doc = try MarkdownDocument(content: content)

    #expect(doc.body == content)
    #expect(doc.frontMatter.isEmpty)
  }

  @Test
  func `Parse markdown AST`() async throws {
    let content = "# Hello\n\nParagraph text."
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 2)
    let heading = try #require(root.children[0] as? Heading)
    #expect(heading.depth == .h1)
  }
}
```

### CLI Testing

When CLI functionality is implemented:
- Will likely follow FrontRange pattern using Command library
- Test helpers will go in Tests/md-utilsTests/CLI Test Helpers.swift
- Temporary file creation utilities for integration tests

### Test Files

- No `.xctestplan` files - those are Xcode-specific
- Simple directory structure: Tests/[TargetName]Tests/
- Test files use suffix: `*Tests.swift`

## Project Structure

```
md-utils/
├── .gitignore                     # Standard Swift package ignores
├── Package.swift                  # Package manifest
├── README                         # Project documentation
├── CLAUDE.md                      # This file (SOP for Claude Code)
├── Sources/
│   ├── MarkdownUtilities/         # Core library
│   │   ├── MarkdownDocument.swift
│   │   ├── FrontMatter/           # Frontmatter parsing
│   │   │   ├── FrontMatterParser.swift
│   │   │   ├── YAMLConversion.swift
│   │   │   └── MarkdownDocument+FrontMatter.swift
│   │   └── TOC/                   # Table of contents generation
│   │       ├── TOCEntry.swift
│   │       ├── TableOfContents.swift
│   │       ├── HeadingTextExtractor.swift
│   │       ├── TOCGenerator.swift
│   │       ├── TOCRenderer.swift
│   │       └── MarkdownDocument+TOC.swift
│   └── md-utils/                  # CLI tool
│       ├── CLIEntry.swift
│       ├── GlobalOptions.swift
│       └── Commands/
│           └── GenerateTOC.swift
└── Tests/
    ├── MarkdownUtilitiesTests/    # Library tests
    │   ├── MarkdownDocumentTests.swift
    │   ├── MarkdownASTTests.swift
    │   ├── FrontMatter/           # Frontmatter tests
    │   │   ├── FrontMatterParsingTests.swift
    │   │   ├── FrontMatterSeparationTests.swift
    │   │   └── FrontMatterEdgeCasesTests.swift
    │   └── TOC/                   # TOC tests
    │       ├── TOCEntryTests.swift
    │       ├── TableOfContentsTests.swift
    │       ├── HeadingTextExtractorTests.swift
    │       ├── TOCGeneratorTests.swift
    │       └── TOCRendererTests.swift
    └── md-utilsTests/             # CLI tests
        └── CLIEntryTests.swift
```

## Naming Conventions

### Types and Structs
- **MarkdownDocument** - Core data type (singular, descriptive)
- **CLIEntry** - CLI entry point (NOT MarkdownUtilitiesEntry)

### Test Files
- Match the file they're testing with "Tests" suffix
- Example: `MarkdownDocument.swift` → `MarkdownDocumentTests.swift`

### Test Functions
- Use raw identifiers (backticks)
- Descriptive, sentence-like names
- Example: `` func `Initialize MarkdownDocument with content`() ``

## Key Patterns and Conventions

1. **Swift 6 Language Mode**: All code uses Swift 6 features and strict concurrency
2. **Test Pattern**: Native Swift Testing with raw identifier function names
3. **CLI Pattern**: SwiftArgumentParser with `ParsableCommand` protocol
4. **Minimal Scaffolding**: Current implementation is intentionally minimal - just establishes architecture
5. **Future-Ready**: Structure mirrors FrontRange for easy feature addition
6. **Recursive File Processing By Default in `md-utils` CLI**: By default, CLI commands performed on a directory are: 
   1. recursive by default: opt-out recursive processing with `--non-recursive` or `--nr` flag
   2. ignores hidden files and directories (those starting with a dot) by default: opt-in to processing hidden files with `--include-hidden` or `--ih` flag

## Development Workflow

### Adding New Features

When adding new features:
1. Start with library implementation in MarkdownUtilities
2. Add comprehensive tests using Swift Testing
3. Add CLI command in md-utils (if user-facing)
4. Update this CLAUDE.md with architectural notes

### Adding CLI Commands

Pattern to follow (based on FrontRange):
1. Create Sources/md-utils/Commands/ directory (when needed)
2. Each command is a struct conforming to `ParsableCommand`
3. Use `@OptionGroup var options: GlobalOptions` for shared options
4. Register in CLIEntry.configuration.subcommands array

### Before Committing

1. Run `swift build` - ensure clean build
2. Run `swift test` - all tests must pass
3. Verify CLI: `swift run md-utils --help`
4. Update CLAUDE.md if architecture changes

## Related Projects

- **FrontRange** - Sister project for YAML front matter operations
  - Repository: https://github.com/DandyLyons/FrontRange
  - Local: /Users/daniellyons/Developer/MySwiftPackages/FrontRange
  - md-utils will eventually port functionality from FrontRange into this project.
    - FrontRange will eventually be obsoleted by this project.

## Future Integration Points

### Front Matter Support (Planned)

md-utils will integrate FrontRange to provide comprehensive front matter handling:
- CRUD operations on YAML front matter
- Batch operations across files
- Structured data extraction
- All FrontRange features available in Markdown context

When implementing:
- Add FrontRange as dependency in Package.swift
- Extend MarkdownDocument to include front matter parsing
- Add CLI commands for front matter operations
- Follow FrontRange patterns for consistency

### Agent Skill (Not Yet Implemented)

The `markdown-utilities` agent skill is planned but not yet started:
- Will instruct LLMs to use md-utils CLI
- Pattern will follow FrontRange's agent skill implementation
- Location: TBD (likely separate repository or skill directory)

## Notes for Claude Code

- **Read before implementing**: Always check README for intended features
- **Follow FrontRange patterns**: When in doubt, check how FrontRange solves similar problems
- **Test naming is strict**: Use raw identifiers for all test function names
- **No XCTest**: This project uses Swift Testing framework exclusively
- **Early stage**: Most features are placeholders - implementation needed
- **Swift 6**: Use modern Swift features, strict concurrency, async/await
