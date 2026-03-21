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

- `body` / `b` (Body) - Extract body content without frontmatter
- `convert` (ConvertCommands) - Convert Markdown to other formats
  - `convert to-text` - Convert Markdown to plain text
  - `convert to-csv` - Convert Markdown to CSV
- `extract` (ExtractSection) - Extract a section from Markdown files by name or index
- `frontmatter` / `fm` (FrontMatterCommands) - Manipulate YAML frontmatter
  - `fm get` - Retrieve frontmatter value by key
  - `fm set` - Set/update frontmatter value by key
  - `fm has` - Check if frontmatter key exists
  - `fm remove` - Delete frontmatter key
  - `fm rename` - Rename frontmatter key
  - `fm replace` / `fm r` - Replace entire frontmatter with new data
  - `fm list` - List all frontmatter keys
  - `fm dump` - Dump entire frontmatter in specified format (JSON, YAML, raw, plist)
  - `fm search` - Search for files matching a JMESPath query
  - `fm sort-keys` / `fm sk` - Sort frontmatter keys
  - `fm touch` - Add frontmatter keys without values
  - `fm array` - Array manipulation commands:
    - `fm array append` - Append value to array
    - `fm array contains` - Check if array contains value
    - `fm array prepend` - Prepend value to array
    - `fm array remove` - Remove value from array
- `headings` (HeadingCommands) - Manipulate heading levels
  - `headings promote` - Promote heading levels (e.g. h2 → h1)
  - `headings demote` - Demote heading levels (e.g. h1 → h2)
- `lines` / `l` (Lines) - Extract a range of lines from a file
- `links` / `ln` (LinkCommands) - Analyze wikilinks in Markdown files
  - `links list` / `ls` - List wikilinks with resolution status
  - `links check` - Check for broken or ambiguous wikilinks (exits with failure if any found)
  - `links backlinks` / `bl` - Find files that link to a given target
- `meta` (FileMetadataCommands) - Read file metadata including standard and extended attributes
  - `meta read` - Read metadata from files with multiple output formats
- `section` / `sect` (SectionCommands) - Manipulate sections in Markdown documents
  - `section move-up` - Move a section up among siblings
  - `section move-down` - Move a section down among siblings
  - `section move-to` - Move a section to a specific position
- `table-of-contents` / `toc` (GenerateTOC) - Generate table of contents for Markdown files

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

### 4. Frontmatter Manipulation ✅

Full CRUD operations plus advanced features:

- **Library**: `MarkdownDocument+FrontMatterMutation` extension with `getValue`, `setValue`, `hasKey`, `removeValue`
- **Format conversion**: `YAMLConversion` utilities for JSON, YAML, and PropertyList output
- **CLI**: `md-utils frontmatter` (alias `fm`) with subcommands:
  - Basic CRUD: `get`, `set`, `has`, `remove`, `rename`, `list`, `dump`
  - Advanced: `replace`, `search` (JMESPath queries), `sort-keys`, `touch`
  - Array operations: `array append`, `array contains`, `array prepend`, `array remove`
- **Dump Feature**: Output entire frontmatter in multiple formats
  - Formats: JSON (default), YAML, raw, PropertyList (XML)
  - Single file: direct output without wrapper
  - Multiple files: cat-style headers (==> path <==) with separation
  - Optional YAML delimiters (---) via `--include-delimiters`
  - Alias: `fm d` for quick access
- Works on single files or batch operations across directories
- Preserves body content and existing frontmatter structure
- Idempotent operations (remove non-existent key is safe)

### 5. Format Conversion ✅

Convert Markdown to other formats with extensible protocol-based architecture.

**Plain Text Conversion:**
- **Library**: `PlainTextConverter`, `PlainTextOptions`, `PhrasingContentTextExtractor`, `BlockContentTextExtractor`
- **API**: `MarkdownDocument.toPlainText(options:)` method
- **CLI**: `md-utils convert to-text` command
- Configurable block spacing, list indentation, code block preservation
- Optional frontmatter inclusion
- Batch processing with recursive directory support

**CSV Conversion:**
- **Library**: `CSVConverter`, `CSVOptions`
- **CLI**: `md-utils convert to-csv` command

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

### 7. Wikilink Parsing & Resolution ✅

Parse and resolve Obsidian-flavored wikilinks.

**Parsing (Library)**: `Wikilink`, `WikilinkScanner`, `WikilinkParser`, `WikilinkAnchor`
- `WikilinkScanner.scan(_:)` - Scan text for all wikilinks
- `MarkdownDocument.wikilinks()` - Scan both frontmatter and body
- Supports targets, display text, heading/block anchors, embeds

**Resolution (Library)**: `WikilinkResolver`, `WikilinkResolution`, `ResolvedWikilink`
- `WikilinkResolver(root:)` - Builds a file index from a vault root directory
- Resolution priority: filename match → relative path → absolute path from root
- No-extension targets match only `.md`/`.markdown`; explicit extensions match exactly
- Detects ambiguous matches (multiple files with same stem)

**CLI**: `md-utils links` command group
- `links list` - List all wikilinks with resolution status (plain text or JSON)
- `links check` - Report broken/ambiguous links, exit with failure if any found
- `links backlinks` - Find files that link to given targets

### 8. Heading Manipulation ✅

Promote and demote headings while maintaining document structure.

- **Library**: `HeadingAdjuster`, `HeadingAdjusterError`, `HeadingReconstructor`, `HeadingScope`, `MarkdownDocument+HeadingAdjustment`
- **CLI**: `md-utils headings promote` and `md-utils headings demote`

### 9. Section Operations ✅

Extract and reorder sections in Markdown documents.

- **Extraction Library**: `SectionExtractor`, `SectionBoundaryDetector`, `SectionContent`, `SectionExtractorError`, `MarkdownDocument+SectionExtraction`
- **Reordering Library**: `SectionReorderer`, `SectionReordererError`, `SectionSiblingFinder`, `MarkdownDocument+SectionReordering`
- **CLI**: `md-utils extract` (extract sections), `md-utils section move-up/move-down/move-to` (reorder sections)

### 10. Content Selection ✅

Select content by heading or line range.

- **CLI**: `md-utils body` (extract body without frontmatter), `md-utils lines` (extract line ranges), `md-utils extract` (extract by section)

## Known Limitations

### YAML Comment Loss on Frontmatter Write

**Affects**: all `fm` write commands (`set`, `remove`, `rename`, `replace`, `sort-keys`, `touch`, `array append`, `array prepend`, `array remove`)

YAML comments (lines beginning with `#`) in frontmatter are permanently lost whenever any write operation is performed. This is a fundamental limitation of the YAML parsing stack:

- **Root cause**: Yams is built on libYAML, a streaming event-based parser. libYAML silently discards comment tokens — they never surface as parse events and therefore cannot be stored in `Yams.Node.Mapping` or any downstream structure.
- **No workaround within Yams**: Comments are unrecoverable from the parsed AST regardless of serialization settings.

**Detection**: `MarkdownDocument.containsYAMLComments` is set to `true` at `init(content:)` time if `FrontMatterParser.containsYAMLComments(_:)` finds any comment lines in the raw frontmatter string (before Yams parses it). All write CLI commands emit a warning to stderr when this is true:

```
warning: path/to/file.md: frontmatter contains YAML comments which will be lost
```

**Scope of detection**: The check is intentionally naive — it detects standalone comment lines (where the first non-whitespace character on a line is `#`). It does **not** detect inline comments (`key: value # comment`). This tradeoff avoids false positives on YAML string values that legitimately contain `#` characters (e.g. URLs, hex color codes).

**Possible future fix**: Replace Yams with a YAML library that preserves comments in its AST (uncommon), or implement raw-text frontmatter surgery that avoids a full parse/serialize round-trip.

## Planned Features

The following features are **NOT YET IMPLEMENTED**:

1. **Validation** - Link validation, Markdown flavor compliance (AST foundation ready)
2. **Additional Format Conversions** - HTML, RTF, XML (infrastructure ready, plain text and CSV implemented)
3. **File Metadata Writing** - Write/update file metadata (read operations implemented)

## Dependencies

### Current Dependencies

- **MarkdownSyntax** (1.3.0+) - Swift Markdown parsing and syntax tree
- **swift-parsing** (0.14.1+) - Parser combinators
- **swift-argument-parser** (1.6.1+) - CLI argument parsing
- **PathKit** (1.0.1+) - File path handling
- **Yams** (6.1.0+) - YAML parsing and serialization
- **jmespath.swift** (1.0.3+) - JMESPath query language for JSON (used by `fm search`)

### Transitive Dependencies

- **swift-case-paths** - Case path utilities (from swift-parsing)
- **xctest-dynamic-overlay** - Testing utilities (from swift-parsing)
- **swift-cmark** - CommonMark C library (from MarkdownSyntax)

## Project Structure

```
md-utils/
├── Package.swift
├── CLAUDE.md
├── docs/                          # Documentation
│   ├── architecture.md
│   ├── testing-standards.md
│   ├── swift-coding-standards.md
│   ├── cli-patterns.md
│   ├── common-use-cases.md
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
│   │   │   ├── CSV/
│   │   │   │   ├── CSVConverter.swift
│   │   │   │   └── CSVOptions.swift
│   │   │   └── MarkdownDocument+FormatConversion.swift
│   │   ├── HeadingAdjustment/
│   │   │   ├── HeadingAdjuster.swift
│   │   │   ├── HeadingAdjusterError.swift
│   │   │   ├── HeadingReconstructor.swift
│   │   │   ├── HeadingScope.swift
│   │   │   └── MarkdownDocument+HeadingAdjustment.swift
│   │   ├── SectionExtraction/
│   │   │   ├── SectionExtractor.swift
│   │   │   ├── SectionBoundaryDetector.swift
│   │   │   ├── SectionContent.swift
│   │   │   ├── SectionExtractorError.swift
│   │   │   └── MarkdownDocument+SectionExtraction.swift
│   │   ├── SectionReordering/
│   │   │   ├── SectionReorderer.swift
│   │   │   ├── SectionReordererError.swift
│   │   │   ├── SectionSiblingFinder.swift
│   │   │   └── MarkdownDocument+SectionReordering.swift
│   │   ├── Helpers/
│   │   │   └── LineNumbers.swift
│   │   ├── FileMetadata/
│   │   │   ├── FileMetadata.swift
│   │   │   ├── FileMetadataReader.swift
│   │   │   ├── FileMetadataError.swift
│   │   │   └── ExtendedAttributes.swift
│   │   └── Wikilink/
│   │       ├── Wikilink.swift
│   │       ├── WikilinkAnchor.swift
│   │       ├── WikilinkScanner.swift
│   │       ├── WikilinkParser.swift
│   │       ├── MarkdownDocument+Wikilink.swift
│   │       ├── WikilinkResolver.swift
│   │       └── ResolvedWikilink.swift
│   └── md-utils/                  # CLI tool
│       ├── CLIEntry.swift
│       ├── GlobalOptions.swift
│       ├── OutputFormat.swift
│       ├── Commands/
│       │   ├── Body.swift
│       │   ├── ExtractSection.swift
│       │   ├── GenerateTOC.swift
│       │   └── Lines.swift
│       ├── FrontMatterCommands/
│       │   ├── FrontMatterCommands.swift
│       │   ├── Get.swift
│       │   ├── Set.swift
│       │   ├── Has.swift
│       │   ├── Remove.swift
│       │   ├── Rename.swift
│       │   ├── Replace.swift
│       │   ├── List.swift
│       │   ├── Dump.swift
│       │   ├── Search.swift
│       │   ├── SortKeys.swift
│       │   ├── Touch.swift
│       │   ├── ArrayCommands.swift
│       │   ├── ArrayAppend.swift
│       │   ├── ArrayContains.swift
│       │   ├── ArrayPrepend.swift
│       │   ├── ArrayRemove.swift
│       │   └── ArrayHelpers.swift
│       ├── HeadingCommands/
│       │   ├── HeadingCommands.swift
│       │   ├── PromoteHeading.swift
│       │   └── DemoteHeading.swift
│       ├── SectionCommands/
│       │   ├── SectionCommands.swift
│       │   ├── MoveSectionUp.swift
│       │   ├── MoveSectionDown.swift
│       │   └── MoveSectionTo.swift
│       ├── ConvertCommands/
│       │   ├── ConvertCommands.swift
│       │   ├── ToText.swift
│       │   └── ToCSV.swift
│       ├── FileMetadataCommands/
│       │   ├── FileMetadataCommands.swift
│       │   └── ReadMetadata.swift
│       └── LinkCommands/
│           ├── LinkCommands.swift
│           ├── ListLinks.swift
│           ├── Check.swift
│           └── Backlinks.swift
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
    │   │   ├── PlainText/
    │   │   │   └── PlainTextConverterTests.swift
    │   │   └── CSV/
    │   │       └── CSVConverterTests.swift
    │   ├── HeadingAdjustment/
    │   │   ├── HeadingAdjusterTests.swift
    │   │   ├── HeadingReconstructorTests.swift
    │   │   ├── HeadingScopeTests.swift
    │   │   ├── EdgeCaseTests.swift
    │   │   └── MarkdownDocumentIntegrationTests.swift
    │   ├── SectionExtraction/
    │   │   ├── SectionExtractorTests.swift
    │   │   ├── SectionBoundaryDetectorTests.swift
    │   │   └── MarkdownDocumentSectionExtractionTests.swift
    │   ├── SectionReordering/
    │   │   ├── SectionReordererTests.swift
    │   │   ├── SectionSiblingFinderTests.swift
    │   │   └── MarkdownDocumentSectionReorderingTests.swift
    │   ├── Helpers/
    │   │   └── LineNumbersTests.swift
    │   ├── FileMetadata/
    │   │   ├── FileMetadataTests.swift
    │   │   ├── FileMetadataReaderTests.swift
    │   │   └── ExtendedAttributesTests.swift
    │   └── Wikilink/
    │       ├── WikilinkScannerTests.swift
    │       ├── WikilinkParserTests.swift
    │       ├── WikilinkResolverTests.swift
    │       ├── ResolvedWikilinkTests.swift
    │       └── MarkdownDocumentWikilinkTests.swift
    └── md-utilsTests/
        ├── CLIEntryTests.swift
        ├── GlobalOptionsTests.swift
        └── Commands/
            ├── BodyTests.swift
            ├── ExtractSectionTests.swift
            ├── LinesTests.swift
            ├── SectionCommandsTests.swift
            ├── ToCSVTests.swift
            ├── FileMetadataCommandsTests.swift
            ├── LinkCommandsTests.swift
            └── FrontMatterCommands/
                ├── GetTests.swift
                ├── HasTests.swift
                ├── SetTests.swift
                ├── RemoveTests.swift
                ├── RenameTests.swift
                ├── ReplaceTests.swift
                ├── ListTests.swift
                ├── SearchTests.swift
                ├── SortKeysTests.swift
                ├── ArrayAppendTests.swift
                ├── ArrayContainsTests.swift
                ├── ArrayPrependTests.swift
                └── ArrayRemoveTests.swift
```

## Naming Conventions

### Types and Structs
- **MarkdownDocument** - Core data type (singular, descriptive)
- **CLIEntry** - CLI entry point (NOT MarkdownUtilitiesEntry)

### Test Files
- Match the file they're testing with "Tests" suffix
- Example: `MarkdownDocument.swift` → `MarkdownDocumentTests.swift`

