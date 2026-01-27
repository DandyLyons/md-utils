# md-utils CLI

Command-line tool for working with Markdown files and YAML frontmatter.

## Overview

md-utils is a powerful CLI tool for parsing, manipulating, and analyzing Markdown documents. It provides commands for working with frontmatter, generating tables of contents, converting formats, and processing multiple files efficiently.

Built on the MarkdownUtilities library, md-utils brings Markdown manipulation capabilities to your terminal and automation scripts.

## Key Features

- **Frontmatter Management**: Read, write, update, and delete YAML frontmatter
- **Table of Contents**: Generate TOCs in multiple formats
- **Format Conversion**: Convert Markdown to plain text
- **Batch Processing**: Process multiple files with recursive directory scanning
- **Flexible Output**: Support for multiple output formats (JSON, YAML, Markdown, HTML)
- **Pipeline-Friendly**: Designed for use in shell scripts and automation

## Quick Start

```bash
# Get frontmatter value
md-utils fm get --key title document.md

# Set frontmatter value
md-utils fm set --key author --value "Jane Doe" document.md --in-place

# Generate table of contents
md-utils toc document.md

# Convert to plain text
md-utils convert to-text document.md

# Extract body without frontmatter
md-utils body document.md
```

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:GlobalOptions>

### Commands

- <doc:Commands/BodyCommand>
- <doc:Commands/TOCCommand>
- <doc:Commands/ToTextCommand>
- <doc:Commands/FMGet>
- <doc:Commands/FMSet>
- <doc:Commands/FMList>
- <doc:Commands/FMDump>

### Workflow Guides

#### Hugo Static Site Generator

- <doc:Workflows/HugoWorkflows/HugoWorkflows>
- <doc:Workflows/HugoWorkflows/CreatingPosts>
- <doc:Workflows/HugoWorkflows/ManagingTaxonomies>
- <doc:Workflows/HugoWorkflows/BulkUpdates>
- <doc:Workflows/HugoWorkflows/DeploymentAutomation>

#### Obsidian Note-Taking

- <doc:Workflows/ObsidianWorkflows/ObsidianWorkflows>
- <doc:Workflows/ObsidianWorkflows/NoteTaking>
- <doc:Workflows/ObsidianWorkflows/LinkManagement>
- <doc:Workflows/ObsidianWorkflows/MetadataSync>
- <doc:Workflows/ObsidianWorkflows/TemplateGeneration>

#### General Markdown

- <doc:Workflows/GeneralMarkdown/GeneralMarkdown>
- <doc:Workflows/GeneralMarkdown/DocumentationMaint>
- <doc:Workflows/GeneralMarkdown/BatchProcessing>
- <doc:Workflows/GeneralMarkdown/ContentMigration>
- <doc:Workflows/GeneralMarkdown/QualityControl>

#### Scripting & Automation

- <doc:Workflows/Scripting/Scripting>
- <doc:Workflows/Scripting/ShellIntegration>
- <doc:Workflows/Scripting/PipelinePatterns>
- <doc:Workflows/Scripting/ErrorHandling>

## Installation

### From Source

```bash
git clone https://github.com/yourusername/md-utils.git
cd md-utils
swift build -c release
cp .build/release/md-utils /usr/local/bin/
```

### Using Mint

```bash
mint install yourusername/md-utils
```

## Command Structure

md-utils uses a hierarchical command structure:

```
md-utils [global-options] <command> [command-options] <files>
```

### Global Options

Options that apply to all commands:

- `--recursive` / `--non-recursive`: Scan directories recursively
- `--include-hidden`: Include hidden files (starting with `.`)
- `--extensions <exts>`: File extensions to process (default: md,markdown)
- `--in-place`: Modify files directly instead of outputting to stdout
- `--output <path>`: Write output to file or directory
- `--no-sort`: Don't sort output files by name

See <doc:GlobalOptions> for complete documentation.

## Common Workflows

### Working with Hugo Sites

```bash
# Create new post with frontmatter
md-utils fm set --key title --value "My Post" \\
               --key date --value "2024-01-24" \\
               --key draft --value "true" \\
               content/posts/my-post.md --in-place

# Publish all drafts
md-utils fm set --key draft --value "false" \\
               --recursive content/ --in-place
```

### Processing Obsidian Vaults

```bash
# Add timestamp to all notes
md-utils fm set --key modified --value "$(date -I)" \\
               --recursive vault/ --in-place

# List all tags across vault
md-utils fm get --key tags --recursive vault/
```

### Documentation Maintenance

```bash
# Generate TOC for all docs
md-utils toc --recursive docs/ --output docs-toc/

# Extract plain text for search indexing
md-utils convert to-text --recursive docs/ \\
         --format plain-text --output search-index/
```

## Output Formats

md-utils supports multiple output formats depending on the command:

- **JSON**: Machine-readable structured data
- **YAML**: Human-readable structured data
- **Markdown**: Formatted Markdown output
- **Plain Text**: Simple text output
- **HTML**: HTML formatted output (for TOC)

## Error Handling

md-utils provides clear error messages and appropriate exit codes:

- `0`: Success
- `1`: General error
- `2`: Invalid arguments
- `3`: File not found
- `4`: Parse error

See <doc:Workflows/Scripting/ErrorHandling> for robust error handling patterns.

## See Also

- [MarkdownUtilities Library Documentation](../MarkdownUtilities/documentation/markdownutilities)
- [GitHub Repository](https://github.com/yourusername/md-utils)
- <doc:GettingStarted>
