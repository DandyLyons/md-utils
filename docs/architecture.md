# Architecture

## Core Library (MarkdownUtilities)

### MarkdownDocument

**Location**: Sources/MarkdownUtilities/MarkdownDocument.swift

Central data structure representing a Markdown document:
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

## CLI Tool (md-utils)

### Entry Point

**Location**: Sources/md-utils/CLIEntry.swift

- Uses swift-argument-parser
- Main command: `md-utils`
- Conforms to `AsyncParsableCommand` to support async subcommands
- Subcommands defined in Sources/md-utils/Commands/

### Current Subcommands

- `toc` (GenerateTOC) - Generate table of contents for Markdown files
- `fm` (FrontMatterCommands) - Manipulate YAML frontmatter with CRUD operations
  - `fm get` - Retrieve frontmatter value by key
  - `fm set` - Set/update frontmatter value by key
  - `fm has` - Check if frontmatter key exists
  - `fm remove` - Delete frontmatter key
  - `fm rename` - Rename frontmatter key
  - `fm list` - List all frontmatter keys
  - `fm dump` - Dump entire frontmatter in specified format (JSON, YAML, raw, plist)
- `meta` (FileMetadataCommands) - Read file metadata including standard and extended attributes
  - `meta read` - Read metadata from files with multiple output formats
- `convert` (ConvertCommands) - Convert Markdown to other formats
  - `convert to-text` - Convert Markdown to plain text

### CLI Default Behavior

By default, CLI commands performed on a directory:
1. Process recursively (opt-out with `--non-recursive` or `--nr`)
2. Ignore hidden files/directories starting with dot (opt-in with `--include-hidden` or `--ih`)

## Implemented Features

### 1. Front Matter Parsing ✅

YAML frontmatter separated and parsed into structured data.

### 2. Markdown AST Parsing ✅

Body text parsed into Abstract Syntax Tree for programmatic manipulation.

### 3. Table of Contents Generation ✅

- **Library**: `TOCGenerator`, `TOCRenderer`, `TOCEntry`, `TableOfContents`
- **CLI**: `md-utils toc` command
- Supports hierarchical and flat structures
- Multiple output formats: Markdown, JSON, plain text, HTML
- Configurable heading levels, slug generation

### 4. Frontmatter Manipulation ⚠️ (Work in Progress)

Basic CRUD operations implemented, advanced features in progress:

- **Library**: `MarkdownDocument+FrontMatterMutation` extension with `getValue`, `setValue`, `hasKey`, `removeValue`
- **Format conversion**: `YAMLConversion` utilities for JSON, YAML, and PropertyList output
- **CLI**: `md-utils fm` command with subcommands `get`, `set`, `has`, `remove`, `rename`, `list`, `dump`
- **Dump Feature**: Output entire frontmatter in multiple formats
  - Formats: JSON (default), YAML, raw, PropertyList (XML)
  - Single file: direct output without wrapper
  - Multiple files: cat-style headers (==> path <==) with separation
  - Optional YAML delimiters (---) via `--include-delimiters`
  - Alias: `fm d` for quick access
- Works on single files or batch operations across directories
- Preserves body content and existing frontmatter structure
- Idempotent operations (remove non-existent key is safe)

**Planned enhancements from FrontRange:**
- More advanced batch operations
- Additional structured data extraction capabilities

### 5. Format Conversion ✅

Convert Markdown to other formats with extensible protocol-based architecture.

**Plain Text Conversion:**
- **Library**: `PlainTextConverter`, `PlainTextOptions`, `PhrasingContentTextExtractor`, `BlockContentTextExtractor`
- **API**: `MarkdownDocument.toPlainText(options:)` method
- **CLI**: `md-utils convert to-text` command
- Configurable block spacing, list indentation, code block preservation
- Optional frontmatter inclusion
- Batch processing with recursive directory support

**Extensible Infrastructure:**
- Core protocols: `MarkdownConverter`, `MarkdownGenerator`, `ConversionOptions`
- Reusable text extraction utilities for phrasing and block content
- Ready for HTML, RTF, XML converters

### 6. File Metadata Reading ✅

Read file metadata including standard attributes and extended attributes.

**Library**: `FileMetadataReader`, `FileMetadata`, `ExtendedAttributes`, `FileMetadataError`
- `FileMetadataReader.readMetadata(at:includeExtendedAttributes:)` - Read all metadata from a file
- `FileMetadata` - Sendable, Codable struct containing file information
- Platform-specific extended attributes support (Darwin/macOS via `listxattr`/`getxattr`)
- Graceful degradation on platforms without xattr support

**CLI**: `md-utils meta read` command
- Multiple output formats: `json-pretty` (default), `json`, `md-table`, `csv`
- Extended attributes included by default, opt-out with `--exclude-xattr`
- Extended attribute errors reported to user with `--ignore-xattr-errors` flag
- Batch processing with recursive directory support
- CSV format with proper RFC 4180 escaping

**Metadata Available**:
- Standard: size, creation/modification/access dates, POSIX permissions, owner/group accounts
- Extended attributes (xattr) on supported platforms
- File type detection (regular file, directory, symbolic link)

## Planned Features

The following features are documented in README but **NOT YET IMPLEMENTED**:

1. **Heading Manipulation** - Promote/demote headings while maintaining structure (AST foundation ready)
2. **Section Operations** - Reorder, extract, inject sections (AST foundation ready)
3. **Content Selection** - Select by heading or line range (AST foundation ready)
4. **Validation** - Link validation, Markdown flavor compliance (AST foundation ready)
5. **Additional Format Conversions** - HTML, RTF, XML (infrastructure ready, plain text implemented)
6. **File Metadata Writing** - Write/update file metadata (read operations implemented)

## Dependencies

### Current Dependencies

- **MarkdownSyntax** (1.3.0+) - Swift Markdown parsing and syntax tree
- **swift-parsing** (0.14.1+) - Parser combinators
- **swift-argument-parser** (1.6.1+) - CLI argument parsing
- **PathKit** (1.0.1+) - File path handling
- **Yams** (6.1.0+) - YAML parsing and serialization

### Transitive Dependencies

- **swift-case-paths** - Case path utilities (from swift-parsing)
- **xctest-dynamic-overlay** - Testing utilities (from swift-parsing)
- **swift-cmark** - CommonMark C library (from MarkdownSyntax)

## Project Structure

```
md-utils/
├── .gitignore
├── Package.swift
├── README
├── CLAUDE.md
├── docs/                          # Documentation
│   ├── architecture.md
│   ├── testing-standards.md
│   ├── swift-coding-standards.md
│   ├── cli-patterns.md
│   └── development-workflow.md
├── Sources/
│   ├── MarkdownUtilities/         # Core library
│   │   ├── MarkdownDocument.swift
│   │   ├── FrontMatter/
│   │   │   ├── FrontMatterParser.swift
│   │   │   ├── YAMLConversion.swift
│   │   │   ├── MarkdownDocument+FrontMatter.swift
│   │   │   └── MarkdownDocument+FrontMatterMutation.swift
│   │   ├── TOC/
│   │   │   ├── TOCEntry.swift
│   │   │   ├── TableOfContents.swift
│   │   │   ├── HeadingTextExtractor.swift
│   │   │   ├── TOCGenerator.swift
│   │   │   ├── TOCRenderer.swift
│   │   │   └── MarkdownDocument+TOC.swift
│   │   ├── FormatConversion/
│   │   │   ├── Protocols/
│   │   │   │   ├── FormatConverter.swift
│   │   │   │   └── ConversionOptions.swift
│   │   │   ├── Shared/
│   │   │   │   ├── PhrasingContentTextExtractor.swift
│   │   │   │   └── BlockContentTextExtractor.swift
│   │   │   ├── PlainText/
│   │   │   │   ├── PlainTextOptions.swift
│   │   │   │   └── PlainTextConverter.swift
│   │   │   └── MarkdownDocument+FormatConversion.swift
│   │   └── FileMetadata/
│   │       ├── FileMetadata.swift
│   │       ├── FileMetadataReader.swift
│   │       ├── FileMetadataError.swift
│   │       └── ExtendedAttributes.swift
│   └── md-utils/                  # CLI tool
│       ├── CLIEntry.swift
│       ├── GlobalOptions.swift
│       ├── OutputFormat.swift
│       ├── Commands/
│       │   └── GenerateTOC.swift
│       ├── FrontMatterCommands/
│       │   ├── FrontMatterCommands.swift
│       │   ├── Get.swift
│       │   ├── Set.swift
│       │   ├── Has.swift
│       │   ├── Remove.swift
│       │   ├── Rename.swift
│       │   ├── List.swift
│       │   └── Dump.swift
│       ├── ConvertCommands/
│       │   ├── ConvertCommands.swift
│       │   └── ToText.swift
│       └── FileMetadataCommands/
│           ├── FileMetadataCommands.swift
│           └── ReadMetadata.swift
└── Tests/
    ├── MarkdownUtilitiesTests/
    │   ├── MarkdownDocumentTests.swift
    │   ├── MarkdownASTTests.swift
    │   ├── FrontMatter/
    │   │   ├── FrontMatterParsingTests.swift
    │   │   ├── FrontMatterSeparationTests.swift
    │   │   ├── FrontMatterEdgeCasesTests.swift
    │   │   └── FrontMatterMutationTests.swift
    │   ├── TOC/
    │   │   ├── TOCEntryTests.swift
    │   │   ├── TableOfContentsTests.swift
    │   │   ├── HeadingTextExtractorTests.swift
    │   │   ├── TOCGeneratorTests.swift
    │   │   └── TOCRendererTests.swift
    │   ├── FormatConversion/
    │   │   ├── Shared/
    │   │   │   ├── PhrasingContentTextExtractorTests.swift
    │   │   │   └── BlockContentTextExtractorTests.swift
    │   │   └── PlainText/
    │   │       └── PlainTextConverterTests.swift
    │   └── FileMetadata/
    │       ├── FileMetadataTests.swift
    │       ├── FileMetadataReaderTests.swift
    │       └── ExtendedAttributesTests.swift
    └── md-utilsTests/
        ├── CLIEntryTests.swift
        └── Commands/
            ├── FrontMatterCommandsTests.swift
            └── FileMetadataCommandsTests.swift
```

## Naming Conventions

### Types and Structs
- **MarkdownDocument** - Core data type (singular, descriptive)
- **CLIEntry** - CLI entry point (NOT MarkdownUtilitiesEntry)

### Test Files
- Match the file they're testing with "Tests" suffix
- Example: `MarkdownDocument.swift` → `MarkdownDocumentTests.swift`

## Related Projects

**FrontRange** - Sister project for YAML front matter operations
- Repository: https://github.com/DandyLyons/FrontRange
- Local: /Users/daniellyons/Developer/MySwiftPackages/FrontRange
- md-utils will eventually incorporate FrontRange functionality
- FrontRange will eventually be obsoleted by this project
