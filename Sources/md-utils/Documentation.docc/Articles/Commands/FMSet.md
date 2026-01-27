# fm set Command

Set frontmatter values in Markdown files.

## Overview

The `fm set` command creates or updates frontmatter values. It supports setting simple values, arrays, nested objects, and can modify multiple files atomically.

## Syntax

```bash
md-utils fm set --key <key> --value <value> [options] <files>
```

## Required Options

### --key

The frontmatter key to set:

```bash
# Simple key
md-utils fm set --key title --value "New Title" post.md

# Nested key (dot notation)
md-utils fm set --key author.name --value "Jane" post.md

# Short form
md-utils fm set -k title -v "New Title" post.md
```

### --value

The value to set:

```bash
# String
md-utils fm set --key author --value "Jane Doe" post.md

# Boolean (use lowercase)
md-utils fm set --key published --value "true" post.md
md-utils fm set --key draft --value "false" post.md

# Number
md-utils fm set --key count --value "42" post.md

# Date (ISO format)
md-utils fm set --key date --value "2024-01-24" post.md

# Array (JSON format)
md-utils fm set --key tags --value '["swift","programming"]' post.md
```

## Output Control

By default, outputs modified content to stdout. Use global `--in-place` option to modify files directly:

```bash
# Output to stdout (preview)
md-utils fm set --key author --value "Jane" post.md

# Modify file in place
md-utils fm set --key author --value "Jane" post.md --in-place

# Short form
md-utils fm set -k author -v "Jane" post.md -i
```

## Examples

### Setting Simple Values

```bash
# Set string
md-utils fm set --key title --value "My Post" post.md --in-place

# Set boolean
md-utils fm set --key published --value "true" post.md -i

# Set number
md-utils fm set --key wordCount --value "1500" post.md -i

# Set date
md-utils fm set --key updated --value "$(date -I)" post.md -i
```

### Setting Arrays

```bash
# Set array (JSON format)
md-utils fm set --key tags --value '["swift", "programming"]' post.md -i

# Set single-item array
md-utils fm set --key categories --value '["tutorial"]' post.md -i

# Empty array
md-utils fm set --key tags --value '[]' post.md -i
```

### Setting Nested Values

```bash
# Set nested value (creates structure if needed)
md-utils fm set --key author.name --value "Jane Doe" post.md -i
md-utils fm set --key author.email --value "jane@example.com" post.md -i

# Results in:
# author:
#   name: Jane Doe
#   email: jane@example.com

# Deeply nested
md-utils fm set --key author.social.twitter --value "@janedoe" post.md -i
```

## Multiple Files

### Batch Updates

```bash
# Update multiple files
md-utils fm set --key author --value "Jane Doe" \\
         post1.md post2.md post3.md --in-place

# Using wildcards
md-utils fm set --key updated --value "$(date -I)" \\
         posts/*.md -i

# Recursive processing
md-utils --recursive fm set --key modified --value "$(date -I)" \\
         content/ --in-place
```

## Common Use Cases

### Publishing Workflow

```bash
# Mark as published
md-utils fm set --key draft --value "false" post.md -i

# Set publish date
md-utils fm set --key publishDate --value "$(date -I)" post.md -i

# Publish all drafts in directory
md-utils -r fm set --key draft --value "false" drafts/ -i
```

### Adding Metadata

```bash
# Add author to posts missing it
for file in posts/*.md; do
    if ! md-utils fm get --key author "$file" >/dev/null 2>&1; then
        md-utils fm set --key author --value "Default Author" "$file" -i
    fi
done

# Add timestamp to all files
md-utils -r fm set --key processedAt --value "$(date -I)" content/ -i
```

### Updating Tags

```bash
# Add tag to all posts
for file in posts/*.md; do
    tags=$(md-utils fm get --key tags "$file" --format json 2>/dev/null || echo '[]')
    new_tags=$(echo "$tags" | jq '. + ["new-tag"] | unique')
    md-utils fm set --key tags --value "$new_tags" "$file" -i
done

# Replace tags
md-utils fm set --key tags --value '["swift", "tutorial"]' post.md -i
```

### Schema Migration

```bash
#!/bin/bash
# Migrate from old field to new field

for file in posts/*.md; do
    # Get old value
    old_value=$(md-utils fm get --key old_field "$file" 2>/dev/null)

    if [ -n "$old_value" ]; then
        # Set new field
        md-utils fm set --key new_field --value "$old_value" "$file" -i

        # Remove old field
        md-utils fm remove --key old_field "$file" -i
    fi
done
```

### Conditional Updates

```bash
#!/bin/bash
# Update only if condition met

for file in posts/*.md; do
    draft=$(md-utils fm get --key draft "$file" 2>/dev/null)

    # Only update non-drafts
    if [ "$draft" != "true" ]; then
        md-utils fm set --key lastChecked --value "$(date -I)" "$file" -i
    fi
done
```

## Pipeline Usage

### Preview Before Apply

```bash
# Preview changes
md-utils fm set --key author --value "Jane" posts/*.md

# Review output, then apply
md-utils fm set --key author --value "Jane" posts/*.md -i
```

### Batch Processing with Logging

```bash
#!/bin/bash
# Update with logging

log_file="updates.log"

for file in posts/*.md; do
    echo "Updating $file" >> "$log_file"

    if md-utils fm set --key updated --value "$(date -I)" "$file" -i; then
        echo "  Success" >> "$log_file"
    else
        echo "  Failed" >> "$log_file"
    fi
done
```

### Complex Workflows

```bash
#!/bin/bash
# Multi-step update workflow

for file in posts/*.md; do
    # Get current date
    date=$(md-utils fm get --key date "$file" 2>/dev/null)

    # Set publish date if missing
    if ! md-utils fm get --key publishDate "$file" >/dev/null 2>&1; then
        md-utils fm set --key publishDate --value "$date" "$file" -i
    fi

    # Update modified timestamp
    md-utils fm set --key modified --value "$(date -I)" "$file" -i

    # Add version
    md-utils fm set --key version --value "2" "$file" -i
done
```

## Value Types

### Strings

```bash
# Simple string
md-utils fm set --key title --value "My Title" post.md -i

# String with spaces (use quotes)
md-utils fm set --key description --value "A long description here" post.md -i

# String with special characters
md-utils fm set --key note --value "Quote: \"example\"" post.md -i
```

### Booleans

Use lowercase string representation:

```bash
# True
md-utils fm set --key published --value "true" post.md -i

# False
md-utils fm set --key draft --value "false" post.md -i
```

### Numbers

```bash
# Integer
md-utils fm set --key count --value "42" post.md -i

# Float
md-utils fm set --key rating --value "4.5" post.md -i
```

### Arrays

Use JSON array format:

```bash
# String array
md-utils fm set --key tags --value '["swift", "programming"]' post.md -i

# Number array
md-utils fm set --key scores --value '[1, 2, 3, 4, 5]' post.md -i

# Mixed array (not recommended)
md-utils fm set --key mixed --value '["string", 42, true]' post.md -i
```

### Objects

Use JSON object format:

```bash
# Simple object
md-utils fm set --key author --value '{"name": "Jane", "email": "jane@example.com"}' post.md -i

# Nested object
md-utils fm set --key metadata --value '{"version": 1, "status": "published"}' post.md -i
```

## Error Handling

### Safe Updates

```bash
# Backup before updating
cp post.md post.md.bak
md-utils fm set --key title --value "New Title" post.md -i

# Or use version control
git add post.md
md-utils fm set --key title --value "New Title" post.md -i
git diff  # Review
git commit -m "Update title"
```

### Validation

```bash
#!/bin/bash
# Validate before setting

key="title"
value="New Title"
file="post.md"

# Check if file exists
if [ ! -f "$file" ]; then
    echo "Error: File not found"
    exit 1
fi

# Check if value is not empty
if [ -z "$value" ]; then
    echo "Error: Value cannot be empty"
    exit 1
fi

# Set value
md-utils fm set --key "$key" --value "$value" "$file" -i
```

### Error Recovery

```bash
#!/bin/bash
# Update with error handling

for file in posts/*.md; do
    if ! md-utils fm set --key updated --value "$(date -I)" "$file" -i 2>/dev/null; then
        echo "Failed to update $file"
        # Log or handle error
    fi
done
```

## Advanced Examples

### Computed Values

```bash
#!/bin/bash
# Set computed values

file="post.md"

# Count words and set
word_count=$(md-utils body --format plain-text "$file" | wc -w)
md-utils fm set --key wordCount --value "$word_count" "$file" -i

# Calculate reading time (250 words/minute)
reading_time=$(( (word_count + 249) / 250 ))
md-utils fm set --key readingTime --value "$reading_time" "$file" -i
```

### Dynamic Metadata

```bash
#!/bin/bash
# Add dynamic metadata

for file in posts/*.md; do
    # File info
    size=$(stat -f%z "$file")
    md-utils fm set --key fileSize --value "$size" "$file" -i

    # Checksum
    checksum=$(md5 -q "$file")
    md-utils fm set --key checksum --value "$checksum" "$file" -i

    # Last modified
    mtime=$(stat -f%Sm -t"%Y-%m-%d" "$file")
    md-utils fm set --key lastModified --value "$mtime" "$file" -i
done
```

### Bulk Updates from CSV

```bash
#!/bin/bash
# Update from CSV file

# CSV format: filename,title,author,tags
while IFS=, read -r filename title author tags; do
    md-utils fm set --key title --value "$title" "$filename" -i
    md-utils fm set --key author --value "$author" "$filename" -i
    md-utils fm set --key tags --value "$tags" "$filename" -i
done < updates.csv
```

## See Also

- <doc:FMGet>
- <doc:FMList>
- <doc:FMDump>
- <doc:GlobalOptions>
- <doc:Workflows/HugoWorkflows/BulkUpdates>
