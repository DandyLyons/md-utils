# Global Options

Options that apply to all md-utils commands.

## Overview

Global options control how md-utils processes files and handles output. These options come before the command name and apply regardless of which command you're using.

## Syntax

```bash
md-utils [global-options] <command> [command-options] <files>
```

Global options must appear **before** the command name.

## File Processing Options

### Recursive Processing

Control whether to scan directories recursively.

#### --recursive

Scan directories recursively, processing all Markdown files in subdirectories:

```bash
# Process all Markdown files in content/ and subdirectories
md-utils --recursive fm get --key title content/

# Short form
md-utils -r fm get --key title content/
```

**Default**: Depends on input type
- Files: Not applicable
- Directories: Recursive by default

#### --non-recursive

Process only files in the specified directory, not subdirectories:

```bash
# Only process files directly in posts/
md-utils --non-recursive fm get --key title posts/

# Skip all subdirectories
md-utils --non-recursive fm set --key updated --value "$(date -I)" docs/ --in-place
```

**Use cases:**
- Avoid processing template directories
- Target only top-level files
- Faster processing when subdirectories aren't needed

### Hidden Files

Control whether to process hidden files (those starting with `.`).

#### --include-hidden

Include hidden files in processing:

```bash
# Process all files, including .draft.md
md-utils --include-hidden --recursive fm get --key title vault/

# Process .obsidian directory contents
md-utils --include-hidden fm get --key title vault/.obsidian/templates/
```

**Default**: Hidden files are excluded

**Use cases:**
- Processing Obsidian vault configuration
- Working with draft files (.draft.md)
- Accessing template directories

### File Extensions

Specify which file extensions to process.

#### --extensions

Comma-separated list of file extensions (without dots):

```bash
# Default: md,markdown
md-utils fm get --key title content/

# Custom extensions
md-utils --extensions md,mdx,txt fm get --key title content/

# Single extension
md-utils --extensions md fm get --key title content/
```

**Default**: `md,markdown`

**Use cases:**
- Process MDX files (React Markdown)
- Include .txt files with frontmatter
- Exclude .markdown while keeping .md

**Examples:**

```bash
# Only .md files
md-utils --extensions md --recursive content/

# Multiple custom extensions
md-utils --extensions md,mdx,markdown,txt --recursive docs/

# Process all text files in documentation
md-utils --extensions txt,md fm dump --format json docs/
```

## Output Control Options

### In-Place Modification

Modify files directly instead of outputting to stdout.

#### --in-place

Update files in place:

```bash
# Modify post.md directly
md-utils fm set --key author --value "Jane" post.md --in-place

# Update all files in directory
md-utils --recursive fm set --key updated --value "$(date -I)" \\
         content/ --in-place

# Short form
md-utils fm set --key draft --value "false" post.md -i
```

**Default**: Output to stdout

> Warning: `--in-place` modifies files directly. Always have backups or use version control.

**Use cases:**
- Batch updates to frontmatter
- Publishing workflow (draft → published)
- Automated content management

**Safety tips:**

```bash
# Test without --in-place first
md-utils fm set --key author --value "Jane" posts/*.md

# Then apply when confident
md-utils fm set --key author --value "Jane" posts/*.md --in-place

# Use with version control
git add posts/
md-utils fm set --key updated --value "$(date -I)" posts/*.md --in-place
git diff  # Review changes
git commit -m "Update timestamps"
```

### Output Destination

#### --output

Write output to a file or directory:

```bash
# Single file to file
md-utils toc post.md --output post-toc.md

# Multiple files to directory
md-utils toc posts/*.md --output toc-dir/

# Recursive processing to directory
md-utils --recursive toc content/ --output toc-output/

# Short form
md-utils toc post.md -o toc.md
```

**Behavior:**
- **Single input file**: `--output` specifies output filename
- **Multiple input files**: `--output` specifies output directory
- **Directory input**: `--output` specifies output directory

**File naming:**

When outputting to a directory, files maintain their relative paths:

```bash
# Input structure:
# content/
#   posts/
#     2024/
#       post1.md
#       post2.md

md-utils --recursive toc content/ --output toc/

# Output structure:
# toc/
#   posts/
#     2024/
#       post1.md
#       post2.md
```

**Use cases:**
- Generate derived files (TOCs, plain text)
- Export for other tools
- Create separate output directory

### Sorting

#### --no-sort

Disable sorting of output files:

```bash
# Files processed in arbitrary order
md-utils --no-sort --recursive fm get --key title content/

# Preserve filesystem order
md-utils --no-sort fm get --key title posts/*.md
```

**Default**: Files are sorted by path

**Use cases:**
- Preserve processing order from filesystem
- Slightly faster processing
- Debug/testing scenarios

## Combining Options

Multiple global options can be combined:

```bash
# All options together
md-utils --recursive --include-hidden --extensions md,mdx \\
         --in-place fm set --key updated --value "$(date -I)" vault/

# Common combination: recursive + in-place
md-utils -r -i fm set --key draft --value "false" content/

# Output with custom extensions
md-utils -r --extensions md,mdx --output dist/ toc content/
```

## Option Order

Global options must come **before** the command:

```bash
# ✓ Correct
md-utils --recursive fm get --key title content/

# ✗ Wrong (--recursive after command)
md-utils fm get --recursive --key title content/
```

Command-specific options come **after** the command:

```bash
# ✓ Correct
md-utils --recursive fm get --key title --format json content/
#        └ global ─┘        └─ command options ─────┘

# ✗ Wrong
md-utils fm get --key title --recursive content/
```

## Common Patterns

### Safe Batch Updates

Test first, then apply:

```bash
# 1. Preview changes (without --in-place)
md-utils --recursive fm set --key updated --value "$(date -I)" content/

# 2. Review output

# 3. Apply changes
md-utils --recursive fm set --key updated --value "$(date -I)" content/ --in-place
```

### Processing Specific File Types

```bash
# Only .md files in docs
md-utils --extensions md --recursive fm get --key title docs/

# Only .mdx files
md-utils --extensions mdx fm get --key title content/

# Multiple types
md-utils --extensions md,mdx,markdown --recursive toc content/
```

### Including Template Files

```bash
# Process hidden template files
md-utils --include-hidden fm get --key template .templates/

# Process all files including hidden
md-utils --recursive --include-hidden fm dump --format json vault/
```

### Generating Derived Files

```bash
# Generate TOCs in separate directory
md-utils --recursive --output toc/ toc content/

# Convert all to plain text
md-utils -r -o plain-text/ convert to-text content/

# Export frontmatter as JSON
md-utils -r fm dump --format json content/ -o frontmatter/
```

## Environment Variables

Some behaviors can be controlled via environment variables:

```bash
# Set default extensions
export MD_UTILS_EXTENSIONS="md,mdx,markdown"
md-utils fm get --key title content/

# Force color output
export MD_UTILS_COLOR="always"
md-utils --recursive fm get --key title content/
```

## Examples by Use Case

### Content Management

```bash
# Publish all drafts
md-utils -r -i fm set --key draft --value "false" content/posts/

# Update timestamps on all posts
md-utils -r -i fm set --key modified --value "$(date -I)" content/

# Add author to posts missing it
md-utils -r -i fm set --key author --value "Default Author" content/
```

### Documentation Generation

```bash
# Generate TOCs for all docs
md-utils -r --output toc/ toc docs/

# Extract plain text for search
md-utils -r --output search/ convert to-text docs/

# Export metadata as JSON
md-utils -r fm dump --format json docs/ -o metadata.json
```

### Obsidian Vault Management

```bash
# Include hidden files and templates
md-utils --include-hidden -r fm get --key tags vault/

# Process only .md files (skip .obsidian directory)
md-utils -r fm get --key created vault/

# Update all notes with timestamp
md-utils -r -i fm set --key modified --value "$(date -I)" vault/
```

### Hugo Site Workflows

```bash
# Process only .md files in content
md-utils --extensions md -r fm get --key title content/

# Publish posts for a specific date
md-utils -r -i fm set --key publishDate --value "2024-01-24" content/posts/

# Generate TOCs for all content
md-utils -r --output public/toc/ toc content/
```

## See Also

- <doc:GettingStarted>
- <doc:Commands/FMGet>
- <doc:Commands/FMSet>
- <doc:Workflows/Scripting/ShellIntegration>
