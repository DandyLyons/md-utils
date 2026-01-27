# toc Command

Generate table of contents from Markdown headings.

## Overview

The `toc` command analyzes Markdown documents and generates a table of contents from their heading structure. It supports multiple output formats and provides options to control heading levels, formatting, and structure.

## Syntax

```bash
md-utils toc [options] <files>
```

## Options

### --format

Output format for the table of contents.

**Values:**
- `md-bullet-links` (default): Markdown bullet list with anchor links
- `plain`: Plain text hierarchical outline
- `json`: JSON array of heading objects
- `html`: HTML navigation list

```bash
# Default: Markdown with links
md-utils toc post.md

# Plain text outline
md-utils toc --format plain post.md

# JSON for processing
md-utils toc --format json post.md

# HTML navigation
md-utils toc --format html post.md
```

### --min-level

Minimum heading level to include (1-6):

```bash
# Skip h1, start with h2
md-utils toc --min-level 2 post.md

# Only h3 and deeper
md-utils toc --min-level 3 post.md
```

**Default**: 1

### --max-level

Maximum heading level to include (1-6):

```bash
# Only h1 and h2
md-utils toc --max-level 2 post.md

# Up to h4
md-utils toc --max-level 4 post.md
```

**Default**: 6

### --flat

Output flat list instead of hierarchical structure:

```bash
# Hierarchical (default)
md-utils toc post.md

# Flat list
md-utils toc --flat post.md
```

### --no-slugs

Don't generate URL-safe slug identifiers:

```bash
# With slugs (default, for links)
md-utils toc post.md

# Without slugs (faster, no links)
md-utils toc --no-slugs post.md
```

## Examples

### Basic TOC Generation

Generate a TOC from a document:

```bash
# Create sample document
cat > doc.md << 'EOF'
# Introduction

Welcome to the guide.

## Getting Started

### Prerequisites

### Installation

## Usage

### Basic Commands

### Advanced Features

## Troubleshooting
EOF

# Generate default TOC
md-utils toc doc.md
```

**Output:**
```markdown
- [Introduction](#introduction)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Installation](#installation)
  - [Usage](#usage)
    - [Basic Commands](#basic-commands)
    - [Advanced Features](#advanced-features)
  - [Troubleshooting](#troubleshooting)
```

### Format Examples

#### Markdown with Links (default)

```bash
md-utils toc --format md-bullet-links doc.md
```
```markdown
- [Introduction](#introduction)
  - [Getting Started](#getting-started)
    - [Installation](#installation)
```

#### Plain Text

```bash
md-utils toc --format plain doc.md
```
```
Introduction
  Getting Started
    Installation
```

#### JSON

```bash
md-utils toc --format json doc.md
```
```json
[
  {
    "level": 1,
    "text": "Introduction",
    "slug": "introduction"
  },
  {
    "level": 2,
    "text": "Getting Started",
    "slug": "getting-started"
  },
  {
    "level": 3,
    "text": "Installation",
    "slug": "installation"
  }
]
```

#### HTML

```bash
md-utils toc --format html doc.md
```
```html
<nav class="toc">
  <ul>
    <li><a href="#introduction">Introduction</a>
      <ul>
        <li><a href="#getting-started">Getting Started</a>
          <ul>
            <li><a href="#installation">Installation</a></li>
          </ul>
        </li>
      </ul>
    </li>
  </ul>
</nav>
```

### Level Filtering

#### Skip h1 (Common Pattern)

```bash
# Skip main title, show sections
md-utils toc --min-level 2 doc.md
```
```markdown
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Usage](#usage)
```

#### Limit Depth

```bash
# Show only h2-h3
md-utils toc --min-level 2 --max-level 3 doc.md
```

#### Top-Level Only

```bash
# Only h1 headings
md-utils toc --max-level 1 doc.md
```

## Common Use Cases

### Documentation Navigation

Add TOC to documentation files:

```bash
# Generate TOC
md-utils toc README.md > toc.md

# Insert into document
cat toc.md content.md > README-with-toc.md
```

### Site Map Generation

Create site navigation from all pages:

```bash
# Generate TOCs for all docs
md-utils --recursive toc docs/ --output toc/

# Combine into site map
md-utils -r toc --format plain docs/ > sitemap.txt
```

### Content Structure Analysis

Analyze document structure:

```bash
# Get structure as JSON
md-utils toc --format json doc.md | jq

# Check heading depth
md-utils toc --format json doc.md | jq 'map(.level) | max'

# Count headings per level
md-utils toc --format json doc.md | \\
    jq 'group_by(.level) | map({level: .[0].level, count: length})'
```

### Hugo/Jekyll Integration

Generate navigation for static sites:

```bash
# Generate TOC for each post
for file in content/posts/*.md; do
    toc_file="layouts/toc/$(basename "$file")"
    md-utils toc --format html --min-level 2 "$file" > "$toc_file"
done

# Include in templates
```

### Validation

Check document structure:

```bash
#!/bin/bash
# validate-structure.sh

file="$1"

# Check if document has h1
h1_count=$(md-utils toc --format json "$file" | jq '[.[] | select(.level == 1)] | length')

if [ "$h1_count" -eq 0 ]; then
    echo "Warning: $file missing h1 heading"
fi

# Check max depth
max_depth=$(md-utils toc --format json "$file" | jq 'map(.level) | max')

if [ "$max_depth" -gt 4 ]; then
    echo "Warning: $file has deep nesting (level $max_depth)"
fi
```

## Pipeline Usage

### Combine with Other Commands

```bash
# Get TOC + body
echo "## Table of Contents" > output.md
md-utils toc post.md >> output.md
echo "" >> output.md
md-utils body post.md >> output.md

# Filter specific sections
md-utils toc --format plain post.md | grep "API"

# Process TOC with jq
md-utils toc --format json post.md | \\
    jq '[.[] | select(.level <= 3)]'
```

### Generate Multiple Formats

```bash
#!/bin/bash
# generate-tocs.sh

file="$1"
basename=$(basename "$file" .md)

# Generate all formats
md-utils toc "$file" > "toc/${basename}-md.md"
md-utils toc --format plain "$file" > "toc/${basename}-plain.txt"
md-utils toc --format json "$file" > "toc/${basename}.json"
md-utils toc --format html "$file" > "toc/${basename}.html"
```

### Batch Processing

```bash
# Generate TOCs for all docs
md-utils --recursive toc docs/ --output toc-files/

# Process with custom formatting
md-utils -r toc --format json docs/ | \\
    jq -s 'flatten | group_by(.text) | map({heading: .[0].text, count: length})'
```

## Advanced Examples

### Custom TOC Insertion

Insert TOC into document:

```bash
#!/bin/bash
# insert-toc.sh

file="$1"

# Generate TOC
toc=$(md-utils toc --min-level 2 "$file")

# Create new file with TOC
{
    # Copy frontmatter and title
    md-utils fm dump --format raw --include-delimiters "$file"
    md-utils toc --max-level 1 "$file"

    echo ""
    echo "## Table of Contents"
    echo "$toc"
    echo ""

    # Copy body (skip h1)
    md-utils body "$file" | tail -n +3
} > "${file%.md}-with-toc.md"
```

### Section Extraction

Extract specific sections based on TOC:

```bash
# Get all "API" sections
md-utils toc --format json doc.md | \\
    jq -r '.[] | select(.text | contains("API")) | .slug'

# Find section starting positions
md-utils toc --format json doc.md | \\
    jq '.[] | {text: .text, slug: .slug}'
```

### Multi-File Navigation

Create master TOC for multiple files:

```bash
#!/bin/bash
# master-toc.sh

echo "# Master Table of Contents"
echo ""

for file in docs/*.md; do
    echo "## $(basename "$file" .md)"
    md-utils toc --min-level 2 --format plain "$file" | sed 's/^/  /'
    echo ""
done
```

## Format Details

### md-bullet-links

- Markdown bullet lists
- Anchor links to headings
- Hierarchical indentation
- GitHub-compatible

### plain

- Plain text only
- Hierarchical indentation
- No links or formatting
- Easy to parse

### json

- Array of heading objects
- Each object: `{level, text, slug}`
- Easy to process programmatically
- Flat array (hierarchy in level property)

### html

- HTML5 `<nav>` element
- Nested `<ul>/<li>` lists
- Anchor links with `href`
- Ready for web pages

## Slug Generation

Slugs are URL-safe identifiers for headings:

| Heading | Generated Slug |
|---------|----------------|
| Getting Started | `getting-started` |
| API v2.0 | `api-v20` |
| FAQ & Support | `faq-support` |
| 2024 Updates | `2024-updates` |

Algorithm:
1. Lowercase
2. Replace spaces with hyphens
3. Remove special characters
4. Ensure uniqueness

## Performance Tips

### Faster Processing

```bash
# Skip slug generation when not needed
md-utils toc --no-slugs --format plain doc.md

# Limit levels for faster parsing
md-utils toc --max-level 3 doc.md

# Process in parallel
find docs/ -name "*.md" -print0 | \\
    xargs -0 -P 4 -I {} md-utils toc {} -o toc/{}.toc
```

### Caching

```bash
# Cache TOCs for unchanged files
for file in docs/*.md; do
    toc_file="cache/$(basename "$file" .md).toc"

    if [ "$file" -nt "$toc_file" ]; then
        md-utils toc "$file" > "$toc_file"
    fi
done
```

## See Also

- <doc:BodyCommand>
- <doc:GlobalOptions>
- <doc:Workflows/GeneralMarkdown/DocumentationMaint>
