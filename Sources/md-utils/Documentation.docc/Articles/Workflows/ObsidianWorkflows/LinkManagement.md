# Link Management

Analyze and manage links in your Obsidian vault with md-utils.

## Overview

Obsidian's linking system is powerful but can become complex as your vault grows. md-utils helps you analyze link patterns, find broken links, identify orphaned notes, and maintain link integrity across your knowledge base.

## Link Analysis

### Extract All Links

```bash
# Find all wikilinks in vault
grep -r "\[\[.*\]\]" vault/ --include="*.md" | \
  sed 's/.*\[\[\([^]]*\)\]\].*/\1/' | \
  sort | uniq -c | sort -rn

# Extract markdown links
grep -r "\[.*\](.*)" vault/ --include="*.md" -o
```

### Link Statistics

```bash
#!/bin/bash
# link-stats.sh

vault_dir="${1:-vault}"

echo "=== Link Statistics ==="

# Count total wikilinks
total_wikilinks=$(grep -r "\[\[" "$vault_dir" --include="*.md" | wc -l)
echo "Total wikilinks: $total_wikilinks"

# Count unique linked notes
unique_links=$(grep -roh "\[\[[^]]*\]\]" "$vault_dir" --include="*.md" | \
  sed 's/\[\[\(.*\)\]\]/\1/' | sed 's/|.*//' | sort -u | wc -l)
echo "Unique notes linked: $unique_links"

# Count external links
external_links=$(grep -r "](http" "$vault_dir" --include="*.md" | wc -l)
echo "External links: $external_links"

# Most linked notes
echo -e "\n=== Most Linked Notes ==="
grep -roh "\[\[[^]]*\]\]" "$vault_dir" --include="*.md" | \
  sed 's/\[\[\(.*\)\]\]/\1/' | sed 's/|.*//' | \
  sort | uniq -c | sort -rn | head -10
```

## Finding Broken Links

### Detect Missing Files

```bash
#!/bin/bash
# check-broken-links.sh

vault_dir="${1:-vault}"

echo "Checking for broken wikilinks..."

# Extract all wikilinks
grep -roh "\[\[[^]]*\]\]" "$vault_dir" --include="*.md" | \
  sed 's/\[\[\(.*\)\]\]/\1/' | sed 's/|.*//' | \
  sort -u | while read -r link; do

  # Check if file exists
  if [ ! -f "$vault_dir/$link.md" ]; then
    echo "BROKEN: [[$link]]"

    # Find files containing this broken link
    echo "  Found in:"
    grep -rl "\[\[$link\]\]" "$vault_dir" --include="*.md" | \
      sed 's/^/    /'
  fi
done
```

### Track Link Metadata

```bash
# Add link count to frontmatter
for note in vault/**/*.md; do
  link_count=$(grep -o "\[\[" "$note" | wc -l)
  md-utils fm set --key outbound-links --value "$link_count" \
    "$note" --in-place
done

# Find notes with many outbound links
md-utils fm get --key outbound-links --recursive vault/ | \
  awk '$2 > 10 {print $1, $2}'
```

## Orphaned Notes

### Find Orphans

```bash
#!/bin/bash
# find-orphans.sh - Notes with no incoming links

vault_dir="${1:-vault}"

echo "Finding orphaned notes..."

# Get all notes
all_notes=$(find "$vault_dir" -name "*.md" -exec basename {} .md \;)

# Get all linked notes
linked_notes=$(grep -roh "\[\[[^]]*\]\]" "$vault_dir" --include="*.md" | \
  sed 's/\[\[\(.*\)\]\]/\1/' | sed 's/|.*//' | sort -u)

# Find difference
echo "$all_notes" | while read -r note; do
  if ! echo "$linked_notes" | grep -qx "$note"; then
    echo "ORPHAN: $note.md"
  fi
done
```

### Auto-Link Orphans

```bash
# Add "orphan" tag to notes with no incoming links
./find-orphans.sh vault/ | grep "ORPHAN:" | \
  sed 's/ORPHAN: /vault\//' | while read -r file; do
    md-utils fm set --key tags --value "['orphan']" "$file" --in-place
    echo "Tagged: $file"
  done
```

## Backlink Management

### Generate Backlink Report

```bash
#!/bin/bash
# backlinks.sh - Generate backlink report for a note

note_name="$1"
vault_dir="${2:-vault}"

echo "=== Backlinks for: $note_name ==="

# Find all files linking to this note
grep -rl "\[\[$note_name\]\]" "$vault_dir" --include="*.md" | \
  while read -r linking_file; do
    echo "- $(basename "$linking_file")"

    # Extract context around link
    grep -n "\[\[$note_name\]\]" "$linking_file" | head -1 | \
      sed 's/^/  Line /'
  done
```

### Store Backlinks in Frontmatter

```bash
#!/bin/bash
# update-backlinks.sh

vault_dir="${1:-vault}"

for note in "$vault_dir"/**/*.md; do
  note_name=$(basename "$note" .md)

  # Find backlinks
  backlinks=$(grep -rl "\[\[$note_name\]\]" "$vault_dir" --include="*.md" | \
    grep -v "$note" | \
    xargs -n1 basename | sed 's/.md$//' | \
    jq -R . | jq -s .)

  # Update frontmatter
  if [ "$backlinks" != "[]" ]; then
    md-utils fm set --key backlinks --value "$backlinks" \
      "$note" --in-place
  fi
done
```

## Link Graphs

### Generate Link Map

```bash
#!/bin/bash
# link-map.sh - Generate GraphViz dot file of vault links

vault_dir="${1:-vault}"
output="${2:-links.dot}"

echo "digraph VaultLinks {" > "$output"
echo "  rankdir=LR;" >> "$output"
echo "  node [shape=box];" >> "$output"

# Process each note
find "$vault_dir" -name "*.md" | while read -r file; do
  source=$(basename "$file" .md)

  # Find all links from this note
  grep -oh "\[\[[^]]*\]\]" "$file" | \
    sed 's/\[\[\(.*\)\]\]/\1/' | sed 's/|.*//' | \
    while read -r target; do
      echo "  \"$source\" -> \"$target\";" >> "$output"
    done
done

echo "}" >> "$output"

echo "Link map saved to: $output"
echo "Render with: dot -Tpng $output -o links.png"
```

### Cluster Analysis

```bash
# Find isolated note clusters
find vault/ -name "*.md" | while read -r note; do
  note_name=$(basename "$note" .md)

  # Count connections (inbound + outbound)
  outbound=$(grep -o "\[\[" "$note" | wc -l)
  inbound=$(grep -rl "\[\[$note_name\]\]" vault/ --include="*.md" | \
    grep -v "$note" | wc -l)

  total=$((outbound + inbound))

  # Flag isolated notes (< 3 connections)
  if [ $total -lt 3 ]; then
    echo "ISOLATED: $note_name (connections: $total)"
    md-utils fm set --key isolation-score --value "$total" \
      "$note" --in-place
  fi
done
```

## Link Refactoring

### Rename Note and Update Links

```bash
#!/bin/bash
# rename-note.sh

old_name="$1"
new_name="$2"
vault_dir="${3:-vault}"

old_file="$vault_dir/$old_name.md"
new_file="$vault_dir/$new_name.md"

# Rename file
mv "$old_file" "$new_file"

# Update all links to this note
find "$vault_dir" -name "*.md" -exec \
  sed -i '' "s/\[\[$old_name\]\]/\[\[$new_name\]\]/g" {} \;

# Update frontmatter title
md-utils fm set --key title --value "$new_name" "$new_file" --in-place

echo "Renamed: $old_name -> $new_name"
echo "Updated all links in vault"
```

### Convert Wikilinks to Markdown Links

```bash
# Convert [[Note]] to [Note](Note.md)
find vault/ -name "*.md" -exec \
  sed -i '' 's/\[\[\([^]]*\)\]\]/[\1](\1.md)/g' {} \;
```

### Consolidate Duplicate Links

```bash
#!/bin/bash
# Remove duplicate link references in a note

note="$1"

# Extract unique links
unique_links=$(grep -oh "\[\[[^]]*\]\]" "$note" | sort -u)

# Create temp file with unique links section
temp_file=$(mktemp)
sed '/## Links/,$d' "$note" > "$temp_file"

echo -e "\n## Links\n" >> "$temp_file"
echo "$unique_links" | while read -r link; do
  echo "- $link" >> "$temp_file"
done

mv "$temp_file" "$note"
```

## Link Validation

### Check External Links

```bash
#!/bin/bash
# check-external-links.sh

vault_dir="${1:-vault}"

echo "Checking external links..."

grep -roh "](http[^)]*)" "$vault_dir" --include="*.md" | \
  sed 's/](\(.*\))/\1/' | sort -u | while read -r url; do

  # Check if URL is accessible
  if curl --output /dev/null --silent --head --fail "$url"; then
    echo "✓ $url"
  else
    echo "✗ $url"
    echo "  Found in:"
    grep -rl "$url" "$vault_dir" --include="*.md" | sed 's/^/    /'
  fi
done
```

### Track Link Health

```bash
# Add link validation timestamp
for note in vault/**/*.md; do
  external_count=$(grep -c "](http" "$note" 2>/dev/null || echo 0)

  md-utils fm set --key external-links --value "$external_count" \
    --key link-check --value "$(date -I)" \
    "$note" --in-place
done
```

## Link Templates

### Standard Link Section

```bash
# Add consistent link section to notes
add_link_section() {
  local note="$1"

  if ! grep -q "## Links" "$note"; then
    cat >> "$note" << 'EOF'

## Links

### Related Notes

-

### External Resources

-

### Backlinks

<!-- Automatically generated -->
EOF
  fi
}

# Apply to all project notes
find vault/Projects/ -name "*.md" -exec bash -c 'add_link_section "$0"' {} \;
```

## Best Practices

### Regular Link Audits

```bash
#!/bin/bash
# weekly-link-audit.sh

echo "=== Weekly Link Audit ==="
echo "Date: $(date)"

# Run all checks
./check-broken-links.sh vault/
./find-orphans.sh vault/
./link-stats.sh vault/

# Save report
./weekly-link-audit.sh > "reports/links-$(date +%Y-%m-%d).txt"
```

### Link Conventions

```bash
# Enforce link style guidelines

# Find links with spaces (should use dashes)
grep -r "\[\[[^]]*\s[^]]*\]\]" vault/ --include="*.md"

# Find absolute paths (should be relative)
grep -r "\[\[/" vault/ --include="*.md"
```

### Maintenance Schedule

```bash
# Add to crontab for regular maintenance

# Daily: Update backlinks
0 0 * * * cd ~/vault && ./update-backlinks.sh vault/

# Weekly: Full link audit
0 0 * * 0 cd ~/vault && ./weekly-link-audit.sh

# Monthly: Check external links
0 0 1 * * cd ~/vault && ./check-external-links.sh vault/
```

## See Also

- <doc:NoteTaking>
- <doc:MetadataSync>
- <doc:../GeneralMarkdown/BatchProcessing>
- <doc:../Scripting/PipelinePatterns>
