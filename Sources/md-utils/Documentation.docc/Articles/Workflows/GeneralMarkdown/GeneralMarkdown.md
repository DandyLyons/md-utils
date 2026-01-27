# General Markdown Workflows

Universal Markdown processing patterns applicable to any documentation workflow.

## Overview

These workflows apply to general Markdown usage beyond specific tools like Hugo or Obsidian. Whether you're maintaining documentation, writing technical content, or managing a knowledge base, md-utils provides powerful tools for Markdown manipulation and maintenance.

## Common Scenarios

### Documentation Maintenance

Keep documentation fresh, accurate, and well-organized:

- Update outdated information across multiple files
- Maintain consistent frontmatter metadata
- Generate table of contents for navigation
- Convert formats for different publishing platforms

### Batch Processing

Efficiently process large collections of Markdown files:

- Bulk metadata updates
- Recursive directory operations
- Pattern-based transformations
- Automated quality checks

### Content Migration

Move content between systems while preserving structure:

- Extract frontmatter for database import
- Convert between Markdown flavors
- Split or combine documents
- Normalize file structures

### Quality Control

Ensure consistency and correctness:

- Validate frontmatter schemas
- Check for missing metadata
- Find broken links
- Standardize formatting

## Key Capabilities

### Frontmatter Management

```bash
# Extract metadata from all docs
md-utils fm get --key author --recursive docs/

# Update version across all files
md-utils fm set --key version --value "2.0" --recursive docs/ --in-place

# List all unique tags
md-utils fm get --key tags --recursive docs/ | jq -s 'add | unique'
```

### Table of Contents

```bash
# Generate TOC for all docs
md-utils toc --recursive docs/ --output toc/

# Create navigation index
for file in docs/**/*.md; do
  md-utils toc "$file" --format markdown >> docs/INDEX.md
done
```

### Format Conversion

```bash
# Convert to plain text for indexing
md-utils convert to-text --recursive docs/ --output plain/

# Extract body content without frontmatter
md-utils body --recursive docs/ --output content/
```

## Integration Patterns

### CI/CD Pipelines

```bash
#!/bin/bash
# .github/workflows/docs.sh

# Validate all documentation
echo "Validating documentation..."

# Check for required frontmatter
find docs/ -name "*.md" | while read -r file; do
  for field in title date author; do
    if ! md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
      echo "ERROR: Missing $field in $file"
      exit 1
    fi
  done
done

echo "✓ All documentation valid"
```

### Build Systems

```bash
# Makefile integration
.PHONY: docs-validate docs-build

docs-validate:
\t@echo "Validating documentation..."
\t@./scripts/validate-docs.sh

docs-build: docs-validate
\t@echo "Building documentation..."
\t@md-utils toc --recursive docs/ --output build/toc/
\t@md-utils convert to-text --recursive docs/ --output build/search/
```

### Git Hooks

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Update modification timestamps
git diff --cached --name-only --diff-filter=M | grep '.md$' | while read -r file; do
  if [ -f "$file" ]; then
    md-utils fm set --key modified --value "$(date -I)" "$file" --in-place
    git add "$file"
  fi
done
```

## Common Patterns

### Recursive Processing

```bash
# Process all Markdown files in directory tree
md-utils fm set --key processed --value "$(date -I)" \
  --recursive docs/ \
  --in-place

# Include hidden files
md-utils fm get --key title \
  --recursive docs/ \
  --include-hidden

# Filter by extension
md-utils toc --recursive docs/ \
  --extensions md,markdown,mdown
```

### Output Management

```bash
# Output to directory (one file per input)
md-utils convert to-text \
  --recursive docs/ \
  --output output/

# Preserve directory structure
find docs/ -name "*.md" | while read -r file; do
  relative=$(echo "$file" | sed 's|^docs/||')
  output="build/$relative"
  mkdir -p "$(dirname "$output")"
  md-utils body "$file" > "$output"
done
```

### File Selection

```bash
# Process only files modified today
find docs/ -name "*.md" -mtime 0 -exec \
  md-utils fm set --key updated --value "true" {} --in-place \;

# Process files matching pattern
find docs/ -name "*-guide.md" -exec \
  md-utils fm set --key type --value "guide" {} --in-place \;

# Exclude specific directories
find docs/ -name "*.md" ! -path "*/drafts/*" ! -path "*/archive/*"
```

## Automation Examples

### Daily Maintenance

```bash
#!/bin/bash
# daily-maintenance.sh

docs_dir="docs"

echo "=== Daily Documentation Maintenance ==="

# Update timestamps
echo "Updating timestamps..."
find "$docs_dir" -name "*.md" -mtime 0 | while read -r file; do
  md-utils fm set --key modified --value "$(date -I)" "$file" --in-place
done

# Generate reports
echo "Generating reports..."
echo "Files modified today: $(find "$docs_dir" -name "*.md" -mtime 0 | wc -l)"
echo "Total docs: $(find "$docs_dir" -name "*.md" | wc -l)"

# Regenerate TOCs
echo "Updating table of contents..."
md-utils toc --recursive "$docs_dir" --output "$docs_dir/toc/"

echo "✓ Maintenance complete"
```

### Weekly Audit

```bash
#!/bin/bash
# weekly-audit.sh

# Check metadata completeness
echo "=== Metadata Audit ==="

for field in title author date; do
  missing=$(find docs/ -name "*.md" -exec sh -c \
    "md-utils fm get --key $field \"\$1\" >/dev/null 2>&1 || echo \"\$1\"" _ {} \;)

  if [ -n "$missing" ]; then
    echo "Missing $field:"
    echo "$missing" | sed 's/^/  /'
  fi
done

# Find stale content (>90 days since modification)
cutoff=$(date -v-90d +%Y-%m-%d)
echo -e "\n=== Stale Content ==="
md-utils fm get --key modified --recursive docs/ | \
  awk -v cutoff="$cutoff" '$2 < cutoff {print $1}'
```

## Best Practices

### Backup Strategy

```bash
# Always backup before bulk operations
backup_docs() {
  backup_dir="backups/docs-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"
  cp -r docs/ "$backup_dir/"
  echo "Backup created: $backup_dir"
}

# Usage
backup_docs
md-utils fm set --key version --value "2.0" --recursive docs/ --in-place
```

### Test First

```bash
# Test on sample before applying to all
test_dir="docs/test"

# Test command
md-utils fm set --key test --value "value" --recursive "$test_dir" --in-place

# Verify results
md-utils fm get --key test --recursive "$test_dir"

# If successful, apply to all
md-utils fm set --key test --value "value" --recursive docs/ --in-place
```

### Version Control

```bash
# Track documentation changes
cd docs/
git add -A
git commit -m "Update documentation metadata"
git tag docs-v2.0

# Review changes before committing
git diff --name-only | grep '.md$' | while read -r file; do
  echo "=== $file ==="
  git diff "$file" | head -20
done
```

## Topics

- <doc:DocumentationMaint>
- <doc:BatchProcessing>
- <doc:ContentMigration>
- <doc:QualityControl>

## See Also

- <doc:../HugoWorkflows/HugoWorkflows>
- <doc:../ObsidianWorkflows/ObsidianWorkflows>
- <doc:../Scripting/Scripting>
