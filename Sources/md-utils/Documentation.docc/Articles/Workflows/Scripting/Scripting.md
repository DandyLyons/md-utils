# Scripting & Automation

Build powerful automation workflows with md-utils and shell scripting.

## Overview

md-utils is designed for scripting and automation. Its command-line interface integrates seamlessly with shell scripts, build systems, and CI/CD pipelines. Whether you're automating documentation maintenance, building content processing workflows, or creating custom tools, md-utils provides the foundation.

## Why Script with md-utils?

### Pipeline-Friendly Design

- **Standard I/O**: Works with pipes, redirects, and process substitution
- **Exit Codes**: Proper error codes for script control flow
- **Batch Operations**: Efficient recursive processing
- **Multiple Formats**: JSON, YAML, Markdown, plain text output

### Integration Points

- **Shell Scripts**: Bash, zsh, fish integration
- **Build Systems**: Make, CMake, Gradle
- **CI/CD**: GitHub Actions, GitLab CI, Jenkins
- **Task Runners**: npm scripts, just, task
- **Git Hooks**: pre-commit, pre-push, post-merge

## Basic Scripting Patterns

### Simple Automation

```bash
#!/bin/bash
# update-docs.sh

# Update modification timestamps
find docs/ -name "*.md" -mtime -1 | while read -r file; do
  md-utils fm set --key modified --value "$(date -I)" "$file" --in-place
done

# Regenerate TOCs
md-utils toc --recursive docs/ --output docs/toc/

echo "✓ Documentation updated"
```

### Data Processing

```bash
#!/bin/bash
# extract-metadata.sh

# Extract all titles and dates to CSV
echo "file,title,date" > metadata.csv

md-utils fm get --key title --recursive docs/ > titles.txt
md-utils fm get --key date --recursive docs/ > dates.txt

paste -d, titles.txt dates.txt >> metadata.csv

echo "✓ Metadata extracted to metadata.csv"
```

### Conditional Logic

```bash
#!/bin/bash
# conditional-update.sh

for file in docs/**/*.md; do
  category=$(md-utils fm get --key category "$file" 2>/dev/null)

  if [ "$category" = "api" ]; then
    # Update API docs
    md-utils fm set --key api_version --value "2.0" "$file" --in-place
  elif [ "$category" = "guide" ]; then
    # Update guides
    md-utils fm set --key reviewed --value "$(date -I)" "$file" --in-place
  fi
done
```

## Advanced Patterns

### Function Libraries

```bash
#!/bin/bash
# lib/md-utils-helpers.sh

# Reusable functions for md-utils automation

# Check if file has required metadata
has_required_metadata() {
  local file="$1"
  shift
  local required_fields=("$@")

  for field in "${required_fields[@]}"; do
    if ! md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
      return 1
    fi
  done

  return 0
}

# Safely update metadata
safe_update() {
  local file="$1"
  local key="$2"
  local value="$3"

  # Backup
  cp "$file" "${file}.bak"

  # Update
  if md-utils fm set --key "$key" --value "$value" "$file" --in-place; then
    rm "${file}.bak"
    return 0
  else
    # Restore on failure
    mv "${file}.bak" "$file"
    return 1
  fi
}

# Extract structured data
extract_to_json() {
  local dir="$1"

  find "$dir" -name "*.md" -exec md-utils fm dump --format json {} \; | \
    jq -s '.'
}
```

Usage:
```bash
#!/bin/bash
source lib/md-utils-helpers.sh

if has_required_metadata "docs/guide.md" title date author; then
  safe_update "docs/guide.md" "validated" "true"
fi
```

### Configuration Files

```bash
#!/bin/bash
# config.sh

# Documentation configuration
DOCS_DIR="docs"
OUTPUT_DIR="build"
REQUIRED_FIELDS="title date author category"
ALLOWED_CATEGORIES="guide tutorial reference api"

# Load from external file
if [ -f ".md-utils.conf" ]; then
  source ".md-utils.conf"
fi
```

### Command Templates

```bash
#!/bin/bash
# templates.sh

# Define command templates
run_validation() {
  local dir="${1:-docs}"

  md-utils fm get --key title --recursive "$dir" | \
    awk '{if (NF < 2) print "Missing title:", $1}'
}

run_batch_update() {
  local key="$1"
  local value="$2"
  local dir="${3:-docs}"

  md-utils fm set --key "$key" --value "$value" \
    --recursive "$dir" --in-place
}

generate_reports() {
  local dir="${1:-docs}"
  local output="${2:-reports}"

  mkdir -p "$output"

  md-utils toc --recursive "$dir" --output "$output/toc/"
  md-utils convert to-text --recursive "$dir" --output "$output/plain/"
}
```

## Common Use Cases

### Documentation Build Pipeline

```bash
#!/bin/bash
# build-docs.sh

set -e  # Exit on error

echo "=== Building Documentation ==="

# Stage 1: Validation
echo "Stage 1: Validating..."
./scripts/validate-docs.sh

# Stage 2: Update metadata
echo "Stage 2: Updating metadata..."
md-utils fm set --key build_date --value "$(date -I)" \
  --recursive docs/ --in-place

# Stage 3: Generate TOCs
echo "Stage 3: Generating TOCs..."
md-utils toc --recursive docs/ --output build/toc/

# Stage 4: Convert formats
echo "Stage 4: Converting formats..."
md-utils convert to-text --recursive docs/ --output build/search/

# Stage 5: Build site
echo "Stage 5: Building site..."
hugo --source docs/ --destination build/site/

echo "✓ Build complete: build/"
```

### Content Synchronization

```bash
#!/bin/bash
# sync-content.sh

# Sync between two documentation sets

source_dir="$1"
target_dir="$2"

find "$source_dir" -name "*.md" | while read -r source; do
  relative=$(echo "$source" | sed "s|^$source_dir/||")
  target="$target_dir/$relative"

  # Copy if target doesn't exist or source is newer
  if [ ! -f "$target" ] || [ "$source" -nt "$target" ]; then
    echo "Syncing: $relative"

    mkdir -p "$(dirname "$target")"
    cp "$source" "$target"

    # Update sync timestamp
    md-utils fm set --key synced_from --value "$source" \
      --key synced_at --value "$(date -Iseconds)" \
      "$target" --in-place
  fi
done

echo "✓ Content synchronized"
```

### Automated Maintenance

```bash
#!/bin/bash
# maintenance.sh

# Daily maintenance tasks

DOCS_DIR="docs"

echo "=== Daily Maintenance: $(date) ==="

# Update timestamps for modified files
echo "Updating timestamps..."
find "$DOCS_DIR" -name "*.md" -mtime -1 | while read -r file; do
  md-utils fm set --key modified --value "$(date -I)" "$file" --in-place
done

# Clean up old drafts
echo "Cleaning drafts..."
find "$DOCS_DIR" -name "*.md" | while read -r file; do
  draft=$(md-utils fm get --key draft "$file" 2>/dev/null)
  created=$(md-utils fm get --key created "$file" 2>/dev/null)

  if [ "$draft" = "true" ]; then
    # Delete drafts older than 30 days
    age=$(( ($(date +%s) - $(date -d "$created" +%s)) / 86400 ))
    if [ "$age" -gt 30 ]; then
      echo "Removing old draft: $file"
      mv "$file" "$DOCS_DIR/.archive/"
    fi
  fi
done

# Generate reports
echo "Generating reports..."
./scripts/generate-report.sh > "reports/daily-$(date +%Y-%m-%d).md"

echo "✓ Maintenance complete"
```

## Integration Examples

### Git Hooks

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Update frontmatter before commit

staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$')

if [ -n "$staged_files" ]; then
  echo "Updating frontmatter for staged files..."

  echo "$staged_files" | while read -r file; do
    md-utils fm set --key modified --value "$(date -I)" "$file" --in-place
    git add "$file"
  done
fi
```

### Makefile

```makefile
# Makefile

DOCS_DIR := docs
BUILD_DIR := build

.PHONY: all validate build clean

all: validate build

validate:
\t@echo "Validating documentation..."
\t@./scripts/validate-docs.sh

build: validate
\t@echo "Building documentation..."
\t@mkdir -p $(BUILD_DIR)
\t@md-utils toc --recursive $(DOCS_DIR) --output $(BUILD_DIR)/toc
\t@md-utils convert to-text --recursive $(DOCS_DIR) --output $(BUILD_DIR)/search

update-timestamps:
\t@find $(DOCS_DIR) -name "*.md" -mtime -1 -exec \
\t\tmd-utils fm set --key modified --value "$$(date -I)" {} --in-place \;

clean:
\t@rm -rf $(BUILD_DIR)

.SILENT: validate build
```

### npm Scripts

```json
{
  "scripts": {
    "docs:validate": "./scripts/validate-docs.sh",
    "docs:build": "md-utils toc --recursive docs/ --output build/",
    "docs:update": "find docs/ -name '*.md' -exec md-utils fm set --key modified --value \"$(date -I)\" {} --in-place \\;",
    "docs:clean": "rm -rf build/",
    "docs": "npm run docs:validate && npm run docs:build"
  }
}
```

### GitHub Actions

```yaml
# .github/workflows/docs.yml

name: Documentation

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install md-utils
        run: |
          # Install instructions

      - name: Validate documentation
        run: ./scripts/validate-docs.sh

      - name: Build documentation
        run: |
          md-utils toc --recursive docs/ --output build/toc/
          md-utils convert to-text --recursive docs/ --output build/search/
```

## Topics

- <doc:ShellIntegration>
- <doc:PipelinePatterns>
- <doc:ErrorHandling>

## See Also

- <doc:../GeneralMarkdown/BatchProcessing>
- <doc:../GeneralMarkdown/DocumentationMaint>
- <doc:../../GlobalOptions>
