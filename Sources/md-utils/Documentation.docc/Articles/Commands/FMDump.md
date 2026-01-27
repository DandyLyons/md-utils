# fm dump Command

Export frontmatter in various formats.

## Overview

The `fm dump` command exports the entire frontmatter block in multiple output formats. This is useful for migration, backup, processing with other tools, and converting between formats.

## Syntax

```bash
md-utils fm dump [options] <files>
```

## Options

### --format

Output format for the frontmatter:

**Values:**
- `json-pretty` (default): Formatted JSON with indentation
- `json`: Compact JSON (single line)
- `yaml`: YAML format
- `raw`: Raw YAML as it appears in file
- `plist`: Property list XML format

```bash
# Pretty JSON (default)
md-utils fm dump post.md

# Compact JSON
md-utils fm dump --format json post.md

# YAML
md-utils fm dump --format yaml post.md

# Raw YAML (preserves original formatting)
md-utils fm dump --format raw post.md

# Property list
md-utils fm dump --format plist post.md
```

### --include-delimiters

Include `---` delimiters in raw format:

```bash
# Without delimiters (default)
md-utils fm dump --format raw post.md

# With delimiters
md-utils fm dump --format raw --include-delimiters post.md
```

## Examples

### JSON Pretty (Default)

```bash
cat > post.md << 'EOF'
---
title: My Post
author: Jane Doe
tags: [swift, programming]
published: true
count: 42
---
EOF

md-utils fm dump post.md
```

**Output:**
```json
{
  "title": "My Post",
  "author": "Jane Doe",
  "tags": ["swift", "programming"],
  "published": true,
  "count": 42
}
```

### Compact JSON

```bash
md-utils fm dump --format json post.md
```

**Output:**
```json
{"title":"My Post","author":"Jane Doe","tags":["swift","programming"],"published":true,"count":42}
```

### YAML Format

```bash
md-utils fm dump --format yaml post.md
```

**Output:**
```yaml
title: My Post
author: Jane Doe
tags:
  - swift
  - programming
published: true
count: 42
```

### Raw Format

```bash
md-utils fm dump --format raw post.md
```

**Output:**
```yaml
title: My Post
author: Jane Doe
tags: [swift, programming]
published: true
count: 42
```

### Raw with Delimiters

```bash
md-utils fm dump --format raw --include-delimiters post.md
```

**Output:**
```yaml
---
title: My Post
author: Jane Doe
tags: [swift, programming]
published: true
count: 42
---
```

## Common Use Cases

### Data Export

Export all frontmatter to JSON:

```bash
# Single file
md-utils fm dump --format json post.md > post-metadata.json

# All posts
for file in posts/*.md; do
    basename=$(basename "$file" .md)
    md-utils fm dump --format json "$file" > "metadata/${basename}.json"
done

# Combined export
echo "[" > all-metadata.json
first=true
for file in posts/*.md; do
    if [ "$first" = false ]; then
        echo "," >> all-metadata.json
    fi
    md-utils fm dump --format json "$file" >> all-metadata.json
    first=false
done
echo "]" >> all-metadata.json
```

### Format Conversion

Convert between formats:

```bash
#!/bin/bash
# Convert YAML frontmatter to TOML

file="$1"

# Get as JSON
json=$(md-utils fm dump --format json "$file")

# Convert JSON to TOML (using external tool)
toml=$(echo "$json" | json2toml)

# Create new file
{
    echo "+++"
    echo "$toml"
    echo "+++"
    md-utils body "$file"
} > "${file%.md}.toml.md"
```

### Migration

Migrate frontmatter to database:

```bash
#!/bin/bash
# Import to database

for file in posts/*.md; do
    json=$(md-utils fm dump --format json "$file")

    # Insert to database
    echo "INSERT INTO posts (filename, metadata) VALUES " \\
         "('$file', '$json');" | sqlite3 posts.db
done
```

### Backup

Backup all frontmatter:

```bash
#!/bin/bash
# Backup frontmatter separately

backup_dir="frontmatter-backup-$(date +%Y%m%d)"
mkdir -p "$backup_dir"

md-utils -r fm dump --format yaml content/ | \\
    while IFS=: read -r file _; do
        mkdir -p "$backup_dir/$(dirname "$file")"
        md-utils fm dump --format yaml "$file" > "$backup_dir/${file%.md}.yaml"
    done
```

### API Integration

Send metadata to API:

```bash
#!/bin/bash
# Sync metadata to API

for file in posts/*.md; do
    json=$(md-utils fm dump --format json "$file")

    # POST to API
    curl -X POST \\
         -H "Content-Type: application/json" \\
         -d "$json" \\
         https://api.example.com/metadata
done
```

## Pipeline Usage

### Process with jq

```bash
# Extract specific fields
md-utils fm dump --format json post.md | jq '{title, author}'

# Filter
md-utils fm dump --format json post.md | jq 'select(.published == true)'

# Transform
md-utils fm dump --format json post.md | \\
    jq '{title, slug: (.title | gsub(" "; "-") | ascii_downcase)}'

# Combine multiple files
for file in posts/*.md; do
    md-utils fm dump --format json "$file"
done | jq -s '.'
```

### Analyze Metadata

```bash
#!/bin/bash
# Analyze frontmatter across all posts

echo "Metadata Analysis"
echo "================="

# Collect all metadata
all_metadata=$(for file in posts/*.md; do
    md-utils fm dump --format json "$file"
done | jq -s '.')

# Count posts by author
echo ""
echo "Posts by author:"
echo "$all_metadata" | jq -r '.[].author' | sort | uniq -c | sort -rn

# Most common tags
echo ""
echo "Most common tags:"
echo "$all_metadata" | jq -r '.[].tags[]' | sort | uniq -c | sort -rn | head -10

# Average word count (if available)
echo ""
echo "Statistics:"
echo "$all_metadata" | jq 'map(.wordCount) | {
    avg: (add / length),
    min: min,
    max: max
}'
```

### Validation

```bash
#!/bin/bash
# Validate frontmatter against schema

schema='{"type":"object","required":["title","date","author"]}'

for file in posts/*.md; do
    json=$(md-utils fm dump --format json "$file")

    # Validate with ajv-cli or similar
    if ! echo "$json" | ajv validate -s <(echo "$schema"); then
        echo "$file: Invalid frontmatter"
    fi
done
```

## Format Comparison

### JSON vs YAML

**JSON** (structured, machine-readable):
- Easy to parse programmatically
- Works with jq and other JSON tools
- Compact representation
- Requires escaping for special characters

**YAML** (human-readable):
- More readable for humans
- Native frontmatter format
- Supports comments
- Can be more compact for simple data

### When to Use Each Format

**json-pretty**:
- Human review and editing
- Debugging frontmatter issues
- Documentation

**json**:
- API integration
- Database storage
- Processing with jq
- Minimal file size

**yaml**:
- Migrating between Markdown systems
- Editing frontmatter externally
- Creating templates

**raw**:
- Exact copy of original
- Preserving formatting
- Backup purposes

**plist**:
- macOS/iOS integration
- Property list editors
- Apple ecosystem tools

## Advanced Examples

### Merge Metadata

```bash
#!/bin/bash
# Merge external metadata into frontmatter

file="post.md"
external_data="metadata.json"

# Get current frontmatter
current=$(md-utils fm dump --format json "$file")

# Merge with external data
merged=$(jq -s '.[0] * .[1]' <(echo "$current") "$external_data")

# Update frontmatter (requires setting each field)
echo "$merged" | jq -r 'to_entries | .[] | "\\(.key)=\\(.value)"' | \\
    while IFS='=' read -r key value; do
        md-utils fm set --key "$key" --value "$value" "$file" -i
    done
```

### Diff Frontmatter

```bash
#!/bin/bash
# Compare frontmatter between two files

file1="post-v1.md"
file2="post-v2.md"

diff -u \\
    <(md-utils fm dump --format yaml "$file1") \\
    <(md-utils fm dump --format yaml "$file2")
```

### Generate TypeScript Types

```bash
#!/bin/bash
# Generate TypeScript interface from frontmatter

echo "interface PostFrontmatter {"

md-utils -r fm dump --format json posts/ | \\
    jq -s '
        map(to_entries | map({key: .key, type: (.value | type)})) |
        flatten |
        group_by(.key) |
        map({key: .[0].key, type: (.[].type | unique | join(" | "))}) |
        .[] |
        "  \(.key): \(.type);"
    ' -r

echo "}"
```

### Create Search Index

```bash
#!/bin/bash
# Build search index from metadata

echo "Building search index..."

index_file="search-index.json"

echo "[" > "$index_file"
first=true

for file in posts/*.md; do
    if [ "$first" = false ]; then
        echo "," >> "$index_file"
    fi

    # Get metadata
    metadata=$(md-utils fm dump --format json "$file")

    # Get plain text content
    content=$(md-utils body --format plain-text "$file" | head -c 500)

    # Combine
    echo "{" >> "$index_file"
    echo '  "file": "'"$file"'",' >> "$index_file"
    echo '  "metadata":' "$metadata," >> "$index_file"
    echo '  "preview": "'"$content"'"' >> "$index_file"
    echo "}" >> "$index_file"

    first=false
done

echo "]" >> "$index_file"

echo "Search index created: $index_file"
```

## See Also

- <doc:FMGet>
- <doc:FMSet>
- <doc:FMList>
- <doc:GlobalOptions>
- <doc:Workflows/GeneralMarkdown/ContentMigration>
