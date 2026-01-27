# body Command

Extract Markdown body content without frontmatter.

## Overview

The `body` command extracts the body content from Markdown documents, removing the YAML frontmatter. This is useful for previewing content, converting to other formats, or analyzing document text without metadata.

## Syntax

```bash
md-utils body [options] <files>
```

## Options

### --format

Output format for the body content.

**Values:**
- `markdown` (default): Preserve Markdown formatting
- `plain-text`: Convert to plain text

```bash
# Get body as Markdown (default)
md-utils body post.md

# Explicit Markdown format
md-utils body --format markdown post.md

# Convert to plain text
md-utils body --format plain-text post.md
```

## Examples

### Basic Usage

Extract body from a single file:

```bash
# Create a sample file
cat > post.md << 'EOF'
---
title: My Post
author: Jane Doe
---

# My Post

This is the **content** of my post.

## Section 1

Some text here.
EOF

# Extract body as Markdown
md-utils body post.md
```

**Output:**
```markdown
# My Post

This is the **content** of my post.

## Section 1

Some text here.
```

### Plain Text Conversion

Convert body to plain text:

```bash
md-utils body --format plain-text post.md
```

**Output:**
```
My Post

This is the content of my post.

Section 1

Some text here.
```

### Multiple Files

Process multiple files:

```bash
# Multiple explicit files
md-utils body post1.md post2.md post3.md

# Using wildcards
md-utils body posts/*.md

# Each file's output is separated
```

### Recursive Processing

Extract bodies from all files in a directory tree:

```bash
# Process all Markdown files recursively
md-utils --recursive body content/

# Output to directory (preserves structure)
md-utils --recursive body content/ --output bodies/
```

## Common Use Cases

### Preview Generation

Generate previews without frontmatter:

```bash
# Get first 5 lines of body for preview
md-utils body post.md | head -n 5

# Create preview file
md-utils body post.md --output preview.md
```

### Content Migration

Extract content when migrating between systems:

```bash
# Extract all post bodies
md-utils --recursive body content/posts/ --output migrated-content/

# Convert to plain text for import
md-utils -r body --format plain-text old-posts/ -o new-system/
```

### Word Count Analysis

Count words without counting frontmatter:

```bash
# Count words in body only
md-utils body --format plain-text post.md | wc -w

# Count for all posts
md-utils -r body --format plain-text posts/ | wc -w

# Per-file word counts
for file in posts/*.md; do
    count=$(md-utils body --format plain-text "$file" | wc -w)
    echo "$file: $count words"
done
```

### Content Extraction for Search

Extract plain text for search indexing:

```bash
# Extract all post bodies as plain text
md-utils --recursive body --format plain-text content/ --output search-index/

# Pipe to search indexer
md-utils body --format plain-text post.md | search-indexer --add
```

### Email Generation

Prepare content for email:

```bash
# Get plain text version for email
CONTENT=$(md-utils body --format plain-text post.md)

# Send via mail command
echo "$CONTENT" | mail -s "New Post" subscribers@example.com
```

### Combining with Other Tools

```bash
# Extract body and pipe to other Markdown tools
md-utils body post.md | pandoc -f markdown -t html

# Get body and search for pattern
md-utils body post.md | grep "important"

# Count lines in body
md-utils body post.md | wc -l

# Compare bodies of two files
diff <(md-utils body post1.md) <(md-utils body post2.md)
```

## Pipeline Usage

The `body` command is designed for pipeline use:

### Extract and Transform

```bash
# Extract → transform → save
md-utils body post.md | sed 's/old/new/g' > transformed.md

# Extract → convert → save
md-utils body post.md | pandoc -f markdown -t rst > post.rst
```

### Filter and Process

```bash
# Extract bodies of posts tagged "swift"
for file in posts/*.md; do
    if md-utils fm get --key tags "$file" | grep -q "swift"; then
        md-utils body "$file"
    fi
done
```

### Aggregate Content

```bash
# Combine all post bodies
md-utils --recursive body posts/ > combined.md

# Create a master document
echo "# All Posts" > master.md
md-utils -r body posts/ >> master.md
```

## Output Control

### Standard Output

By default, output goes to stdout:

```bash
# Print to console
md-utils body post.md

# Redirect to file
md-utils body post.md > body.md

# Pipe to other command
md-utils body post.md | less
```

### File Output

Save to a specific file:

```bash
# Single file
md-utils body post.md --output body.md

# Multiple files to directory
md-utils body posts/*.md --output bodies/

# Recursive to directory
md-utils -r body content/ --output extracted/
```

## Format Comparison

### Markdown Format

Preserves all Markdown formatting:

```bash
md-utils body --format markdown post.md
```

**Preserves:**
- Headings (`#`, `##`, etc.)
- **Bold** and *italic*
- Lists (ordered and unordered)
- Code blocks and inline code
- Links and images
- Blockquotes
- All other Markdown syntax

### Plain Text Format

Strips all formatting:

```bash
md-utils body --format plain-text post.md
```

**Removes:**
- Heading markers (`#`)
- **Bold** and *italic* markers
- List markers (`-`, `*`, `1.`)
- Code block delimiters
- Link brackets and URLs
- Image syntax
- Blockquote markers

**Preserves:**
- Text content
- Paragraph structure
- Basic spacing

## Batch Processing Scripts

### Process All Posts

```bash
#!/bin/bash
# extract-all-bodies.sh

INPUT_DIR="content/posts"
OUTPUT_DIR="extracted-bodies"

mkdir -p "$OUTPUT_DIR"

md-utils --recursive body "$INPUT_DIR" --output "$OUTPUT_DIR"

echo "Extracted bodies from $INPUT_DIR to $OUTPUT_DIR"
```

### Convert to Plain Text

```bash
#!/bin/bash
# convert-to-text.sh

for file in posts/*.md; do
    basename=$(basename "$file" .md)
    md-utils body --format plain-text "$file" > "text/${basename}.txt"
done

echo "Converted $(ls posts/*.md | wc -l) files"
```

### Selective Extraction

```bash
#!/bin/bash
# extract-published.sh

# Extract bodies only from published posts
for file in posts/*.md; do
    draft=$(md-utils fm get --key draft "$file")

    if [ "$draft" != "true" ]; then
        md-utils body "$file" > "published/$(basename "$file")"
    fi
done
```

## Error Handling

### Missing Frontmatter

If a file has no frontmatter, the entire file is treated as body:

```bash
# File without frontmatter
echo "# Just Content" > no-fm.md

# Returns entire file
md-utils body no-fm.md
# Output: # Just Content
```

### Invalid Files

```bash
# Non-existent file
md-utils body missing.md
# Error: File not found: missing.md

# Empty file
touch empty.md
md-utils body empty.md
# Output: (empty)
```

### Mixed Results

When processing multiple files, errors are reported but don't stop processing:

```bash
md-utils body post1.md missing.md post2.md
# Outputs: body of post1.md
# Error: File not found: missing.md
# Outputs: body of post2.md
```

## Integration Examples

### With Pandoc

```bash
# Convert body to HTML
md-utils body post.md | pandoc -f markdown -t html -o post.html

# Convert to PDF
md-utils body post.md | pandoc -f markdown -o post.pdf

# Convert multiple formats
for file in posts/*.md; do
    basename=$(basename "$file" .md)
    md-utils body "$file" | pandoc -f markdown -t html -o "html/${basename}.html"
    md-utils body "$file" | pandoc -f markdown -t docx -o "docx/${basename}.docx"
done
```

### With Static Site Generators

```bash
# Extract body for custom processor
md-utils body post.md | custom-processor > processed.html

# Combine with frontmatter for custom format
FRONTMATTER=$(md-utils fm dump --format json post.md)
BODY=$(md-utils body post.md)
echo "{\"metadata\": $FRONTMATTER, \"content\": \"$BODY\"}" | jq
```

### With Search Engines

```bash
# Index content in search engine
md-utils --recursive body --format plain-text posts/ | \\
    while IFS= read -r file; do
        # Index each file
        curl -X POST -d "$file" https://search-api.example.com/index
    done
```

## See Also

- <doc:TOCCommand>
- <doc:ToTextCommand>
- <doc:GlobalOptions>
- <doc:Workflows/GeneralMarkdown/ContentMigration>
