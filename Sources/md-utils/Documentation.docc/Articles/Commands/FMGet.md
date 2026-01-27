# fm get Command

Read frontmatter values from Markdown files.

## Overview

The `fm get` command retrieves values from YAML frontmatter. It supports accessing simple values, arrays, nested objects, and can output in multiple formats.

## Syntax

```bash
md-utils fm get --key <key> [options] <files>
```

## Required Options

### --key

The frontmatter key to retrieve:

```bash
# Simple key
md-utils fm get --key title post.md

# Nested key (dot notation)
md-utils fm get --key author.name post.md

# Short form
md-utils fm get -k title post.md
```

## Optional Parameters

### --format

Output format for the value:

- `auto` (default): Detect type and format appropriately
- `json`: JSON format
- `yaml`: YAML format
- `raw`: Raw string value

```bash
# Auto-detect (default)
md-utils fm get --key tags post.md

# JSON format
md-utils fm get --key tags --format json post.md

# YAML format
md-utils fm get --key tags --format yaml post.md

# Raw string
md-utils fm get --key title --format raw post.md
```

## Examples

### Simple Values

```bash
# Create sample file
cat > post.md << 'EOF'
---
title: My Blog Post
author: Jane Doe
date: 2024-01-24
published: true
count: 42
---

# Content here
EOF

# Get string
md-utils fm get --key title post.md
# Output: My Blog Post

# Get boolean
md-utils fm get --key published post.md
# Output: true

# Get number
md-utils fm get --key count post.md
# Output: 42

# Get date
md-utils fm get --key date post.md
# Output: 2024-01-24
```

### Array Values

```bash
cat > post.md << 'EOF'
---
tags: [swift, programming, tutorial]
categories:
  - Development
  - Swift
---
EOF

# Get inline array
md-utils fm get --key tags post.md
# Output: ["swift", "programming", "tutorial"]

# Get block array
md-utils fm get --key categories post.md
# Output: ["Development", "Swift"]

# JSON format
md-utils fm get --key tags --format json post.md
# Output: ["swift","programming","tutorial"]
```

### Nested Values

```bash
cat > post.md << 'EOF'
---
author:
  name: Jane Doe
  email: jane@example.com
  social:
    twitter: "@janedoe"
    github: "janedoe"
---
EOF

# Get nested value (dot notation)
md-utils fm get --key author.name post.md
# Output: Jane Doe

# Get deeply nested value
md-utils fm get --key author.social.twitter post.md
# Output: @janedoe

# Get entire object
md-utils fm get --key author --format json post.md
# Output: {"name":"Jane Doe","email":"jane@example.com",...}
```

## Multiple Files

### Process Multiple Files

```bash
# Multiple explicit files
md-utils fm get --key title post1.md post2.md post3.md

# Using wildcards
md-utils fm get --key author posts/*.md

# Output shows each file:
# post1.md: First Post
# post2.md: Second Post
# post3.md: Third Post
```

### Recursive Processing

```bash
# Get all titles in directory tree
md-utils --recursive fm get --key title content/

# Filter results
md-utils -r fm get --key author posts/ | grep "Jane"

# Count unique authors
md-utils -r fm get --key author posts/ | sort | uniq | wc -l
```

## Common Use Cases

### Find Files by Value

```bash
# Find posts by specific author
md-utils fm get --key author posts/*.md | grep -l "Jane Doe"

# Find published posts
for file in posts/*.md; do
    if [ "$(md-utils fm get --key published "$file")" = "true" ]; then
        echo "$file"
    fi
done

# Find posts with specific tag
md-utils fm get --key tags posts/*.md | grep -l "swift"
```

### List All Values

```bash
# List all titles
md-utils -r fm get --key title posts/

# List all tags (flatten arrays)
md-utils -r fm get --key tags posts/ --format json | \\
    jq -r '.[]' | sort | uniq

# List all authors
md-utils -r fm get --key author posts/ | \\
    sed 's/.*: //' | sort | uniq
```

### Validation

```bash
#!/bin/bash
# Check required fields

required_fields=("title" "date" "author")

for file in posts/*.md; do
    missing=()

    for field in "${required_fields[@]}"; do
        if ! md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
            missing+=("$field")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "$file missing: ${missing[*]}"
    fi
done
```

### Content Analysis

```bash
# Count posts per author
md-utils -r fm get --key author posts/ | \\
    sed 's/.*: //' | sort | uniq -c

# Tag frequency
md-utils -r fm get --key tags posts/ --format json | \\
    jq -r '.[]' | sort | uniq -c | sort -rn

# Posts by year
md-utils -r fm get --key date posts/ | \\
    sed 's/.*: //' | cut -d- -f1 | sort | uniq -c
```

## Pipeline Usage

### Filter and Process

```bash
# Get titles of published posts
for file in posts/*.md; do
    if [ "$(md-utils fm get --key draft "$file")" != "true" ]; then
        md-utils fm get --key title "$file"
    fi
done

# Process posts by category
md-utils fm get --key category posts/*.md | \\
    while IFS=: read -r file category; do
        echo "Processing $category: $file"
    done
```

### JSON Processing

```bash
# Extract all metadata as JSON
for file in posts/*.md; do
    echo "{"
    echo "  \"file\": \"$file\","
    echo "  \"title\": \"$(md-utils fm get --key title "$file")\","
    echo "  \"author\": \"$(md-utils fm get --key author "$file")\","
    echo "  \"tags\": $(md-utils fm get --key tags "$file" --format json)"
    echo "}"
done | jq -s '.'
```

### Reporting

```bash
#!/bin/bash
# Generate content report

echo "Content Report"
echo "=============="
echo ""

echo "Total posts: $(ls posts/*.md | wc -l)"
echo ""

echo "Posts by author:"
md-utils -r fm get --key author posts/ | \\
    sed 's/.*: //' | sort | uniq -c | sort -rn
echo ""

echo "Most common tags:"
md-utils -r fm get --key tags posts/ --format json | \\
    jq -r '.[]' | sort | uniq -c | sort -rn | head -10
```

## Output Formats

### Auto Format (Default)

Automatically detects type:

```bash
md-utils fm get --key title post.md
# Output: My Title

md-utils fm get --key tags post.md
# Output: ["tag1", "tag2"]

md-utils fm get --key published post.md
# Output: true
```

### JSON Format

Always outputs valid JSON:

```bash
# String
md-utils fm get --key title --format json post.md
# Output: "My Title"

# Array
md-utils fm get --key tags --format json post.md
# Output: ["tag1","tag2"]

# Object
md-utils fm get --key author --format json post.md
# Output: {"name":"Jane","email":"jane@example.com"}
```

### YAML Format

Outputs YAML:

```bash
md-utils fm get --key author --format yaml post.md
# Output:
# name: Jane Doe
# email: jane@example.com
```

### Raw Format

Plain string (no quotes):

```bash
md-utils fm get --key title --format raw post.md
# Output: My Title
```

## Error Handling

### Missing Keys

```bash
# Key doesn't exist
md-utils fm get --key missing post.md
# Error: Key not found: missing

# Check if key exists
if md-utils fm get --key author post.md >/dev/null 2>&1; then
    echo "Author exists"
else
    echo "No author"
fi
```

### Invalid Files

```bash
# File not found
md-utils fm get --key title missing.md
# Error: File not found: missing.md

# Invalid frontmatter
md-utils fm get --key title invalid.md
# Error: Failed to parse frontmatter
```

### Mixed Results

When processing multiple files, errors don't stop processing:

```bash
md-utils fm get --key title post1.md missing.md post2.md
# Output: post1.md: Title One
# Error: File not found: missing.md
# Output: post2.md: Title Two
```

## Advanced Examples

### Conditional Processing

```bash
#!/bin/bash
# Process based on frontmatter value

for file in posts/*.md; do
    category=$(md-utils fm get --key category "$file" 2>/dev/null)

    case "$category" in
        "tutorial")
            echo "Processing tutorial: $file"
            # Custom processing
            ;;
        "news")
            echo "Processing news: $file"
            # Different processing
            ;;
    esac
done
```

### Data Export

```bash
#!/bin/bash
# Export to CSV

echo "file,title,author,date,tags"

md-utils -r fm get --key title posts/ | while IFS=: read -r file title; do
    author=$(md-utils fm get --key author "$file" 2>/dev/null || echo "Unknown")
    date=$(md-utils fm get --key date "$file" 2>/dev/null || echo "")
    tags=$(md-utils fm get --key tags --format json "$file" 2>/dev/null || echo "[]")

    echo "$file,$title,$author,$date,$tags"
done
```

### Migration

```bash
#!/bin/bash
# Find posts using old field names

echo "Posts needing migration:"

for file in posts/*.md; do
    if md-utils fm get --key old_field "$file" >/dev/null 2>&1; then
        echo "  $file"
    fi
done
```

## See Also

- <doc:FMSet>
- <doc:FMList>
- <doc:FMDump>
- <doc:GlobalOptions>
