# Documentation Maintenance

Keep documentation up-to-date and well-organized with md-utils.

## Overview

Documentation requires ongoing maintenance to remain useful. md-utils automates common maintenance tasks like updating timestamps, validating metadata, generating navigation, and ensuring consistency across large documentation sets.

## Timestamp Management

### Update Modification Dates

```bash
#!/bin/bash
# update-doc-timestamps.sh

docs_dir="${1:-docs}"

# Update files modified in last day
find "$docs_dir" -name "*.md" -mtime -1 | while read -r file; do
  md-utils fm set --key last_modified --value "$(date -I)" \
    "$file" --in-place

  echo "Updated: $file"
done
```

### Track Review Dates

```bash
# Add reviewed timestamp
mark_reviewed() {
  local file="$1"

  md-utils fm set --key last_reviewed --value "$(date -I)" \
    --key review_count --value "$(($(md-utils fm get --key review_count "$file" 2>/dev/null || echo 0) + 1))" \
    "$file" --in-place
}

# Find docs needing review (>6 months old)
cutoff=$(date -v-6m +%Y-%m-%d)
md-utils fm get --key last_reviewed --recursive docs/ | \
  awk -v cutoff="$cutoff" '$2 < cutoff || $2 == "" {print $1}'
```

### Add Creation Timestamps

```bash
# Add created timestamp from git history
find docs/ -name "*.md" | while read -r file; do
  if ! md-utils fm get --key created "$file" >/dev/null 2>&1; then
    # Get first commit date for file
    created=$(git log --follow --format="%aI" --reverse "$file" | head -1)

    if [ -n "$created" ]; then
      md-utils fm set --key created --value "$created" "$file" --in-place
      echo "Added created date: $file"
    fi
  fi
done
```

## Version Management

### Update Version Numbers

```bash
#!/bin/bash
# bump-doc-version.sh

old_version="$1"
new_version="$2"
docs_dir="${3:-docs}"

echo "Updating version: $old_version -> $new_version"

# Update all references
find "$docs_dir" -name "*.md" | while read -r file; do
  # Update frontmatter
  current=$(md-utils fm get --key version "$file" 2>/dev/null)

  if [ "$current" = "$old_version" ]; then
    md-utils fm set --key version --value "$new_version" \
      --key version_updated --value "$(date -I)" \
      "$file" --in-place

    echo "Updated: $file"
  fi

  # Update content references
  if grep -q "$old_version" "$file"; then
    sed -i '' "s/$old_version/$new_version/g" "$file"
    echo "Updated content: $file"
  fi
done

echo "✓ Version bump complete"
```

### Version Compatibility Tracking

```bash
# Track API version compatibility
update_api_compatibility() {
  local min_version="$1"
  local max_version="$2"

  find docs/api/ -name "*.md" | while read -r file; do
    md-utils fm set --key api_min_version --value "$min_version" \
      --key api_max_version --value "$max_version" \
      --key compatibility_updated --value "$(date -I)" \
      "$file" --in-place
  done
}

update_api_compatibility "2.0" "2.5"
```

## Navigation Maintenance

### Regenerate Table of Contents

```bash
#!/bin/bash
# regenerate-tocs.sh

docs_dir="${1:-docs}"

echo "Regenerating table of contents..."

# For each markdown file
find "$docs_dir" -name "*.md" | while read -r file; do
  # Generate TOC
  toc=$(md-utils toc "$file" --format markdown)

  # Check if file has TOC marker
  if grep -q "<!-- TOC -->" "$file"; then
    # Replace existing TOC
    awk -v toc="$toc" '
      /<!-- TOC -->/ {print; print toc; skip=1; next}
      /<!-- \/TOC -->/ {skip=0}
      !skip {print}
    ' "$file" > "$file.tmp"

    mv "$file.tmp" "$file"
    echo "Updated TOC: $file"
  fi
done
```

### Update Index Files

```bash
#!/bin/bash
# update-index.sh

docs_dir="${1:-docs}"
index_file="$docs_dir/INDEX.md"

echo "# Documentation Index" > "$index_file"
echo "" >> "$index_file"
echo "Generated: $(date)" >> "$index_file"
echo "" >> "$index_file"

# Group by category
for category in getting-started guides reference api; do
  files=$(find "$docs_dir" -name "*.md" -exec sh -c \
    'md-utils fm get --key category "$1" 2>/dev/null | grep -q "'$category'" && echo "$1"' _ {} \;)

  if [ -n "$files" ]; then
    echo "## $(echo $category | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')" >> "$index_file"
    echo "" >> "$index_file"

    echo "$files" | while read -r file; do
      title=$(md-utils fm get --key title "$file" 2>/dev/null || basename "$file" .md)
      relative=$(echo "$file" | sed "s|^$docs_dir/||")
      echo "- [$title]($relative)" >> "$index_file"
    done

    echo "" >> "$index_file"
  fi
done

echo "✓ Index updated: $index_file"
```

### Breadcrumb Generation

```bash
# Add breadcrumbs to nested documentation
add_breadcrumbs() {
  local file="$1"
  local docs_root="docs"

  # Build breadcrumb path
  relative=$(echo "$file" | sed "s|^$docs_root/||")
  IFS='/' read -ra parts <<< "$relative"

  breadcrumb="[Home](../index.md)"
  path=""

  for ((i=0; i<${#parts[@]}-1; i++)); do
    part="${parts[$i]}"
    path+="$part/"

    # Convert to title case
    title=$(echo "$part" | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')

    breadcrumb+=" > [$title](../$path/index.md)"
  done

  # Update file
  md-utils fm set --key breadcrumb --value "$breadcrumb" "$file" --in-place
}

find docs/ -name "*.md" -exec bash -c 'add_breadcrumbs "$0"' {} \;
```

## Content Validation

### Check Required Fields

```bash
#!/bin/bash
# validate-docs.sh

required_fields="title description author date"

echo "Validating documentation..."

errors=0

find docs/ -name "*.md" | while read -r file; do
  file_errors=()

  for field in $required_fields; do
    if ! md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
      file_errors+=("Missing: $field")
    fi
  done

  if [ ${#file_errors[@]} -gt 0 ]; then
    echo "INVALID: $file"
    printf '  %s\n' "${file_errors[@]}"
    ((errors++))
  fi
done

if [ $errors -eq 0 ]; then
  echo "✓ All documentation valid"
  exit 0
else
  echo "✗ Found $errors files with errors"
  exit 1
fi
```

### Find Broken Cross-References

```bash
#!/bin/bash
# check-internal-links.sh

docs_dir="${1:-docs}"

echo "Checking internal links..."

# Extract all markdown links
find "$docs_dir" -name "*.md" | while read -r file; do
  grep -on '\[.*\](.*\.md' "$file" | while IFS=: read -r line_num link; do
    # Extract link path
    link_path=$(echo "$link" | sed -n 's/.*](\(.*\.md\).*/\1/p')

    # Resolve relative path
    dir=$(dirname "$file")
    target="$dir/$link_path"

    # Normalize path
    target=$(cd "$dir" && realpath --relative-to="$docs_dir" "$link_path" 2>/dev/null)

    # Check if target exists
    if [ ! -f "$docs_dir/$target" ]; then
      echo "BROKEN: $file:$line_num"
      echo "  Link: $link_path"
      echo "  Target not found: $docs_dir/$target"
    fi
  done
done
```

### Detect Stale Content

```bash
#!/bin/bash
# find-stale-docs.sh

# Find docs not modified in 6 months
cutoff=$(date -v-6m +%Y-%m-%d)

echo "=== Stale Documentation (>6 months) ==="

md-utils fm get --key last_modified --recursive docs/ | \
  awk -v cutoff="$cutoff" '$2 < cutoff {print $1, $2}' | \
  while read -r file date; do
    title=$(md-utils fm get --key title "$file" 2>/dev/null || basename "$file")
    echo "- $title ($file) - Last modified: $date"
  done
```

## Cleanup Operations

### Remove Obsolete Files

```bash
#!/bin/bash
# cleanup-obsolete.sh

# Mark files as obsolete
mark_obsolete() {
  local file="$1"

  md-utils fm set --key status --value "obsolete" \
    --key obsolete_date --value "$(date -I)" \
    "$file" --in-place
}

# Find obsolete files (manually marked)
md-utils fm get --key status --recursive docs/ | \
  grep "obsolete" | cut -d: -f1 | while read -r file; do

  # Move to archive
  archive_dir="docs/.archive/$(dirname ${file#docs/})"
  mkdir -p "$archive_dir"
  mv "$file" "$archive_dir/"

  echo "Archived: $file"
done
```

### Consolidate Duplicates

```bash
# Find potential duplicate content
find docs/ -name "*.md" -exec sh -c '
  title=$(md-utils fm get --key title "$1" 2>/dev/null)
  echo "$title|$1"
' _ {} \; | sort | uniq -D -f1

# Merge duplicates (manual review required)
merge_docs() {
  local primary="$1"
  local duplicate="$2"

  # Append content from duplicate
  echo -e "\n---\n# Merged from: $duplicate\n" >> "$primary"
  md-utils body "$duplicate" >> "$primary"

  # Mark duplicate as obsolete
  md-utils fm set --key status --value "merged" \
    --key merged_into --value "$primary" \
    "$duplicate" --in-place
}
```

### Normalize Formatting

```bash
#!/bin/bash
# normalize-formatting.sh

# Standardize frontmatter order
standard_field_order="title description author date tags category version"

normalize_frontmatter() {
  local file="$1"

  # Extract all frontmatter
  declare -A fm_data

  md-utils fm dump "$file" | while IFS='=' read -r key value; do
    fm_data["$key"]="$value"
  done

  # Rebuild in standard order
  temp_file=$(mktemp)

  # Add fields in standard order
  for field in $standard_field_order; do
    value="${fm_data[$field]}"
    if [ -n "$value" ]; then
      md-utils fm set --key "$field" --value "$value" "$temp_file" --in-place
    fi
  done

  # Add remaining fields
  for key in "${!fm_data[@]}"; do
    if ! echo "$standard_field_order" | grep -q "$key"; then
      md-utils fm set --key "$key" --value "${fm_data[$key]}" "$temp_file" --in-place
    fi
  done

  # Preserve body and update file
  md-utils body "$file" >> "$temp_file"
  mv "$temp_file" "$file"
}

find docs/ -name "*.md" -exec bash -c 'normalize_frontmatter "$0"' {} \;
```

## Reporting

### Generate Documentation Report

```bash
#!/bin/bash
# doc-report.sh

output="reports/doc-status-$(date +%Y-%m-%d).md"

cat > "$output" << EOF
# Documentation Status Report

Generated: $(date)

## Statistics

- Total documents: $(find docs/ -name "*.md" | wc -l)
- Modified this week: $(find docs/ -name "*.md" -mtime -7 | wc -l)
- Modified this month: $(find docs/ -name "*.md" -mtime -30 | wc -l)

## By Category

EOF

# Count by category
md-utils fm get --key category --recursive docs/ | \
  cut -d: -f2 | sort | uniq -c | \
  awk '{print "- " $2 ": " $1}' >> "$output"

echo -e "\n## Validation Issues\n" >> "$output"

# Run validation
./validate-docs.sh 2>&1 | grep -E "INVALID|Missing" >> "$output"

echo "Report saved: $output"
```

## Best Practices

### Automated Maintenance Schedule

```bash
# Add to crontab

# Daily: Update modification timestamps
0 0 * * * cd ~/docs && ./update-doc-timestamps.sh

# Weekly: Regenerate TOCs and index
0 0 * * 0 cd ~/docs && ./regenerate-tocs.sh && ./update-index.sh

# Monthly: Full validation and stale content report
0 0 1 * * cd ~/docs && ./validate-docs.sh && ./find-stale-docs.sh
```

### Change Tracking

```bash
# Track all documentation changes
git log --since="1 week ago" --name-only --pretty=format: docs/ | \
  sort -u | grep -v '^$' | while read -r file; do
    if [ -f "$file" ]; then
      echo "$file: $(md-utils fm get --key title "$file" 2>/dev/null)"
    fi
  done
```

## See Also

- <doc:QualityControl>
- <doc:BatchProcessing>
- <doc:../Scripting/ShellIntegration>
