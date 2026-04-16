# Common Use Cases

This document provides common use cases for the `md-utils` CLI and its subcommands.

## Extraction Operations

### Extract a section from a Markdown file
```bash
md-utils extract --name "Introduction" document.md
```

### Extract and save section to a file
```bash
md-utils extract --index 2 document.md --output section.md
```

### Extract specific line range from a file
```bash
md-utils lines document.md --start 10 --end 20
```

### Extract lines with line numbers
```bash
md-utils lines document.md -s 1 -e 50 --numbered
```

## Table of Contents Generation

### Generate table of contents
```bash
md-utils toc document.md
```

### Generate TOC with specific heading levels
```bash
md-utils toc document.md --min-level 2 --max-level 4
```

### Generate TOC in JSON format
```bash
md-utils toc document.md --format json-pretty
```

## Heading Manipulation

### Promote a heading (decrease level)
```bash
md-utils promote --index 3 document.md --in-place
```

### Demote a heading (increase level)
```bash
md-utils demote --index 2 document.md --in-place
```

## Frontmatter Operations

### Basic Frontmatter Management

#### Get frontmatter value (JSON, default)
```bash
md-utils fm get --key title document.md
# Output: [{"path":"/abs/path/document.md","value":"My Title"}]
```

The default format is JSON — an array of objects with `path` and (optionally) `value`:
- `"value"` present → key found; typed value (string, number, bool, array, object)
- `"value": null` → key exists with a YAML null value
- `"value"` absent → key not present in frontmatter

```bash
# Get values from multiple files and filter with jq
md-utils fm get --key title posts/ | jq '.[] | select(has("value")) | .value'

# Find files where the key is missing
md-utils fm get --key title posts/ | jq '.[] | select(has("value") | not) | .path'
```

#### Get frontmatter value as plain text
```bash
# Scalar
md-utils fm get --key title --format inline document.md

# Array as bullet list
md-utils fm get --key tags --format bullets document.md

# Array as numbered list
md-utils fm get --key tags --format numbered-list document.md
```

#### Set frontmatter value
```bash
md-utils fm set --key author --value "Jane Doe" document.md
```

#### Check if frontmatter key exists
```bash
md-utils fm has --key published document.md
```

#### List all frontmatter keys
```bash
md-utils fm list document.md
```

### Frontmatter Search and Retrieval

#### Search files by frontmatter value
```bash
md-utils fm search --key status --value published posts/
```

### Frontmatter Array Operations

#### Add tag to frontmatter array
```bash
md-utils fm array append --key tags --value tutorial posts/*.md
```

#### Check if array contains value
```bash
md-utils fm array contains --key tags --value swift posts/
```

#### Remove value from array
```bash
md-utils fm array remove --key tags --value draft posts/*.md
```

### Frontmatter Utilities

#### Sort frontmatter keys alphabetically
```bash
md-utils fm sort-keys document.md
```

#### Dump all frontmatter as YAML
```bash
md-utils fm dump document.md
```

## Conversion Operations

### Convert Markdown to plain text
```bash
md-utils convert to-text document.md
```

## Advanced Operations

### Find files with specific tag and publish them
```bash
md-utils fm array contains --key tags --value swift posts/ | xargs md-utils fm set --key published --value true
```

### Extract TOC and pipe to file
```bash
md-utils toc document.md --format md-bullet-links > toc.md
```

### Find files missing a frontmatter key
```bash
find posts/ -name "*.md" | xargs -I {} sh -c 'md-utils fm has --key author {} || echo {}'
```

### Batch update author across all files
```bash
md-utils fm set --key author --value "Jane Doe" posts/*.md
```

### Extract specific section and convert to text
```bash
md-utils extract --name "API Reference" document.md | md-utils convert to-text
```

### Search for files with status "draft" and list them
```bash
md-utils fm search --key status --value draft . | xargs ls -l
```

### Get all titles from multiple files
```bash
md-utils fm get --key title posts/*.md | jq '.[] | select(has("value")) | [.path, .value] | join(": ")'
```

### Extract lines and search for pattern
```bash
md-utils lines document.md -s 1 -e 100 | grep -i "important"
```

### Create TOC for all markdown files in directory
```bash
for file in docs/*.md; do echo "## $file"; md-utils toc "$file"; echo; done
```

### Find files with multiple tags
```bash
md-utils fm array contains --key tags --value swift posts/ | xargs -I {} sh -c 'md-utils fm array contains --key tags --value tutorial {} && echo {}'
```

### Read file metadata
```bash
md-utils meta read document.md
```

### Recursively update frontmatter in directory
```bash
md-utils fm set --key updated --value "2026-01-24" --recursive posts/
```

