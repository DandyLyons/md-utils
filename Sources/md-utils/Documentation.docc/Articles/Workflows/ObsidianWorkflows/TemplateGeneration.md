# Template Generation

Create and apply note templates in Obsidian with md-utils.

## Overview

Templates help maintain consistency across your Obsidian vault by providing standardized structures for different note types. md-utils enhances Obsidian's templating capabilities with powerful frontmatter management and batch operations.

## Basic Templates

### Simple Note Template

```bash
#!/bin/bash
# create-note.sh

template_dir="vault/Templates"
note_dir="vault/Notes"

note_name="$1"
template="${2:-default}"

template_file="$template_dir/$template.md"
new_note="$note_dir/$note_name.md"

# Copy template
cp "$template_file" "$new_note"

# Update frontmatter
md-utils fm set --key title --value "$note_name" \
  --key created --value "$(date -Iseconds)" \
  --key template-used --value "$template" \
  "$new_note" --in-place

echo "Created: $new_note"
open "$new_note"
```

### Template with Variables

```bash
#!/bin/bash
# template-expand.sh

expand_template() {
  local template="$1"
  local output="$2"
  shift 2

  # Copy template
  cp "$template" "$output"

  # Replace variables
  while [ $# -gt 0 ]; do
    key="$1"
    value="$2"
    shift 2

    # Replace in content
    sed -i '' "s/{{$key}}/$value/g" "$output"

    # Add to frontmatter
    md-utils fm set --key "$key" --value "$value" "$output" --in-place
  done
}

# Usage
expand_template "vault/Templates/project.md" "vault/Projects/new-project.md" \
  "project-name" "My Project" \
  "status" "active" \
  "lead" "Alice"
```

## Template Library

### Daily Note Template

```markdown
---
type: daily-note
date: {{DATE}}
day: {{DAY}}
week: {{WEEK}}
tags:
  - daily
---

# Daily Note - {{LONG_DATE}}

## Morning

- [ ] Review calendar
- [ ] Set daily priorities
- [ ] Check messages

## Notes

## Tasks

- [ ]

## Evening Review

### What went well?


### What could improve?


### Tomorrow's priorities

- [ ]

## Links

-
```

Script to create daily note:
```bash
#!/bin/bash
# daily-note.sh

daily_dir="vault/Daily"
date_str=$(date +%Y-%m-%d)
daily_note="$daily_dir/$date_str.md"

if [ -f "$daily_note" ]; then
  echo "Daily note already exists"
  open "$daily_note"
  exit 0
fi

# Create from template
cp "vault/Templates/daily.md" "$daily_note"

# Expand variables
sed -i '' "s/{{DATE}}/$(date -I)/g" "$daily_note"
sed -i '' "s/{{DAY}}/$(date +%A)/g" "$daily_note"
sed -i '' "s/{{WEEK}}/$(date +%V)/g" "$daily_note"
sed -i '' "s/{{LONG_DATE}}/$(date "+%A, %B %d, %Y")/g" "$daily_note"

# Set frontmatter
md-utils fm set --key date --value "$(date -I)" \
  --key day --value "$(date +%A)" \
  --key week --value "$(date +%V)" \
  "$daily_note" --in-place

echo "Created: $daily_note"
open "$daily_note"
```

### Meeting Note Template

```markdown
---
type: meeting
title: {{TITLE}}
date: {{DATE}}
attendees: {{ATTENDEES}}
tags:
  - meeting
---

# {{TITLE}}

**Date:** {{DATE}}
**Attendees:** {{ATTENDEES}}
**Location:** {{LOCATION}}

## Agenda

1.

## Discussion


## Action Items

- [ ]

## Decisions


## Next Steps


## Next Meeting

**Date:**
**Agenda:**
```

Script:
```bash
#!/bin/bash
# meeting-note.sh

title="$1"
attendees="$2"
date="${3:-$(date -I)}"

filename="vault/Meetings/${date}-${title// /-}.md"

cp "vault/Templates/meeting.md" "$filename"

# Expand template
sed -i '' "s/{{TITLE}}/$title/g" "$filename"
sed -i '' "s/{{DATE}}/$date/g" "$filename"
sed -i '' "s/{{ATTENDEES}}/$attendees/g" "$filename"
sed -i '' "s/{{LOCATION}}/Conference Room A/g" "$filename"

# Set frontmatter
md-utils fm set --key title --value "$title" \
  --key date --value "$date" \
  --key attendees --value "$attendees" \
  "$filename" --in-place

echo "Created: $filename"
```

### Project Template

```markdown
---
type: project
project: {{PROJECT_NAME}}
status: planning
created: {{CREATED}}
tags:
  - project
---

# {{PROJECT_NAME}}

## Overview


## Goals

- [ ]

## Timeline

**Start Date:**
**Target Date:**
**Status:** Planning

## Resources

### Team

-

### Links

-

## Tasks

- [ ]

## Notes


## Archive

<!-- Completed items -->
```

## Batch Template Application

### Apply Template to Multiple Files

```bash
#!/bin/bash
# batch-template.sh

template="$1"
shift
files=("$@")

for file in "${files[@]}"; do
  # Preserve existing content
  existing_body=$(md-utils body "$file" 2>/dev/null)

  # Get template frontmatter
  template_fm=$(md-utils fm dump "$template" 2>/dev/null)

  # Apply template frontmatter
  if [ -n "$template_fm" ]; then
    echo "$template_fm" | while IFS='=' read -r key value; do
      # Skip if already exists
      if ! md-utils fm get --key "$key" "$file" >/dev/null 2>&1; then
        md-utils fm set --key "$key" --value "$value" "$file" --in-place
      fi
    done
  fi

  echo "Applied template to: $file"
done
```

### Migrate to New Template

```bash
#!/bin/bash
# migrate-template.sh - Update notes to new template structure

old_template_tag="v1-template"
new_template="vault/Templates/note-v2.md"

# Find all notes using old template
md-utils fm get --key template-version --recursive vault/ | \
  grep "v1" | cut -d: -f1 | while read -r note; do

  echo "Migrating: $note"

  # Get new template frontmatter
  for key in $(md-utils fm list "$new_template"); do
    value=$(md-utils fm get --key "$key" "$new_template")
    md-utils fm set --key "$key" --value "$value" "$note" --in-place
  done

  # Update version
  md-utils fm set --key template-version --value "v2" \
    --key migrated --value "$(date -I)" \
    "$note" --in-place
done
```

## Dynamic Templates

### Context-Aware Templates

```bash
#!/bin/bash
# smart-template.sh

note_name="$1"
vault_dir="vault"

# Determine template based on note name or location
if [[ "$note_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  template="daily"
  output_dir="$vault_dir/Daily"
elif [[ "$note_name" == meeting-* ]]; then
  template="meeting"
  output_dir="$vault_dir/Meetings"
elif [[ "$note_name" == project-* ]]; then
  template="project"
  output_dir="$vault_dir/Projects"
else
  template="default"
  output_dir="$vault_dir/Notes"
fi

output_file="$output_dir/$note_name.md"

echo "Using template: $template"
./create-note.sh "$note_name" "$template"
```

### Inherited Templates

```bash
#!/bin/bash
# inherit-template.sh - Child notes inherit from parent

parent_note="$1"
child_name="$2"

parent_dir=$(dirname "$parent_note")
child_note="$parent_dir/$child_name.md"

# Copy template structure
template=$(md-utils fm get --key template "$parent_note")
cp "vault/Templates/$template.md" "$child_note"

# Inherit specific fields
for key in project tags category; do
  value=$(md-utils fm get --key "$key" "$parent_note" 2>/dev/null)
  if [ -n "$value" ]; then
    md-utils fm set --key "$key" --value "$value" "$child_note" --in-place
  fi
done

# Set parent reference
parent_name=$(basename "$parent_note" .md)
md-utils fm set --key parent --value "$parent_name" \
  --key created --value "$(date -Iseconds)" \
  "$child_note" --in-place

echo "Created child note: $child_note"
```

## Template Validation

### Check Template Compliance

```bash
#!/bin/bash
# validate-template.sh

template_name="$1"
template_file="vault/Templates/$template_name.md"

echo "Validating notes using template: $template_name"

# Get required fields from template
required_fields=$(md-utils fm list "$template_file")

# Check all notes using this template
md-utils fm get --key template-used --recursive vault/ | \
  grep "$template_name" | cut -d: -f1 | while read -r note; do

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

### Auto-Fix Template Issues

```bash
#!/bin/bash
# fix-template-compliance.sh

template="vault/Templates/note.md"

# Find non-compliant notes
md-utils fm get --key template-used --recursive vault/ | \
  grep "note" | cut -d: -f1 | while read -r note; do

  # Check each required field
  md-utils fm list "$template" | while read -r field; do
    # If missing, copy from template
    if ! md-utils fm get --key "$field" "$note" >/dev/null 2>&1; then
      value=$(md-utils fm get --key "$field" "$template")
      md-utils fm set --key "$field" --value "$value" "$note" --in-place
      echo "Fixed $field in: $note"
    fi
  done
done
```

## Template Collections

### Template Picker

```bash
#!/bin/bash
# pick-template.sh

template_dir="vault/Templates"

echo "Available templates:"
templates=($(ls "$template_dir"/*.md | xargs -n1 basename | sed 's/.md//'))

select template in "${templates[@]}"; do
  if [ -n "$template" ]; then
    echo "Selected: $template"

    read -p "Note name: " note_name
    ./create-note.sh "$note_name" "$template"
    break
  fi
done
```

### Template Catalog

```bash
#!/bin/bash
# list-templates.sh

template_dir="vault/Templates"

echo "=== Template Catalog ==="

find "$template_dir" -name "*.md" | while read -r template; do
  name=$(basename "$template" .md)
  description=$(md-utils fm get --key description "$template" 2>/dev/null || echo "No description")
  type=$(md-utils fm get --key type "$template" 2>/dev/null || echo "unknown")

  echo ""
  echo "Template: $name"
  echo "  Type: $type"
  echo "  Description: $description"
  echo "  Fields:"
  md-utils fm list "$template" | sed 's/^/    - /'
done
```

## Advanced Patterns

### Nested Templates

```bash
# Template composition
compose_template() {
  local base_template="$1"
  local extension_template="$2"
  local output="$3"

  # Start with base
  cp "$base_template" "$output"

  # Merge frontmatter from extension
  md-utils fm dump "$extension_template" | while IFS='=' read -r key value; do
    md-utils fm set --key "$key" --value "$value" "$output" --in-place
  done

  # Append extension content
  md-utils body "$extension_template" >> "$output"
}

# Usage: Create project-meeting template from project + meeting
compose_template \
  "vault/Templates/project.md" \
  "vault/Templates/meeting.md" \
  "vault/Templates/project-meeting.md"
```

### Conditional Sections

```bash
# Template with conditional sections
create_conditional_note() {
  local template="$1"
  local output="$2"
  local include_sections="$3"  # Comma-separated: "tasks,links,review"

  cp "$template" "$output"

  # Remove sections not in include list
  IFS=',' read -ra sections <<< "$include_sections"

  # Remove unwanted sections
  if [[ ! " ${sections[@]} " =~ " tasks " ]]; then
    sed -i '' '/## Tasks/,/^##/d' "$output"
  fi

  if [[ ! " ${sections[@]} " =~ " links " ]]; then
    sed -i '' '/## Links/,/^##/d' "$output"
  fi
}
```

## Best Practices

### Version Control for Templates

```bash
# Track template changes
cd vault/Templates
git add *.md
git commit -m "Updated meeting template with location field"

# Tag template versions
git tag template-v2.0
```

### Template Documentation

Add to each template:
```markdown
---
template-name: meeting-note
template-version: 2.0
description: Standard meeting note template
required-fields:
  - title
  - date
  - attendees
optional-fields:
  - location
  - recording
---
```

### Testing Templates

```bash
#!/bin/bash
# test-template.sh

template="$1"
test_dir="vault/.template-tests"

mkdir -p "$test_dir"

# Create test note
test_note="$test_dir/test-$(date +%s).md"
./create-note.sh "test-note" "$template"

# Validate
./validate-template.sh "$template"

# Cleanup
rm -rf "$test_dir"
```

## See Also

- <doc:NoteTaking>
- <doc:MetadataSync>
- <doc:../../Commands/FMSet>
- <doc:../Scripting/ShellIntegration>
