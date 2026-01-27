# Obsidian Workflows

Integrate md-utils with Obsidian for enhanced note-taking and knowledge management.

## Overview

Obsidian is a powerful knowledge base that works on local Markdown files. md-utils complements Obsidian by providing command-line tools for batch processing, automation, and advanced metadata management.

These workflows show how to use md-utils to enhance your Obsidian vault management, automate repetitive tasks, and maintain consistency across your notes.

## Common Use Cases

### Note Management

- Bulk update note metadata
- Standardize frontmatter across vault
- Add timestamps to notes
- Organize notes by tags and categories

### Metadata Synchronization

- Keep frontmatter in sync with file names
- Update modification timestamps
- Manage tags and aliases
- Track note relationships

### Template Generation

- Create note templates with frontmatter
- Generate daily/weekly note structures
- Automate recurring note creation
- Batch apply templates to existing notes

### Link Management

- Extract and analyze note links
- Generate link reports
- Find broken or orphaned notes
- Create link maps

## Key Features for Obsidian

### Frontmatter Management

Obsidian uses YAML frontmatter for metadata. md-utils provides powerful tools for managing this metadata:

```bash
# Add tags to all notes in a folder
md-utils fm set --key tags --value "inbox" --recursive vault/Inbox/ --in-place

# Set modification timestamp
md-utils fm set --key modified --value "$(date -I)" note.md --in-place

# Add aliases
md-utils fm set --key aliases --value "['Note Title', 'Alt Name']" note.md --in-place
```

### Batch Processing

Process multiple notes efficiently:

```bash
# Update all notes modified today
find vault/ -type f -name "*.md" -mtime 0 | \
  xargs -I {} md-utils fm set --key modified --value "$(date -I)" {} --in-place

# Add status field to all project notes
md-utils fm set --key status --value "in-progress" \
  --recursive vault/Projects/ --in-place
```

### Template Support

Generate consistent note structures:

```bash
# Create daily note template
md-utils fm set --key date --value "$(date -I)" \
  --key tags --value "['daily-note']" \
  --key template --value "daily" \
  daily-note.md --in-place
```

## Integration Patterns

### Vault-Wide Operations

```bash
# List all tags in vault
md-utils fm get --key tags --recursive vault/ | jq -s 'add | unique'

# Find notes without tags
find vault/ -name "*.md" -exec \
  sh -c 'md-utils fm get --key tags "$1" 2>/dev/null || echo "$1"' _ {} \;

# Update vault metadata
for note in vault/**/*.md; do
  md-utils fm set --key vault-version --value "2.0" "$note" --in-place
done
```

### File Organization

```bash
# Add folder-based tags
for folder in vault/*/; do
  tag=$(basename "$folder")
  md-utils fm set --key folder-tag --value "$tag" \
    --recursive "$folder" --in-place
done

# Sync filename to title
for file in vault/**/*.md; do
  title=$(basename "$file" .md | sed 's/-/ /g')
  md-utils fm set --key title --value "$title" "$file" --in-place
done
```

### Daily Workflows

```bash
# Morning routine: Create daily note
daily_note="vault/Daily/$(date +%Y-%m-%d).md"
md-utils fm set --key date --value "$(date -I)" \
  --key type --value "daily-note" \
  --key weather --value "sunny" \
  "$daily_note" --in-place

# Evening routine: Add review timestamp
md-utils fm set --key reviewed --value "$(date -I)" \
  --recursive vault/Daily/ --in-place
```

## Best Practices

### Backup First

Always backup your vault before running batch operations:

```bash
# Create timestamped backup
tar -czf "vault-backup-$(date +%Y%m%d-%H%M%S).tar.gz" vault/
```

### Test on Single Files

Test commands on a single note before running on entire vault:

```bash
# Test on one file
md-utils fm set --key test --value "value" vault/test-note.md

# If successful, apply to all
md-utils fm set --key test --value "value" --recursive vault/ --in-place
```

### Use Version Control

Track changes with git:

```bash
cd vault/
git add -A
git commit -m "Updated metadata with md-utils"
```

### Validate Results

Check results after batch operations:

```bash
# Verify tags were added
md-utils fm get --key tags --recursive vault/Inbox/

# Count notes with specific metadata
md-utils fm get --key status --recursive vault/ | grep -c "in-progress"
```

## Topics

- <doc:NoteTaking>
- <doc:LinkManagement>
- <doc:MetadataSync>
- <doc:TemplateGeneration>

## See Also

- <doc:../GeneralMarkdown/GeneralMarkdown>
- <doc:../Scripting/Scripting>
- <doc:../../Commands/FMSet>
