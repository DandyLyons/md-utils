# fm list Command

List all frontmatter keys in Markdown files.

## Overview

The `fm list` command displays all keys present in a document's frontmatter. This is useful for discovering schema, validation, and exploring document structure.

## Syntax

```bash
md-utils fm list [options] <files>
```

## Examples

### Basic Usage

List keys from a single file:

```bash
# Create sample file
cat > post.md << 'EOF'
---
title: My Post
author: Jane Doe
date: 2024-01-24
tags: [swift, programming]
published: true
---

# Content
EOF

# List all keys
md-utils fm list post.md
```

**Output:**
```
title
author
date
tags
published
```

### Multiple Files

```bash
# List keys from multiple files
md-utils fm list post1.md post2.md post3.md

# Each file's output is shown separately
```

**Output:**
```
post1.md:
title
author
tags

post2.md:
title
date
published
```

### Recursive Processing

```bash
# List keys from all files
md-utils --recursive fm list content/

# Unique keys across all files
md-utils -r fm list content/ | sort | uniq
```

## Common Use Cases

### Schema Discovery

Discover what fields are used:

```bash
# Find all unique keys across posts
md-utils -r fm list posts/ | sort | uniq

# Count occurrences of each key
md-utils -r fm list posts/ | sort | uniq -c | sort -rn
```

**Example output:**
```
 150 title
 150 date
 148 author
 120 tags
  45 draft
  23 categories
```

### Validation

Check for required fields:

```bash
#!/bin/bash
# Validate required fields

required=("title" "date" "author")

for file in posts/*.md; do
    keys=$(md-utils fm list "$file")
    missing=()

    for field in "${required[@]}"; do
        if ! echo "$keys" | grep -q "^${field}$"; then
            missing+=("$field")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "$file missing: ${missing[*]}"
    fi
done
```

### Finding Inconsistencies

Identify files with unusual fields:

```bash
#!/bin/bash
# Find files with non-standard fields

# Get common fields
common=$(md-utils -r fm list posts/ | sort | uniq -c | \\
         awk '$1 > 100 {print $2}')

# Check each file
for file in posts/*.md; do
    keys=$(md-utils fm list "$file")

    for key in $keys; do
        if ! echo "$common" | grep -q "^${key}$"; then
            echo "$file has unusual field: $key"
        fi
    done
done
```

### Schema Documentation

Generate schema documentation:

```bash
#!/bin/bash
# Document frontmatter schema

echo "# Frontmatter Schema"
echo ""
echo "## Fields"
echo ""

md-utils -r fm list posts/ | sort | uniq | while read -r key; do
    count=$(md-utils -r fm list posts/ | grep -c "^${key}$")
    total=$(ls posts/*.md | wc -l)
    percentage=$((count * 100 / total))

    echo "### $key"
    echo ""
    echo "- Used in: $count / $total files ($percentage%)"

    # Get sample value
    for file in posts/*.md; do
        if md-utils fm list "$file" | grep -q "^${key}$"; then
            sample=$(md-utils fm get --key "$key" "$file" 2>/dev/null)
            echo "- Example: \`$sample\`"
            break
        fi
    done

    echo ""
done
```

## Pipeline Usage

### Filter by Field Presence

```bash
# Find files with specific field
for file in posts/*.md; do
    if md-utils fm list "$file" | grep -q "^draft$"; then
        echo "$file has draft field"
    fi
done

# Find files missing a field
for file in posts/*.md; do
    if ! md-utils fm list "$file" | grep -q "^author$"; then
        echo "$file missing author"
    fi
done
```

### Compare Schemas

```bash
#!/bin/bash
# Compare two files' schemas

file1="post1.md"
file2="post2.md"

keys1=$(md-utils fm list "$file1" | sort)
keys2=$(md-utils fm list "$file2" | sort)

echo "Only in $file1:"
comm -23 <(echo "$keys1") <(echo "$keys2")

echo ""
echo "Only in $file2:"
comm -13 <(echo "$keys1") <(echo "$keys2")

echo ""
echo "In both:"
comm -12 <(echo "$keys1") <(echo "$keys2")
```

### Field Coverage Report

```bash
#!/bin/bash
# Generate field coverage report

echo "Field Coverage Report"
echo "===================="
echo ""

total_files=$(ls posts/*.md | wc -l)

md-utils -r fm list posts/ | sort | uniq | while read -r key; do
    count=$(for file in posts/*.md; do
        md-utils fm list "$file" | grep -q "^${key}$" && echo 1
    done | wc -l)

    percentage=$((count * 100 / total_files))

    printf "%-20s %3d / %3d (%3d%%)\n" "$key:" "$count" "$total_files" "$percentage"
done | sort -t'(' -k2 -rn
```

## Advanced Examples

### Required vs Optional Fields

```bash
#!/bin/bash
# Categorize fields by usage

total=$(ls posts/*.md | wc -l)
threshold=90  # 90% = required

echo "Required fields (>$threshold% coverage):"
md-utils -r fm list posts/ | sort | uniq -c | while read -r count key; do
    percentage=$((count * 100 / total))
    if [ $percentage -gt $threshold ]; then
        echo "  $key ($percentage%)"
    fi
done

echo ""
echo "Optional fields (<=$threshold% coverage):"
md-utils -r fm list posts/ | sort | uniq -c | while read -r count key; do
    percentage=$((count * 100 / total))
    if [ $percentage -le $threshold ]; then
        echo "  $key ($percentage%)"
    fi
done
```

### Migration Planning

```bash
#!/bin/bash
# Find deprecated fields

deprecated=("old_field" "legacy_field" "deprecated_field")

echo "Files using deprecated fields:"
for file in posts/*.md; do
    keys=$(md-utils fm list "$file")
    found=()

    for field in "${deprecated[@]}"; do
        if echo "$keys" | grep -q "^${field}$"; then
            found+=("$field")
        fi
    done

    if [ ${#found[@]} -gt 0 ]; then
        echo "  $file: ${found[*]}"
    fi
done
```

### Schema Diff

```bash
#!/bin/bash
# Compare schemas between directories

echo "Schema differences between directories:"
echo ""

schema1=$(md-utils -r fm list dir1/ | sort | uniq)
schema2=$(md-utils -r fm list dir2/ | sort | uniq)

echo "Only in dir1/:"
comm -23 <(echo "$schema1") <(echo "$schema2")

echo ""
echo "Only in dir2/:"
comm -13 <(echo "$schema1") <(echo "$schema2")

echo ""
echo "In both:"
comm -12 <(echo "$schema1") <(echo "$schema2")
```

## Integration Examples

### With JSON Processing

```bash
#!/bin/bash
# Generate JSON schema

echo "{"
echo '  "fields": {'

md-utils -r fm list posts/ | sort | uniq | while read -r key; do
    # Get sample value to infer type
    for file in posts/*.md; do
        if value=$(md-utils fm get --key "$key" "$file" --format json 2>/dev/null); then
            # Infer type from JSON
            if echo "$value" | jq -e 'type == "string"' >/dev/null 2>&1; then
                type="string"
            elif echo "$value" | jq -e 'type == "number"' >/dev/null 2>&1; then
                type="number"
            elif echo "$value" | jq -e 'type == "boolean"' >/dev/null 2>&1; then
                type="boolean"
            elif echo "$value" | jq -e 'type == "array"' >/dev/null 2>&1; then
                type="array"
            else
                type="unknown"
            fi

            echo "    \"$key\": {\"type\": \"$type\"},"
            break
        fi
    done
done

echo "  }"
echo "}"
```

### Quality Checks

```bash
#!/bin/bash
# Quality check for frontmatter completeness

echo "Frontmatter Quality Report"
echo "=========================="
echo ""

total=$(ls posts/*.md | wc -l)
required=("title" "date" "author")

# Check required fields
echo "Required Fields Coverage:"
for field in "${required[@]}"; do
    count=0
    for file in posts/*.md; do
        if md-utils fm list "$file" | grep -q "^${field}$"; then
            ((count++))
        fi
    done

    percentage=$((count * 100 / total))
    echo "  $field: $count/$total ($percentage%)"

    if [ $percentage -lt 100 ]; then
        echo "    Missing in:"
        for file in posts/*.md; do
            if ! md-utils fm list "$file" | grep -q "^${field}$"; then
                echo "      - $file"
            fi
        done
    fi
done
```

## See Also

- <doc:FMGet>
- <doc:FMSet>
- <doc:FMDump>
- <doc:Workflows/GeneralMarkdown/QualityControl>
