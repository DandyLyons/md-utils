# convert to-text Command

Convert Markdown to plain text.

## Overview

The `convert to-text` command converts Markdown documents to plain text, stripping all formatting while preserving content structure. This is useful for previews, search indexing, accessibility, and content analysis.

## Syntax

```bash
md-utils convert to-text [options] <files>
```

## Options

### --block-separator

String used to separate block elements:

```bash
# Double newlines (default)
md-utils convert to-text post.md

# Single newlines (compact)
md-utils convert to-text --block-separator $'\n' post.md

# Custom separator
md-utils convert to-text --block-separator "---" post.md
```

**Default**: `\n\n` (double newline)

### --indent-lists

Control list item indentation:

```bash
# With indentation (default)
md-utils convert to-text post.md

# No indentation (flat)
md-utils convert to-text --no-indent-lists post.md
```

**Default**: true (lists are indented)

### --preserve-code-blocks

Control code block preservation:

```bash
# Preserve code blocks (default)
md-utils convert to-text post.md

# Strip code blocks
md-utils convert to-text --no-preserve-code-blocks post.md
```

**Default**: true (code blocks preserved)

## Examples

### Basic Conversion

Convert a simple document:

```bash
cat > post.md << 'EOF'
---
title: Sample Post
---

# Welcome

This is **bold** and this is *italic*.

## Features

- First item
- Second item
- Third item

Visit [our site](https://example.com).
EOF

md-utils convert to-text post.md
```

**Output:**
```
Welcome

This is bold and this is italic.

Features

First item
Second item
Third item

Visit our site.
```

### Compact Mode

Single-line breaks:

```bash
md-utils convert to-text --block-separator $'\n' post.md
```

**Output:**
```
Welcome
This is bold and this is italic.
Features
First item
Second item
Third item
Visit our site.
```

### No List Indentation

Flatten list structure:

```bash
md-utils convert to-text --no-indent-lists post.md
```

**Output:**
```
Features

First item
Second item
Third item
```

## Common Use Cases

### Preview Generation

```bash
# Generate 200-character preview
md-utils convert to-text post.md | head -c 200

# Preview without code
md-utils convert to-text --no-preserve-code-blocks post.md | head -n 5
```

### Word Counting

```bash
# Count words accurately
md-utils convert to-text post.md | wc -w

# Word count for all posts
md-utils -r convert to-text posts/ | wc -w

# Per-file word counts
for file in posts/*.md; do
    count=$(md-utils convert to-text "$file" | wc -w)
    echo "$(basename "$file"): $count words"
done
```

### Search Indexing

```bash
# Extract plain text for search
md-utils -r convert to-text content/ --output search-index/

# Pipe to indexer
md-utils convert to-text post.md | search-tool --index
```

### Content Analysis

```bash
# Analyze reading level
md-utils convert to-text post.md | readability-tool

# Check spelling
md-utils convert to-text post.md | aspell list

# Find long sentences
md-utils convert to-text post.md | \\
    tr '.' '\n' | awk 'length > 100'
```

### Email Content

```bash
# Convert to email-friendly text
md-utils convert to-text --block-separator $'\n\n' post.md | \\
    fold -s -w 72 > email-body.txt

# Send via mail
md-utils convert to-text post.md | mail -s "Newsletter" list@example.com
```

## Batch Processing

### Convert All Files

```bash
# Convert recursively
md-utils -r convert to-text content/ --output plain-text/

# Compact version
md-utils -r convert to-text --block-separator $'\n' \\
         content/ -o compact/
```

### Selective Conversion

```bash
#!/bin/bash
# Convert only published posts

for file in posts/*.md; do
    draft=$(md-utils fm get --key draft "$file")

    if [ "$draft" != "true" ]; then
        basename=$(basename "$file" .md)
        md-utils convert to-text "$file" > "text/${basename}.txt"
    fi
done
```

### Format Pipeline

```bash
#!/bin/bash
# Multi-format export

file="$1"
base=$(basename "$file" .md)

# Default format
md-utils convert to-text "$file" > "output/${base}.txt"

# Compact format
md-utils convert to-text --block-separator $'\n' "$file" \\
    > "output/${base}-compact.txt"

# No code blocks
md-utils convert to-text --no-preserve-code-blocks "$file" \\
    > "output/${base}-nocode.txt"
```

## Formatting Examples

### With vs Without Code Blocks

**Input:**
````markdown
## Example

Here's some code:

```python
def hello():
    print("Hello")
```

And more text.
````

**With code blocks (default):**
```
Example

Here's some code:

def hello():
    print("Hello")

And more text.
```

**Without code blocks:**
```
Example

Here's some code:

And more text.
```

### List Indentation

**Input:**
```markdown
- Top level
  - Nested item
  - Another nested
- Back to top
```

**With indentation (default):**
```
Top level
  Nested item
  Another nested
Back to top
```

**Without indentation:**
```
Top level
Nested item
Another nested
Back to top
```

## Integration Examples

### With Translation Tools

```bash
# Extract text for translation
md-utils convert to-text en/post.md > translate-input.txt

# Translate
translate-tool < translate-input.txt > translated.txt

# Reconstruct document (manually combine with frontmatter)
```

### With Readability Tools

```bash
# Check readability score
md-utils convert to-text post.md | \\
    textstat --flesch-reading-ease

# Analyze complexity
md-utils convert to-text post.md | style-check
```

### With Text Processing

```bash
# Extract keywords
md-utils convert to-text post.md | \\
    tr '[:space:]' '\n' | \\
    sort | uniq -c | sort -rn | head -20

# Find long words
md-utils convert to-text post.md | \\
    tr '[:space:]' '\n' | \\
    awk 'length > 12'

# Sentence analysis
md-utils convert to-text post.md | \\
    tr '.' '\n' | \\
    awk '{print length, $0}' | \\
    sort -rn
```

## Advanced Usage

### Custom Processing

```bash
#!/bin/bash
# Custom text processing pipeline

file="$1"

# Convert to text
text=$(md-utils convert to-text "$file")

# Remove extra whitespace
cleaned=$(echo "$text" | tr -s ' ')

# Wrap lines
wrapped=$(echo "$cleaned" | fold -s -w 80)

# Output
echo "$wrapped"
```

### Comparison

```bash
# Compare text content of two documents
diff <(md-utils convert to-text v1.md) \\
     <(md-utils convert to-text v2.md)

# Show what changed in content
md-utils convert to-text old.md > old.txt
md-utils convert to-text new.md > new.txt
diff -u old.txt new.txt
```

### Statistics

```bash
#!/bin/bash
# Document statistics

file="$1"

# Convert to plain text
text=$(md-utils convert to-text "$file")

# Calculate stats
words=$(echo "$text" | wc -w)
lines=$(echo "$text" | wc -l)
chars=$(echo "$text" | wc -c)

echo "Statistics for $file:"
echo "  Words: $words"
echo "  Lines: $lines"
echo "  Characters: $chars"
```

## See Also

- <doc:BodyCommand>
- <doc:GlobalOptions>
- <doc:Workflows/GeneralMarkdown/ContentMigration>
