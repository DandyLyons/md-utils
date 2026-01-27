# Metadata Synchronization

Keep Obsidian vault metadata consistent and synchronized.

## Overview

Maintaining consistent metadata across an Obsidian vault is essential for organization, searchability, and automation. md-utils provides tools to synchronize frontmatter with filenames, timestamps, tags, and other vault properties.

## Filename Synchronization

### Sync Title to Filename

```bash
#!/bin/bash
# sync-title-to-filename.sh

vault_dir="${1:-vault}"

find "$vault_dir" -name "*.md" | while read -r file; do
  # Get filename without extension
  filename=$(basename "$file" .md")

  # Convert dashes/underscores to spaces for title
  title=$(echo "$filename" | sed 's/[-_]/ /g' | sed 's/\b\(.\)/\u\1/g')

  # Update frontmatter
  md-utils fm set --key title --value "$title" "$file" --in-place

  echo "Updated: $file -> $title"
done
```

### Sync Filename to Title

```bash
#!/bin/bash
# sync-filename-to-title.sh - Rename files to match title

vault_dir="${1:-vault}"

find "$vault_dir" -name "*.md" | while read -r file; do
  # Get title from frontmatter
  title=$(md-utils fm get --key title "$file" 2>/dev/null)

  if [ -n "$title" ]; then
    # Convert title to filename
    new_filename=$(echo "$title" | \
      tr '[:upper:]' '[:lower:]' | \
      sed 's/ /-/g' | \
      sed 's/[^a-z0-9-]//g').md

    dir=$(dirname "$file")
    new_path="$dir/$new_filename"

    if [ "$file" != "$new_path" ]; then
      echo "Renaming: $file -> $new_filename"
      mv "$file" "$new_path"
    fi
  fi
done
```

## Timestamp Management

### Add Created Timestamps

```bash
# Add created timestamp from file creation date
find vault/ -name "*.md" -exec sh -c '
  if ! md-utils fm get --key created "$1" >/dev/null 2>&1; then
    # macOS
    created=$(stat -f "%SB" -t "%Y-%m-%dT%H:%M:%S%z" "$1" 2>/dev/null)

    # Linux (alternative)
    # created=$(stat -c "%w" "$1" 2>/dev/null)

    if [ -n "$created" ]; then
      md-utils fm set --key created --value "$created" "$1" --in-place
      echo "Added created timestamp: $1"
    fi
  fi
' _ {} \;
```

### Update Modified Timestamps

```bash
#!/bin/bash
# update-modified.sh - Update modified timestamp for recently changed files

vault_dir="${1:-vault}"
days="${2:-1}"  # Default: files modified in last day

find "$vault_dir" -name "*.md" -mtime -"$days" | while read -r file; do
  # Get file modification time
  mod_time=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S%z" "$file")

  # Update frontmatter
  md-utils fm set --key modified --value "$mod_time" "$file" --in-place

  echo "Updated: $file"
done
```

### Automatic Timestamp Updates

```bash
#!/bin/bash
# watch-vault.sh - Watch for changes and update timestamps

vault_dir="${1:-vault}"

# Requires fswatch (install with: brew install fswatch)
fswatch -0 "$vault_dir" | while read -d "" file; do
  if [[ "$file" == *.md ]]; then
    timestamp=$(date -Iseconds)
    md-utils fm set --key modified --value "$timestamp" "$file" --in-place
    echo "Updated timestamp: $file"
  fi
done
```

## Tag Synchronization

### Sync Folder Tags

```bash
#!/bin/bash
# sync-folder-tags.sh

vault_dir="${1:-vault}"

# For each directory, add folder name as tag
find "$vault_dir" -type d | while read -r dir; do
  folder_name=$(basename "$dir")

  # Skip vault root and hidden directories
  if [ "$dir" = "$vault_dir" ] || [[ "$folder_name" == .* ]]; then
    continue
  fi

  # Convert folder name to tag
  tag=$(echo "$folder_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

  # Add tag to all notes in folder
  find "$dir" -maxdepth 1 -name "*.md" | while read -r note; do
    # Get existing tags
    existing_tags=$(md-utils fm get --key tags "$note" 2>/dev/null || echo "[]")

    # Add folder tag if not present
    if ! echo "$existing_tags" | grep -q "$tag"; then
      new_tags=$(echo "$existing_tags" | jq --arg tag "$tag" '. + [$tag] | unique')
      md-utils fm set --key tags --value "$new_tags" "$note" --in-place
      echo "Added tag '$tag' to: $note"
    fi
  done
done
```

### Normalize Tags

```bash
#!/bin/bash
# normalize-tags.sh - Ensure consistent tag format

vault_dir="${1:-vault}"

find "$vault_dir" -name "*.md" | while read -r note; do
  tags=$(md-utils fm get --key tags "$note" 2>/dev/null)

  if [ -n "$tags" ]; then
    # Normalize: lowercase, no spaces, consistent format
    normalized=$(echo "$tags" | \
      jq 'map(. | gsub(" "; "-") | ascii_downcase) | unique | sort')

    md-utils fm set --key tags --value "$normalized" "$note" --in-place
  fi
done
```

### Tag Hierarchy

```bash
# Convert flat tags to hierarchical
convert_to_hierarchy() {
  local note="$1"

  tags=$(md-utils fm get --key tags "$note" 2>/dev/null)

  if [ -n "$tags" ]; then
    # Example: convert "python" and "programming" to "programming/python"
    hierarchical=$(echo "$tags" | jq '
      map(
        if . == "python" or . == "javascript" or . == "rust" then
          "programming/" + .
        elif . == "obsidian" or . == "vim" then
          "tools/" + .
        else
          .
        end
      ) | unique
    ')

    md-utils fm set --key tags --value "$hierarchical" "$note" --in-place
  fi
}

# Apply to all notes
find vault/ -name "*.md" -exec bash -c 'convert_to_hierarchy "$0"' {} \;
```

## Aliases Management

### Generate Aliases from Filename

```bash
# Add filename variants as aliases
find vault/ -name "*.md" | while read -r file; do
  filename=$(basename "$file" .md)
  title=$(md-utils fm get --key title "$file" 2>/dev/null || echo "$filename")

  # Generate aliases
  aliases="["
  [ "$filename" != "$title" ] && aliases+="\"$filename\","
  aliases+="\"${filename//-/ }\""  # Dash to space
  aliases+="]"

  md-utils fm set --key aliases --value "$aliases" "$file" --in-place
done
```

### Sync Aliases Bidirectionally

```bash
#!/bin/bash
# sync-aliases.sh

vault_dir="${1:-vault}"

# Build alias map
declare -A alias_map

find "$vault_dir" -name "*.md" | while read -r file; do
  note_name=$(basename "$file" .md")
  aliases=$(md-utils fm get --key aliases "$file" 2>/dev/null)

  if [ -n "$aliases" ]; then
    echo "$aliases" | jq -r '.[]' | while read -r alias; do
      # Store mapping: alias -> actual note
      echo "$alias -> $note_name"
    done
  fi
done
```

## Property Inheritance

### Inherit Project Metadata

```bash
#!/bin/bash
# inherit-project-metadata.sh

vault_dir="${1:-vault}"

find "$vault_dir/Projects" -type d | while read -r project_dir; do
  project_file="$project_dir/Overview.md"

  if [ -f "$project_file" ]; then
    # Get project metadata
    project_name=$(md-utils fm get --key project "$project_file")
    project_status=$(md-utils fm get --key status "$project_file")

    # Apply to all notes in project
    find "$project_dir" -name "*.md" ! -name "Overview.md" | while read -r note; do
      md-utils fm set --key project --value "$project_name" \
        --key project-status --value "$project_status" \
        "$note" --in-place
    done
  fi
done
```

### Template Metadata

```bash
# Apply template metadata to new notes
apply_template_metadata() {
  local note="$1"
  local template="$2"

  # Copy metadata from template
  for key in tags type category; do
    value=$(md-utils fm get --key "$key" "$template" 2>/dev/null)
    if [ -n "$value" ]; then
      md-utils fm set --key "$key" --value "$value" "$note" --in-place
    fi
  done
}

# Usage
apply_template_metadata "vault/new-note.md" "vault/Templates/note-template.md"
```

## Status Tracking

### Update Note Status

```bash
#!/bin/bash
# update-status.sh

vault_dir="${1:-vault}"

find "$vault_dir" -name "*.md" | while read -r note; do
  # Determine status based on content markers
  if grep -q "- \[ \]" "$note"; then
    status="in-progress"
  elif grep -q "TODO:" "$note"; then
    status="draft"
  elif grep -q "DONE" "$note"; then
    status="completed"
  else
    status="active"
  fi

  md-utils fm set --key status --value "$status" \
    --key status-updated --value "$(date -I)" \
    "$note" --in-place
done
```

### Track Review Status

```bash
# Mark notes as reviewed
mark_reviewed() {
  local note="$1"

  md-utils fm set --key last-reviewed --value "$(date -I)" \
    --key review-count --value "$(( $(md-utils fm get --key review-count "$note" 2>/dev/null || echo 0) + 1 ))" \
    "$note" --in-place
}

# Find notes needing review (>30 days since last review)
cutoff_date=$(date -v-30d +%Y-%m-%d)
md-utils fm get --key last-reviewed --recursive vault/ | \
  awk -v cutoff="$cutoff_date" '$2 < cutoff {print $1}'
```

## Bulk Updates

### Mass Property Update

```bash
# Update property across entire vault
update_vault_property() {
  local key="$1"
  local value="$2"
  local vault_dir="${3:-vault}"

  find "$vault_dir" -name "*.md" | while read -r note; do
    md-utils fm set --key "$key" --value "$value" "$note" --in-place
  done

  echo "Updated $key=$value for all notes in $vault_dir"
}

# Usage
update_vault_property "vault-version" "2.0" "vault/"
```

### Conditional Updates

```bash
# Update property only if condition met
find vault/ -name "*.md" | while read -r note; do
  # Only update if note has specific tag
  tags=$(md-utils fm get --key tags "$note" 2>/dev/null)

  if echo "$tags" | grep -q "project"; then
    md-utils fm set --key requires-review --value "true" \
      "$note" --in-place
  fi
done
```

## Validation

### Metadata Schema Validation

```bash
#!/bin/bash
# validate-metadata.sh

required_fields="title created modified tags type"

find vault/ -name "*.md" | while read -r note; do
  errors=()

  for field in $required_fields; do
    if ! md-utils fm get --key "$field" "$note" >/dev/null 2>&1; then
      errors+=("Missing: $field")
    fi
  done

  if [ ${#errors[@]} -gt 0 ]; then
    echo "INVALID: $note"
    printf '  %s\n' "${errors[@]}"
  fi
done
```

### Fix Common Issues

```bash
#!/bin/bash
# fix-metadata-issues.sh

find vault/ -name "*.md" | while read -r note; do
  # Fix: Add missing created timestamp
  if ! md-utils fm get --key created "$note" >/dev/null 2>&1; then
    md-utils fm set --key created --value "$(date -I)" "$note" --in-place
  fi

  # Fix: Ensure tags is array
  tags=$(md-utils fm get --key tags "$note" 2>/dev/null)
  if [ -n "$tags" ] && ! echo "$tags" | grep -q "^\["; then
    md-utils fm set --key tags --value "[$tags]" "$note" --in-place
  fi

  # Fix: Remove empty fields
  # (requires custom logic per field)
done
```

## Best Practices

### Regular Sync Schedule

```bash
# Daily: Update timestamps for modified files
0 0 * * * ~/scripts/update-modified.sh ~/vault

# Weekly: Sync folder tags
0 0 * * 0 ~/scripts/sync-folder-tags.sh ~/vault

# Monthly: Full metadata validation
0 0 1 * * ~/scripts/validate-metadata.sh ~/vault
```

### Backup Before Bulk Updates

```bash
# Always backup before mass operations
backup_vault() {
  backup_dir="backups/vault-$(date +%Y%m%d-%H%M%S)"
  cp -r vault/ "$backup_dir"
  echo "Backup created: $backup_dir"
}

backup_vault
./bulk-update.sh vault/
```

## See Also

- <doc:NoteTaking>
- <doc:TemplateGeneration>
- <doc:../../Commands/FMSet>
- <doc:../Scripting/ShellIntegration>
