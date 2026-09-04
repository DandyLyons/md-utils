# Architecture

`md-utils` is part of a broader Markdown tooling ecosystem. [`treedocs`](https://github.com/DandyLyons/treedocs) is a sister project, and future integrations are planned between the two projects.

The proposed native and Cloudflare server architecture, WebAssembly target split, Markdown type-system prerequisite, and storage direction are documented in [MarkdownUtilities Server Architecture](server-architecture.md). The supported WASI toolchain and repeatable Core verification workflow are documented in [WebAssembly Support](webassembly.md).

## Library Layers

`MarkdownUtilitiesCore` owns content-only parsing and transformations. It accepts strings, document models, and explicit context; it does not scan the filesystem or inspect host metadata. The target is supported on Apple platforms and Linux.

`MarkdownUtilities` depends on Core and adds filesystem-backed wikilink resolution, CSV path metadata, and file metadata including extended attributes. `MarkdownUtilitiesServer` also depends only on Core, defines storage-neutral canonical-record persistence, and compiles explicit server resources into transport-neutral endpoint plans. Consumers import the products explicitly according to the APIs each source file uses.

The Markdown type system follows the same boundary. Core owns canonical `MarkdownRecord` values, parsed `MarkdownDocument` values, normalized rule configuration, rule and type compilation, portable predicate evaluation, diagnostics, and in-memory fix application. `MarkdownUtilities` loads `.md-utils/types/`, resolves filesystem schema resources, constructs logical record paths, acquires modification timestamps, and performs atomic record writes. The executable owns command parsing, the serialized JMESPath capability provider, prompts, formatting, and exit status.

The full source and dependency classification is recorded in the [portability audit](portability-audit.md).

## Core Library (MarkdownUtilitiesCore)

### MarkdownDocument

**Location**: `Sources/MarkdownUtilitiesCore/MarkdownDocument.swift`

Central data structure representing a Markdown document:
- Separates YAML (`---`) or TOML (`+++`) frontmatter from body content
- Frontmatter parsed into the ordered, format-neutral `FrontMatter` model
- Body available as `String` for text processing
- Supports parsing body into Markdown AST via `parseAST()` method
- AST parsing uses MarkdownSyntax library returning `Root` structure

A document is a successfully parsed content view and deliberately has no persistent identity, logical path, revision, or storage location. `MarkdownRecord` is the separate canonical resource model. It remains representable when parsing fails, allowing type and rule assessment to return invalid YAML as a structured diagnostic.

### Markdown Types and Rules

**Locations**: `Sources/MarkdownUtilitiesCore/Types/`, `Sources/MarkdownUtilitiesCore/Rules/`, and `Sources/MarkdownUtilities/Types/`

- `MarkdownTypeDefinition` models the `frontmatter`, `body`, and `context` conformance domains.
- `MarkdownTypeRegistry` validates definitions, resolves and caches external JSON Schema graphs, and rejects duplicates, cycles, and conflicting schema identifiers.
- `MarkdownTypeChecker` analyzes one canonical record once and supports named assessment, overlap queries, and type-hint verification.
- `MarkdownRuleDefinition` is the sole normalized rule model and keeps applicability separate from checks.
- `MarkdownRuleCompiler` validates definitions and capabilities before records are processed, producing one immutable `MarkdownRuleRegistry` shared by CLI and server consumers.
- `MarkdownDiagnostic` distinguishes errors from advisories and can carry structured fix-its.
- `MarkdownTypeFixer` applies selected edits in memory; native and CLI layers own persistence and interaction.

Types are structural and non-exclusive. Rules and types remain distinct domain models even where they share analysis and predicate evaluation. Config versions `0.1.0` and `0.2.0` normalize into the same Core definitions; there is no `0.3.0` grouping syntax.

The normative mdtype v1 design is documented in [RFC 0001](rfcs/0001-mdtype.md).

### fm-var Foundation

Core's `FMVar/` feature area defines the portable [RFC 001 Rev 3](https://github.com/DandyLyons/fm-var-tag/blob/18604853843d6edf22aba927c98697f5c956a0f3/PROPOSAL.md) vocabulary for `<fm-var>`,
`<fm-list>`, and `<fm-format>`. It includes lossless raw attributes, exact half-open UTF-8 source
ranges, normalized JSONPath declarations, YAML-to-I-JSON query argument and node-association
models, ordered nodelists, formatting provenance, statuses, result metadata, stable diagnostic
codes, and proposed child-text edits. UTF-8 offsets are zero-based; diagnostic lines and UTF-8 byte
columns are one-based. These types are content-only and `Codable`, `Equatable`, and `Sendable`
where used for structured reports.

DynamicJSON 1.0.2 is Core's authoritative JSONPath parser and evaluator. The portable
`FMVarJSONPathEvaluator` converts `FMVarQueryArgument` values, maps located results back to retained
node identities and source scalars, preserves order and duplicates, configures function
availability, and maps invalid, unsupported, resource-limited, empty, and non-empty outcomes into
structured fm-var results. Configurable outer guards cover query length, query/value depth,
conservative execution work, final result count, and conservative regular-expression work without
performing I/O.

Core's `FMVarURIResolver` performs strict, fragment-free RFC 3986 parsing and Section 5.2 resolution.
Its `FMVarYAMLProjector` configures Yams from `Resolver.basic` with YAML 1.2.2 Core Schema rules and
projects Yams nodes into the existing I-JSON query model. Yams remains the only YAML syntax parser,
scalar decoder, representation composer, and alias implementation; the projector only assigns
portable types, validates RFC 001 constraints, retains `Node.Scalar.string`, and creates
deterministic JSON-location node identities.

`MarkdownUtilities` owns `FMVarSourceResolver`, the adapter between portable resolution and a
host-supplied async `FMVarResourceProvider`. Its native `FMVarHostPolicy` and
`FileFMVarResourceProvider` provide the initial concrete host: a required canonical allowed root,
an 8 MiB source limit, and local Markdown/YAML access only. Relative, absolute-path, and `file:`
references must remain under the root both before and after symlink resolution. Network schemes,
authorities, credentials, URI queries, redirects, and other file kinds are disabled. Omitted and
empty references reuse a containing snapshot loaded through the same policy, while `self` is an
ordinary relative path. Recognized content type is authoritative and extension is a fallback only
for absent or generic types. Processing stops after decoding and projecting one resource.

Core does not maintain a second parser, type checker, or interpreter to correct dependency
behavior. DynamicJSON's grapheme-cluster `length()`, Foundation regular expressions, and strict-mode
syntax extensions remain visible and are documented compatibility constraints, but dependency-only
functions are removed from the evaluation environment. Object enumeration order is not portable
and is never sorted or deduplicated. Value coercion, formatting, escaping, and mutation remain
downstream work. `MarkdownUtilities` owns filesystem policy, while executable hosts retain policy
selection and revision-checked write responsibilities. The
language-neutral fixture corpus is pinned to the authoritative proposal revision and bundled with
`MarkdownUtilitiesCoreTests`.

## Server Planning Library (MarkdownUtilitiesServer)

`MarkdownUtilitiesServer` owns the storage-neutral `RecordStore` contract, actor-backed `InMemoryRecordStore`, versioned resource-configuration model, selection and identity policies, immutable `EndpointPlan`, generic read snapshot, transport-neutral route descriptions, and structured startup diagnostics. It has no Hummingbird or filesystem dependency.

The store contract fetches canonical records by stable identity, enumerates deterministic bounded pages under optional logical search roots, and defines store-owned revisions for atomic create, replace, and delete operations. Logical paths remain portable metadata rather than filesystem keys. Parsed representations, type membership, and other indexes remain rebuildable derived state.

Server resources are explicit and opt-in. Configuration supports rule selection, type selection within a collection-relative search root, and rule selection with an expected type. Compilation resolves only referenced definitions, rejects unsafe or ambiguous routes, and derives stable operation IDs. Equivalent inputs produce identical plans regardless of authoring order.

The read snapshot scans canonical storage in bounded pages, applies path narrowing before parsing, reuses one record analysis across rule, type, and identity assessment, and publishes immutable generic envelopes with collision-safe primary-ID and logical-path lookup. The native server loads its own configuration outside `.md-utils.json`, registers Hummingbird 2 adapters from the accepted plan and snapshot, and generates OpenAPI 3.1 from that same plan.

**Frontmatter Handling:**
- Uses `FrontMatterParser` to detect YAML and TOML delimiter blocks
- Frontmatter parsed into `FrontMatter` during initialization while retaining its source format
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
- Subcommands defined in `Sources/md-utils/Commands/`

### Current Subcommands

- `body` / `b` (Body) - Extract body content without frontmatter
- `convert` (ConvertCommands) - Convert Markdown to other formats
  - `convert to-text` - Convert Markdown to plain text
  - `convert to-csv` - Convert Markdown to CSV
- `extract` (ExtractSection) - Extract a section from Markdown files by name or index
- `frontmatter` / `fm` (FrontMatterCommands) - Manipulate YAML or TOML frontmatter
  - `fm get` - Retrieve frontmatter value by key
  - `fm set` - Set/update frontmatter value by key
  - `fm has` - Check if frontmatter key exists
  - `fm remove` - Delete frontmatter key
  - `fm remove-frontmatter` / `fm rmfm` - Delete the complete frontmatter block
  - `fm rename` - Rename frontmatter key
  - `fm replace` / `fm r` - Replace entire frontmatter with new data
  - `fm list` - List all frontmatter keys
  - `fm dump` - Dump entire frontmatter in specified format (JSON, YAML, TOML, raw, plist)
  - `fm search` - Search YAML frontmatter with a JMESPath query (TOML is out of scope)
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
- `okf` (OKFCommands) - Work with Open Knowledge Format v0.1 draft bundles
  - `okf init` - Create a minimal OKF bundle scaffold and install schema configuration
  - `okf validate` - Validate hard OKF v0.1 draft conformance rules
  - `okf report` - Report bundle inventory, type distribution, and advisory diagnostics
  - `okf doctor` - Run validation plus advisory health diagnostics
  - `okf type set` - Set an explicit OKF concept `type` value on matching files
- `types` (TypesCommands) - Work with Markdown type definitions and typed records
  - `types add`, `list`, `describe`, `doctor`, and `schema` - Manage and inspect definitions
  - `types check`, `verify`, `identify`, and `find` - Assess conformance and type hints
  - `types fix` - Preview and apply structured conformance fixes
- `section` / `sect` (SectionCommands) - Manipulate sections in Markdown documents
  - `section get` - Extract a section and output it
  - `section set` - Replace a section body while preserving its heading
  - `section insert` - Insert a new contained section before or after another section
  - `section remove` - Remove a section and all descendant content
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

YAML and TOML frontmatter are separated and parsed into structured data.

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
- **Format conversion**: `FrontMatterConversion` for YAML/TOML and shared JSON, YAML, TOML, and PropertyList output
- **CLI**: `md-utils frontmatter` (alias `fm`) with subcommands:
  - Basic CRUD: `get`, `set`, `has`, `remove`, `rename`, `list`, `dump`
  - Advanced: `replace`, `search` (JMESPath queries), `sort-keys`, `touch`
  - Array operations: `array append`, `array contains`, `array prepend`, `array remove`
- **Dump Feature**: Output entire frontmatter in multiple formats
  - Formats: JSON (default), YAML, TOML, raw, PropertyList (XML)
  - Single file: direct output without wrapper
  - Multiple files: cat-style headers (==> path <==) with separation
  - Optional format-appropriate delimiters via `--include-delimiters`
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

## Planned Features

The following features are **NOT YET IMPLEMENTED**:

1. **Additional Validation** - Markdown flavor compliance and future predicate vocabulary
2. **Additional Format Conversions** - HTML, RTF, XML (infrastructure ready, plain text and CSV implemented)
3. **File Metadata Writing** - Write/update file metadata (read operations implemented)
4. **`treedocs` Integration** - Integration with the sister project [`treedocs`](https://github.com/DandyLyons/treedocs)

## Dependencies

### Current Dependencies

- **MarkdownSyntax** (1.3.0+) - Swift Markdown parsing and syntax tree
- **swift-parsing** (0.14.1+) - Parser combinators
- **swift-argument-parser** (1.6.1+) - CLI argument parsing
- **PathKit** (1.0.1+) - File path handling
- **JSONSchema.swift** (0.6.0+) - JSON Schema validation
- **DynamicJSON** (1.0.2+, Apache-2.0) - RFC 9535 JSONPath parsing and evaluation for portable fm-var work
- **Yams** (6.1.0+) - YAML parsing and serialization
- **swift-toml** (2.0.0+) - TOML parsing and serialization
- **jmespath.swift** (1.0.3+) - JMESPath query language for JSON (used by `fm search`)
- **Rainbow** (4.2.1+) - ANSI styling for human-facing CLI output

### Transitive Dependencies

- **swift-case-paths** - Case path utilities (from swift-parsing)
- **xctest-dynamic-overlay** - Testing utilities (from swift-parsing)
- **swift-cmark** - CommonMark C library (from MarkdownSyntax)

## Project Structure
```text
md-utils/
├── Package.swift
├── Dockerfile.core-linux
├── docs/
│   ├── architecture.md
│   ├── portability-audit.md
│   └── development-workflow.md
├── Sources/
│   ├── MarkdownUtilitiesCore/     # Portable content operations
│   ├── MarkdownUtilities/         # Native filesystem and metadata integrations
│   └── md-utils/                  # CLI orchestration and presentation
└── Tests/
    ├── MarkdownUtilitiesCoreTests/
    ├── MarkdownUtilitiesTests/
    └── md-utilsTests/
```

The two library targets mirror their test targets. Portable features and tests belong in the Core directories; filesystem- or host-dependent behavior belongs in the native directories.

## Naming Conventions

### Types and Structs
- **MarkdownDocument** - Core data type (singular, descriptive)
- **CLIEntry** - CLI entry point (NOT MarkdownUtilitiesEntry)

### Test Files
- Match the file they're testing with "Tests" suffix
- Example: `MarkdownDocument.swift` → `MarkdownDocumentTests.swift`
