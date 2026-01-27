# Note-Taking Workflows

Streamline note creation and organization in Obsidian with md-utils.

## Overview

md-utils enhances Obsidian's note-taking capabilities by automating metadata management, enforcing consistency, and enabling powerful batch operations. These workflows help you focus on writing while maintaining a well-organized vault.

## Quick Capture

### Create Note with Metadata

```bash
# Quick note creation
note="vault/$(date +%Y%m%d-%H%M)-quick-note.md"
md-utils fm set --key created --value "$(date -Iseconds)" \
  --key tags --value "['quick-capture', 'inbox']" \
  --key type --value "note" \
  "$note" --in-place
echo "# Quick Note\n\nContent here..." >> "$note"
```

### Inbox Processing

```bash
# Add processing timestamp to inbox notes
md-utils fm set --key processed --value "$(date -I)" \
  --recursive vault/Inbox/ --in-place

# Move processed notes (manual verification)
find vault/Inbox/ -name "*.md" -exec \
  sh -c 'if md-utils fm get --key processed "$1" >/dev/null 2>&1; then echo "$1"; fi' _ {} \;
```

## Daily Notes

### Generate Daily Note

```bash
#!/bin/bash
# daily-note.sh

daily_dir="vault/Daily"
daily_note="$daily_dir/$(date +%Y-%m-%d).md"

# Create daily note if it doesn't exist
if [ ! -f "$daily_note" ]; then
  touch "$daily_note"

  # Add frontmatter
  md-utils fm set --key date --value "$(date -I)" \
    --key day --value "$(date +%A)" \
    --key week --value "$(date +%V)" \
    --key tags --value "['daily']" \
    --key type --value "daily-note" \
    "$daily_note" --in-place

  # Add template content
  cat >> "$daily_note" << 'EOF'
# Daily Note - $(date +%A, %B %d, %Y)

## Morning

- [ ] Review calendar
- [ ] Plan priorities

## Notes


## Evening Review

- What went well?
- What could improve?
EOF

  echo "Created: $daily_note"
  open "$daily_note"  # macOS - opens in default editor
fi
```

### Weekly Review

```bash
# Find all daily notes from this week
week_start=$(date -v-mon +%Y-%m-%d)
md-utils fm get --key date --recursive vault/Daily/ | \
  awk -v start="$week_start" '$0 >= start'

# Update weekly review status
md-utils fm set --key week-reviewed --value "$(date -I)" \
  --recursive vault/Daily/ --in-place
```

## Meeting Notes

### Create Meeting Note

```bash
#!/bin/bash
# meeting-note.sh

meeting_title="$1"
attendees="$2"
meeting_date="${3:-$(date -I)}"

filename="vault/Meetings/${meeting_date}-${meeting_title// /-}.md"

md-utils fm set --key title --value "$meeting_title" \
  --key date --value "$meeting_date" \
  --key attendees --value "$attendees" \
  --key type --value "meeting" \
  --key tags --value "['meeting']" \
  "$filename" --in-place

cat >> "$filename" << EOF
# $meeting_title

**Date:** $meeting_date
**Attendees:** $attendees

## Agenda

-

## Discussion


## Action Items

- [ ]

## Decisions


## Next Meeting

EOF

echo "Created: $filename"
```

Usage:
```bash
./meeting-note.sh "Team Sync" "['Alice', 'Bob']" "2024-01-24"
```

## Project Notes

### Initialize Project

```bash
#!/bin/bash
# init-project.sh

project_name="$1"
project_dir="vault/Projects/$project_name"

mkdir -p "$project_dir"

# Create project overview
overview="$project_dir/Overview.md"
md-utils fm set --key project --value "$project_name" \
  --key status --value "planning" \
  --key created --value "$(date -I)" \
  --key type --value "project" \
  --key tags --value "['project']" \
  "$overview" --in-place

# Create standard project files
for file in "Tasks.md" "Notes.md" "Resources.md"; do
  note="$project_dir/$file"
  md-utils fm set --key project --value "$project_name" \
    --key type --value "project-$(echo $file | tr '[:upper:]' '[:lower:]' | sed 's/.md//')" \
    "$note" --in-place
done

echo "Project initialized: $project_dir"
```

### Update Project Status

```bash
# Mark project as active
md-utils fm set --key status --value "active" \
  --key started --value "$(date -I)" \
  --recursive "vault/Projects/My Project/" --in-place

# Archive completed project
md-utils fm set --key status --value "completed" \
  --key completed --value "$(date -I)" \
  --recursive "vault/Projects/My Project/" --in-place
```

## Research Notes

### Literature Note Template

```bash
# Create literature note
create_lit_note() {
  local title="$1"
  local author="$2"
  local year="$3"

  local filename="vault/Literature/${author}-${year}-${title// /-}.md"

  md-utils fm set --key title --value "$title" \
    --key author --value "$author" \
    --key year --value "$year" \
    --key type --value "literature" \
    --key tags --value "['literature', 'reading']" \
    --key added --value "$(date -I)" \
    "$filename" --in-place

  cat >> "$filename" << 'EOF'
# Literature Note

## Summary


## Key Points

-

## Quotes


## Related Notes

EOF
}

create_lit_note "Deep Work" "Cal Newport" "2016"
```

### Link to Source

```bash
# Add source URL to research notes
md-utils fm set --key source --value "https://example.com/article" \
  --key accessed --value "$(date -I)" \
  vault/Research/article-name.md --in-place
```

## Zettelkasten Method

### Create Permanent Note

```bash
#!/bin/bash
# zettel.sh - Create Zettelkasten note

timestamp=$(date +%Y%m%d%H%M%S)
title="$1"

filename="vault/Zettelkasten/${timestamp}.md"

md-utils fm set --key id --value "$timestamp" \
  --key title --value "$title" \
  --key created --value "$(date -Iseconds)" \
  --key type --value "permanent" \
  --key tags --value "['zettel']" \
  "$filename" --in-place

cat >> "$filename" << EOF
# $title

## Content


## Links

-

## References

EOF

echo "Zettel created: $filename (ID: $timestamp)"
```

### Link Notes

```bash
# Add backlink metadata
md-utils fm set --key linked-from --value "['20240124120000']" \
  vault/Zettelkasten/20240124130000.md --in-place

# Find notes linking to a specific note
grep -r "\[\[20240124120000\]\]" vault/Zettelkasten/
```

## Tagging Strategies

### Auto-Tag by Location

```bash
# Tag notes by folder
for dir in vault/Projects vault/Daily vault/Literature; do
  tag=$(basename "$dir" | tr '[:upper:]' '[:lower:]')
  md-utils fm set --key auto-tag --value "$tag" \
    --recursive "$dir" --in-place
done
```

### Multi-Tag Support

```bash
# Add multiple tags
md-utils fm set --key tags \
  --value "['productivity', 'tools', 'automation']" \
  note.md --in-place

# Append tag to existing tags (requires manual merge)
existing=$(md-utils fm get --key tags note.md)
new_tags=$(echo "$existing" | jq '. + ["new-tag"] | unique')
md-utils fm set --key tags --value "$new_tags" note.md --in-place
```

## Best Practices

### Consistent Metadata

```bash
# Ensure all notes have required fields
required_fields="created modified type tags"

for note in vault/**/*.md; do
  for field in $required_fields; do
    if ! md-utils fm get --key "$field" "$note" >/dev/null 2>&1; then
      echo "Missing $field: $note"
    fi
  done
done
```

### Timestamping

```bash
# Add created timestamp if missing
find vault/ -name "*.md" -exec sh -c '
  if ! md-utils fm get --key created "$1" >/dev/null 2>&1; then
    file_date=$(stat -f "%SB" -t "%Y-%m-%dT%H:%M:%S%z" "$1")
    md-utils fm set --key created --value "$file_date" "$1" --in-place
  fi
' _ {} \;
```

### Regular Maintenance

```bash
#!/bin/bash
# vault-maintenance.sh

# Update all modification timestamps
find vault/ -name "*.md" -mtime -1 -exec \
  md-utils fm set --key modified --value "$(date -I)" {} --in-place \;

# Report on vault statistics
echo "=== Vault Statistics ==="
echo "Total notes: $(find vault/ -name '*.md' | wc -l)"
echo "Modified today: $(find vault/ -name '*.md' -mtime 0 | wc -l)"
echo "Untagged notes: $(find vault/ -name '*.md' -exec sh -c \
  'md-utils fm get --key tags "$1" >/dev/null 2>&1 || echo "$1"' _ {} \; | wc -l)"
```

## See Also

- <doc:MetadataSync>
- <doc:TemplateGeneration>
- <doc:../../Commands/FMSet>
- <doc:../Scripting/ShellIntegration>
