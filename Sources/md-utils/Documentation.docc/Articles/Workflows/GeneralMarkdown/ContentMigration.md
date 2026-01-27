# Content Migration

Migrate Markdown content between systems and formats with md-utils.

## Overview

Content migration involves moving Markdown documents from one system to another while preserving structure, metadata, and formatting. md-utils provides tools for extracting, transforming, and loading content between different platforms, CMS systems, and documentation tools.

## Common Migration Scenarios

### Platform Migrations

- Jekyll → Hugo
- WordPress → Static Site Generator
- Confluence → Markdown documentation
- Notion → Obsidian
- Medium → Personal blog

### Format Conversions

- HTML → Markdown with frontmatter
- Plain text → Structured Markdown
- Different Markdown flavors (GitHub, CommonMark, etc.)
- Legacy formats → Modern documentation

## Export Operations

### Extract Content from System

```bash
#!/bin/bash
# export-content.sh

source_dir="$1"
export_dir="export-$(date +%s)"

mkdir -p "$export_dir"/{content,metadata,attachments}

echo "Exporting content from: $source_dir"

# Export frontmatter to JSON
md-utils fm dump --recursive "$source_dir" --format json > \
  "$export_dir/metadata/all-frontmatter.json"

# Export body content
find "$source_dir" -name "*.md" | while read -r file; do
  relative=$(echo "$file" | sed "s|^$source_dir/||")
  output="$export_dir/content/$relative"

  mkdir -p "$(dirname "$output")"
  md-utils body "$file" > "$output"
done

# Export to plain text for full-text search
md-utils convert to-text --recursive "$source_dir" \
  --output "$export_dir/plain-text/"

echo "✓ Export complete: $export_dir"
```

### Create Migration Manifest

```bash
#!/bin/bash
# create-manifest.sh

source_dir="$1"
manifest="migration-manifest.json"

echo "Creating migration manifest..."

jq -n '
{
  "migration_date": "'$(date -I)'",
  "source_system": "Jekyll",
  "target_system": "Hugo",
  "total_files": 0,
  "files": []
}' > "$manifest"

find "$source_dir" -name "*.md" | while read -r file; do
  # Extract metadata
  title=$(md-utils fm get --key title "$file" 2>/dev/null)
  date=$(md-utils fm get --key date "$file" 2>/dev/null)
  categories=$(md-utils fm get --key categories "$file" 2>/dev/null)

  # Add to manifest
  jq --arg file "$file" \
     --arg title "$title" \
     --arg date "$date" \
     --arg categories "$categories" \
     '.files += [{
        source: $file,
        title: $title,
        date: $date,
        categories: $categories
      }] | .total_files += 1' "$manifest" > "$manifest.tmp"

  mv "$manifest.tmp" "$manifest"
done

echo "✓ Manifest created: $manifest"
```

## Import Operations

### Import with Transformation

```bash
#!/bin/bash
# import-content.sh

source_dir="$1"
target_dir="$2"

echo "Importing content to: $target_dir"

find "$source_dir" -name "*.md" | while read -r source_file; do
  # Determine target path
  relative=$(echo "$source_file" | sed "s|^$source_dir/||")
  target_file="$target_dir/$relative"

  mkdir -p "$(dirname "$target_file")"

  # Copy content
  cp "$source_file" "$target_file"

  # Transform frontmatter for target system
  md-utils fm set --key imported_from --value "$source_file" \
    --key imported_date --value "$(date -I)" \
    "$target_file" --in-place

  echo "Imported: $relative"
done

echo "✓ Import complete"
```

### Map Metadata Fields

```bash
#!/bin/bash
# map-metadata.sh - Transform frontmatter schema

source_file="$1"
target_file="$2"

# Create mapping configuration
declare -A field_map=(
  ["post_title"]="title"
  ["post_date"]="date"
  ["post_author"]="author"
  ["post_category"]="categories"
  ["post_tags"]="tags"
)

# Copy file
cp "$source_file" "$target_file"

# Transform fields
for source_field in "${!field_map[@]}"; do
  target_field="${field_map[$source_field]}"

  value=$(md-utils fm get --key "$source_field" "$source_file" 2>/dev/null)

  if [ -n "$value" ]; then
    # Remove old field, add new field
    md-utils fm delete --key "$source_field" "$target_file" --in-place
    md-utils fm set --key "$target_field" --value "$value" "$target_file" --in-place
  fi
done
```

## Platform-Specific Migrations

### Jekyll to Hugo

```bash
#!/bin/bash
# jekyll-to-hugo.sh

jekyll_dir="$1"
hugo_dir="$2/content"

mkdir -p "$hugo_dir"

find "$jekyll_dir/_posts" -name "*.md" | while read -r post; do
  # Extract Jekyll frontmatter
  title=$(md-utils fm get --key title "$post")
  date=$(md-utils fm get --key date "$post")
  categories=$(md-utils fm get --key categories "$post")
  tags=$(md-utils fm get --key tags "$post")

  # Determine Hugo path
  year=$(echo "$date" | cut -d- -f1)
  slug=$(basename "$post" .md | sed 's/^[0-9]*-[0-9]*-[0-9]*-//')

  target="$hugo_dir/posts/$year/$slug.md"
  mkdir -p "$(dirname "$target")"

  cp "$post" "$target"

  # Transform frontmatter for Hugo
  md-utils fm set --key title --value "$title" \
    --key date --value "$date" \
    --key categories --value "$categories" \
    --key tags --value "$tags" \
    --key draft --value "false" \
    "$target" --in-place

  # Remove Jekyll-specific fields
  md-utils fm delete --key layout "$target" --in-place

  echo "Migrated: $slug"
done

echo "✓ Jekyll to Hugo migration complete"
```

### WordPress Export to Markdown

```bash
#!/bin/bash
# wordpress-to-md.sh

# Assumes WordPress export XML has been converted to individual MD files
# (using tools like wordpress-export-to-markdown)

source_dir="$1"
target_dir="$2"

find "$source_dir" -name "*.md" | while read -r file; do
  # Clean up WordPress-specific elements
  cleaned=$(mktemp)
  cp "$file" "$cleaned"

  # Remove WordPress shortcodes
  sed -i '' 's/\[caption[^]]*\]//g' "$cleaned"
  sed -i '' 's/\[\/caption\]//g' "$cleaned"

  # Fix image paths
  sed -i '' 's|/wp-content/uploads/|/images/|g' "$cleaned"

  # Normalize frontmatter
  title=$(md-utils fm get --key title "$cleaned")
  date=$(md-utils fm get --key date "$cleaned")
  categories=$(md-utils fm get --key categories "$cleaned")

  # Determine target path
  slug=$(basename "$file" .md)
  target="$target_dir/$slug.md"

  cp "$cleaned" "$target"

  md-utils fm set --key title --value "$title" \
    --key date --value "$date" \
    --key categories --value "$categories" \
    --key source --value "wordpress" \
    "$target" --in-place

  rm "$cleaned"

  echo "Converted: $slug"
done
```

### Obsidian to Hugo Blog

```bash
#!/bin/bash
# obsidian-to-hugo.sh

vault_dir="$1"
hugo_content="$2"

# Find all notes tagged for publishing
md-utils fm get --key tags --recursive "$vault_dir" | \
  grep "publish" | cut -d: -f1 | while read -r note; do

  title=$(md-utils fm get --key title "$note")
  date=$(md-utils fm get --key date "$note" || echo "$(date -I)")
  tags=$(md-utils fm get --key tags "$note")

  # Create Hugo post
  slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
  target="$hugo_content/posts/$slug.md"

  cp "$note" "$target"

  # Transform for Hugo
  md-utils fm set --key title --value "$title" \
    --key date --value "$date" \
    --key tags --value "$tags" \
    --key draft --value "false" \
    "$target" --in-place

  # Convert Obsidian wikilinks to Hugo links
  sed -i '' 's/\[\[\([^]]*\)\]\]/[\1](\/posts\/\1)/g' "$target"

  echo "Published: $title"
done
```

## Data Transformation

### URL Rewriting

```bash
#!/bin/bash
# rewrite-urls.sh

old_domain="oldsite.com"
new_domain="newsite.com"

find content/ -name "*.md" -exec \
  sed -i '' "s|$old_domain|$new_domain|g" {} \;

echo "✓ URLs rewritten"
```

### Path Restructuring

```bash
#!/bin/bash
# restructure-paths.sh

# Flatten directory structure
find source/ -name "*.md" | while read -r file; do
  filename=$(basename "$file")
  cp "$file" "target/$filename"
done

# Or organize by metadata
find source/ -name "*.md" | while read -r file; do
  category=$(md-utils fm get --key category "$file")
  year=$(md-utils fm get --key date "$file" | cut -d- -f1)

  target="organized/$category/$year/$(basename "$file")"
  mkdir -p "$(dirname "$target")"
  cp "$file" "$target"
done
```

### Image Migration

```bash
#!/bin/bash
# migrate-images.sh

source_dir="$1"
target_dir="$2"
image_dir="$target_dir/static/images"

mkdir -p "$image_dir"

# Find all image references
find "$source_dir" -name "*.md" -exec \
  grep -oh '!\[.*\]([^)]*)' {} \; | \
  sed 's/.*](\([^)]*\))/\1/' | \
  sort -u | while read -r img_path; do

  # Copy image to new location
  if [ -f "$source_dir/$img_path" ]; then
    filename=$(basename "$img_path")
    cp "$source_dir/$img_path" "$image_dir/$filename"

    echo "Copied: $img_path -> $image_dir/$filename"
  fi
done

# Update image references in content
find "$target_dir" -name "*.md" -exec \
  sed -i '' 's|!\[\(.*\)\](\(.*\))|![\1](/images/\2)|g' {} \;
```

## Validation

### Verify Migration

```bash
#!/bin/bash
# verify-migration.sh

source_dir="$1"
target_dir="$2"

source_count=$(find "$source_dir" -name "*.md" | wc -l)
target_count=$(find "$target_dir" -name "*.md" | wc -l)

echo "=== Migration Verification ==="
echo "Source files: $source_count"
echo "Target files: $target_count"

if [ $source_count -ne $target_count ]; then
  echo "⚠ File count mismatch"
else
  echo "✓ File count matches"
fi

# Check for required metadata
echo -e "\n### Metadata Validation"
errors=0

find "$target_dir" -name "*.md" | while read -r file; do
  for field in title date; do
    if ! md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
      echo "Missing $field: $file"
      ((errors++))
    fi
  done
done

if [ $errors -eq 0 ]; then
  echo "✓ All files have required metadata"
else
  echo "✗ Found $errors metadata errors"
fi
```

### Check Data Integrity

```bash
#!/bin/bash
# check-integrity.sh

# Verify no data loss
find source/ -name "*.md" | while read -r source; do
  target="migrated/$(basename "$source")"

  # Compare word counts (rough check)
  source_words=$(md-utils body "$source" | wc -w)
  target_words=$(md-utils body "$target" | wc -w)

  diff=$((source_words - target_words))

  if [ ${diff#-} -gt 100 ]; then  # More than 100 words difference
    echo "⚠ Significant content change: $source ($diff words)"
  fi
done
```

## Rollback and Recovery

### Create Rollback Plan

```bash
#!/bin/bash
# create-rollback.sh

# Backup before migration
backup_dir="backups/pre-migration-$(date +%s)"
mkdir -p "$backup_dir"

# Copy original content
cp -r source/ "$backup_dir/"

# Record state
find source/ -name "*.md" | while read -r file; do
  md5sum "$file"
done > "$backup_dir/checksums.txt"

echo "✓ Rollback point created: $backup_dir"
```

### Rollback Migration

```bash
#!/bin/bash
# rollback.sh

backup_dir="$1"

if [ ! -d "$backup_dir" ]; then
  echo "Error: Backup not found"
  exit 1
fi

# Restore from backup
cp -r "$backup_dir"/source/* source/

# Verify checksums
cd "$backup_dir"
md5sum -c checksums.txt

echo "✓ Rollback complete"
```

## Best Practices

### Incremental Migration

```bash
# Migrate in batches
find source/ -name "*.md" | head -100 | while read -r file; do
  # Migrate file
  ./migrate-file.sh "$file" target/
done

# Verify batch
./verify-migration.sh source/ target/

# Continue with next batch if successful
```

### Keep Migration Log

```bash
#!/bin/bash
# migrate-with-logging.sh

log_file="migration-$(date +%s).log"

{
  echo "Migration started: $(date)"
  echo "Source: $source_dir"
  echo "Target: $target_dir"
  echo ""

  # Perform migration with logging
  ./migrate-content.sh "$source_dir" "$target_dir" 2>&1

  echo ""
  echo "Migration completed: $(date)"
} | tee "$log_file"
```

### Test Before Production

```bash
# Test migration with small subset
test_source="source/test"
test_target="target/test"

./migrate-content.sh "$test_source" "$test_target"
./verify-migration.sh "$test_source" "$test_target"

# If successful, migrate all
if [ $? -eq 0 ]; then
  ./migrate-content.sh source/ target/
fi
```

## See Also

- <doc:BatchProcessing>
- <doc:QualityControl>
- <doc:../Scripting/PipelinePatterns>
- <doc:../HugoWorkflows/HugoWorkflows>
