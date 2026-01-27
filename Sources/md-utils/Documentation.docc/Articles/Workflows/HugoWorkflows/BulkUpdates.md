# Bulk Updates for Hugo

Perform mass updates to Hugo content with md-utils.

## Overview

Efficiently update frontmatter across many files with bulk operations, batch processing, and automated scripts.

## Publishing Workflows

### Publish All Drafts

```bash
# Set all drafts to published
md-utils -r fm set --key draft --value "false" content/posts/ -i

# Publish drafts in specific directory
md-utils fm set --key draft --value "false" content/posts/2024/*.md -i
```

### Publish by Date

```bash
#!/bin/bash
# publish-ready.sh - Publish posts with past publish dates

today=$(date -I)

for file in content/posts/**/*.md; do
    publish_date=$(md-utils fm get --key publishDate "$file" 2>/dev/null)

    if [ -n "$publish_date" ] && [ "$publish_date" \< "$today" ]; then
        md-utils fm set --key draft --value "false" "$file" -i
        echo "Published: $file"
    fi
done
```

### Scheduled Publishing

```bash
#!/bin/bash
# scheduled-publish.sh - Run via cron

current_datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

for file in content/posts/**/*.md; do
    draft=$(md-utils fm get --key draft "$file" 2>/dev/null)
    publish_date=$(md-utils fm get --key publishDate "$file" 2>/dev/null)

    if [ "$draft" = "true" ] && [ -n "$publish_date" ]; then
        if [[ "$publish_date" < "$current_datetime" ]]; then
            md-utils fm set --key draft --value "false" "$file" -i
            echo "Auto-published: $file"
        fi
    fi
done
```

## Metadata Updates

### Update Timestamps

```bash
# Update all modified dates
md-utils -r fm set --key lastmod --value "$(date -I)" content/ -i

# Update only changed files (with git)
git diff --name-only HEAD | grep '\.md$' | \\
    xargs -I {} md-utils fm set --key lastmod --value "$(date -I)" {} -i

# Update specific directory
md-utils fm set --key lastmod --value "$(date -I)" content/posts/2024/*.md -i
```

### Add Missing Fields

```bash
#!/bin/bash
# add-missing-fields.sh

default_author="Site Admin"

for file in content/posts/**/*.md; do
    # Add author if missing
    if ! md-utils fm get --key author "$file" >/dev/null 2>&1; then
        md-utils fm set --key author --value "$default_author" "$file" -i
        echo "Added author to: $file"
    fi

    # Add description if missing
    if ! md-utils fm get --key description "$file" >/dev/null 2>&1; then
        # Generate from first paragraph
        desc=$(md-utils body --format plain-text "$file" | head -n 1 | cut -c1-160)
        md-utils fm set --key description --value "$desc" "$file" -i
        echo "Added description to: $file"
    fi
done
```

### Set Default Values

```bash
#!/bin:bash
# set-defaults.sh

for file in content/posts/**/*.md; do
    # Ensure draft field exists
    if ! md-utils fm get --key draft "$file" >/dev/null 2>&1; then
        md-utils fm set --key draft --value "true" "$file" -i
    fi

    # Add default slug if missing
    if ! md-utils fm get --key slug "$file" >/dev/null 2>&1; then
        filename=$(basename "$file" .md)
        md-utils fm set --key slug --value "$filename" "$file" -i
    fi

    # Set default weight
    if ! md-utils fm get --key weight "$file" >/dev/null 2>&1; then
        md-utils fm set --key weight --value "0" "$file" -i
    fi
done
```

## Schema Migration

### Rename Fields

```bash
#!/bin/bash
# migrate-fields.sh - Rename frontmatter fields

for file in content/**/*.md; do
    # Rename old_field to new_field
    if value=$(md-utils fm get --key old_field "$file" 2>/dev/null); then
        md-utils fm set --key new_field --value "$value" "$file" -i
        # TODO: Remove old field (requires fm remove command)
        echo "Migrated: $file"
    fi
done
```

### Add Version Field

```bash
#!/bin/bash
# version-bump.sh - Add/update version

version="2"

md-utils -r fm set --key schema_version --value "$version" content/ -i

echo "Updated schema version to $version"
```

### Convert Field Types

```bash
#!/bin/bash
# convert-types.sh

for file in content/**/*.md; do
    # Convert string tags to array
    tags=$(md-utils fm get --key tags "$file" 2>/dev/null)

    if [[ "$tags" =~ ^[a-zA-Z] ]]; then  # If it's a plain string
        # Convert to array
        tags_array="[\"$tags\"]"
        md-utils fm set --key tags --value "$tags_array" "$file" -i
        echo "Converted tags in: $file"
    fi
done
```

## Batch Processing

### Process by Category

```bash
#!/bin/bash
# update-by-category.sh

category="$1"
key="$2"
value="$3"

for file in content/posts/**/*.md; do
    cats=$(md-utils fm get --key categories "$file" --format json 2>/dev/null)

    if echo "$cats" | grep -q "\"$category\""; then
        md-utils fm set --key "$key" --value "$value" "$file" -i
        echo "Updated: $file"
    fi
done
```

### Update by Date Range

```bash
#!/bin/bash
# update-date-range.sh

start_date="2024-01-01"
end_date="2024-12-31"

for file in content/posts/**/*.md; do
    date=$(md-utils fm get --key date "$file" 2>/dev/null)

    if [[ "$date" > "$start_date" ]] && [[ "$date" < "$end_date" ]]; then
        md-utils fm set --key year --value "2024" "$file" -i
        echo "Updated: $file"
    fi
done
```

## Content Cleanup

### Remove Deprecated Fields

```bash
#!/bin/bash
# cleanup-fields.sh

deprecated=("old_field" "temp_field" "debug_info")

for file in content/**/*.md; do
    for field in "${deprecated[@]}"; do
        if md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
            # TODO: Remove field (requires fm remove command)
            echo "Found deprecated field '$field' in: $file"
        fi
    done
done
```

### Normalize Boolean Values

```bash
#!/bin/bash
# normalize-booleans.sh

for file in content/**/*.md; do
    # Ensure draft is boolean
    draft=$(md-utils fm get --key draft "$file" 2>/dev/null)

    case "$draft" in
        "yes"|"Yes"|"YES"|"1"|"on")
            md-utils fm set --key draft --value "true" "$file" -i
            ;;
        "no"|"No"|"NO"|"0"|"off")
            md-utils fm set --key draft --value "false" "$file" -i
            ;;
    esac
done
```

## Verification

### Pre-Update Backup

```bash
#!/bin/bash
# safe-bulk-update.sh

backup_dir="backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"

# Backup
cp -r content/ "$backup_dir/"

# Perform update
md-utils -r fm set --key updated --value "$(date -I)" content/ -i

# Verify
if [ $? -eq 0 ]; then
    echo "Update successful. Backup in: $backup_dir"
else
    echo "Update failed. Restoring from backup..."
    rm -rf content/
    cp -r "$backup_dir/content" ./
fi
```

### Dry Run

```bash
#!/bin/bash
# dry-run-update.sh

echo "DRY RUN: Showing what would be updated"
echo ""

for file in content/posts/**/*.md; do
    draft=$(md-utils fm get --key draft "$file" 2>/dev/null)

    if [ "$draft" = "true" ]; then
        echo "Would publish: $file"
    fi
done

read -p "Proceed with actual update? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    md-utils -r fm set --key draft --value "false" content/posts/ -i
    echo "Update complete"
fi
```

## See Also

- <doc:CreatingPosts>
- <doc:ManagingTaxonomies>
- <doc:DeploymentAutomation>
- <doc:HugoWorkflows>
