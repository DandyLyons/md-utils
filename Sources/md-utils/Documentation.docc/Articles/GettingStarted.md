# Getting Started with md-utils

Learn how to install and use the md-utils CLI tool.

## Overview

md-utils is a command-line tool for working with Markdown files and YAML frontmatter. This guide will help you install md-utils and learn the basic commands.

## Installation

### From Source

Build and install from source using Swift:

```bash
# Clone the repository
git clone https://github.com/yourusername/md-utils.git
cd md-utils

# Build in release mode
swift build -c release

# Copy to your PATH
cp .build/release/md-utils /usr/local/bin/

# Verify installation
md-utils --version
```

### Using Mint

If you have [Mint](https://github.com/yonaskolb/Mint) installed:

```bash
mint install yourusername/md-utils
```

### Using Homebrew

```bash
brew install md-utils
```

## Verifying Installation

Check that md-utils is installed correctly:

```bash
# Check version
md-utils --version

# Get help
md-utils --help
```

## Your First Commands

### Reading Frontmatter

Get a value from frontmatter:

```bash
# Create a sample Markdown file
cat > sample.md << 'EOF'
---
title: My First Document
author: Jane Doe
tags: [swift, markdown]
---

# My First Document

This is the content.
EOF

# Get the title
md-utils fm get --key title sample.md
# Output: My First Document

# Get tags
md-utils fm get --key tags sample.md
# Output: ["swift", "markdown"]
```

### Setting Frontmatter

Update frontmatter values:

```bash
# Set a value (outputs to stdout)
md-utils fm set --key author --value "John Doe" sample.md

# Modify the file in place
md-utils fm set --key author --value "John Doe" sample.md --in-place

# Verify the change
md-utils fm get --key author sample.md
# Output: John Doe
```

### Extracting Body Content

Get the Markdown content without frontmatter:

```bash
# Get body as Markdown
md-utils body sample.md
# Output:
# # My First Document
#
# This is the content.

# Convert to plain text
md-utils body --format plain-text sample.md
# Output:
# My First Document
#
# This is the content.
```

### Generating Table of Contents

Create a TOC from document headings:

```bash
# Create a document with headings
cat > doc.md << 'EOF'
# Introduction

## Getting Started

### Installation

### Configuration

## Usage

### Basic Commands

### Advanced Features
EOF

# Generate TOC (default: Markdown with links)
md-utils toc doc.md
# Output:
# - [Introduction](#introduction)
#   - [Getting Started](#getting-started)
#     - [Installation](#installation)
#     - [Configuration](#configuration)
#   - [Usage](#usage)
#     - [Basic Commands](#basic-commands)
#     - [Advanced Features](#advanced-features)

# Generate as plain text
md-utils toc --format plain doc.md
# Output:
# Introduction
#   Getting Started
#     Installation
#     Configuration
#   Usage
#     Basic Commands
#     Advanced Features
```

## Command Structure

All md-utils commands follow this pattern:

```bash
md-utils [global-options] <command> [command-options] <files>
```

### Components

1. **Global Options**: Apply to all commands (e.g., `--recursive`, `--in-place`)
2. **Command**: The operation to perform (e.g., `fm get`, `toc`, `body`)
3. **Command Options**: Specific to each command (e.g., `--key`, `--format`)
4. **Files**: One or more files or directories to process

### Example

```bash
md-utils --recursive fm set --key updated --value "2024-01-24" content/ --in-place
#        └─ global   │  └── command options ──────────────┘ └files┘ └ global ─┘
#                    └── command
```

## Getting Help

### General Help

```bash
# List all commands
md-utils --help

# Or
md-utils -h
```

### Command-Specific Help

```bash
# Help for a specific command
md-utils fm --help
md-utils toc --help
md-utils convert --help

# Help for a subcommand
md-utils fm get --help
md-utils fm set --help
```

## Common Patterns

### Single File Operations

Process one file at a time:

```bash
# Read
md-utils fm get --key title post.md

# Write (to stdout)
md-utils fm set --key draft --value "false" post.md

# Write (in place)
md-utils fm set --key draft --value "false" post.md --in-place
```

### Multiple Files

Process several files:

```bash
# Process multiple files
md-utils fm get --key title post1.md post2.md post3.md

# Use wildcards
md-utils fm get --key title posts/*.md

# Output to separate files
md-utils toc posts/*.md --output toc-files/
```

### Recursive Directory Processing

Process all Markdown files in a directory tree:

```bash
# Process all files recursively
md-utils fm get --key title --recursive content/

# Modify all files in place
md-utils fm set --key updated --value "$(date -I)" \\
         --recursive content/ --in-place

# Generate TOCs for all files
md-utils toc --recursive docs/ --output toc/
```

### Pipeline Usage

Use md-utils in shell pipelines:

```bash
# Extract titles and grep for pattern
md-utils fm get --key title --recursive posts/ | grep "Swift"

# Get all tags and count unique ones
md-utils fm get --key tags --recursive posts/ \\
    | jq -r '.[]' \\
    | sort \\
    | uniq -c

# Find posts by author
md-utils fm get --key author posts/*.md \\
    | grep -l "Jane Doe" \\
    | xargs md-utils fm get --key title
```

## File Selection

### Extensions

Control which file extensions to process:

```bash
# Default: .md and .markdown
md-utils fm get --key title content/

# Custom extensions
md-utils --extensions md,mdx,txt fm get --key title content/
```

### Hidden Files

Include or exclude hidden files:

```bash
# Exclude hidden files (default)
md-utils --recursive fm get --key title vault/

# Include hidden files
md-utils --recursive --include-hidden fm get --key title vault/
```

## Output Modes

### Standard Output (Default)

Results go to stdout:

```bash
# Prints to console
md-utils fm get --key title post.md
md-utils toc post.md
```

### In-Place Modification

Modify files directly:

```bash
# Updates the file
md-utils fm set --key author --value "Jane" post.md --in-place
```

### File Output

Write results to a file:

```bash
# Single file
md-utils toc post.md --output toc.md

# Multiple files (directory required)
md-utils toc --recursive posts/ --output toc-dir/
```

## Working with Formats

Different commands support different output formats:

```bash
# Frontmatter dump formats
md-utils fm dump --format json post.md
md-utils fm dump --format yaml post.md
md-utils fm dump --format plist post.md

# TOC formats
md-utils toc --format md-bullet-links post.md
md-utils toc --format plain post.md
md-utils toc --format json post.md
md-utils toc --format html post.md

# Body formats
md-utils body --format markdown post.md
md-utils body --format plain-text post.md
```

## Error Handling

md-utils provides clear error messages:

```bash
# File not found
md-utils fm get --key title missing.md
# Error: File not found: missing.md

# Invalid frontmatter
md-utils fm get --key title invalid.md
# Error: Failed to parse frontmatter in invalid.md

# Missing required option
md-utils fm get post.md
# Error: Missing required option: --key
```

Exit codes indicate success or failure:
- `0`: Success
- Non-zero: Error occurred

Use in scripts:

```bash
if md-utils fm get --key title post.md > /dev/null 2>&1; then
    echo "Title exists"
else
    echo "No title or error"
fi
```

## Next Steps

Now that you understand the basics:

- <doc:GlobalOptions> - Learn about all global options
- <doc:Commands/FMGet> - Master frontmatter reading
- <doc:Commands/FMSet> - Learn frontmatter updates
- <doc:Commands/TOCCommand> - Explore TOC generation
- <doc:Workflows/Scripting/ShellIntegration> - Use md-utils in scripts

## See Also

- <doc:GlobalOptions>
- <doc:Commands/BodyCommand>
- <doc:Commands/TOCCommand>
- <doc:Workflows/Scripting/Scripting>
