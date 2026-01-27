# Quality Control

Ensure documentation quality and consistency with automated validation.

## Overview

Quality control processes help maintain high standards across your documentation. md-utils enables automated validation of metadata, content structure, formatting, and compliance with documentation standards.

## Metadata Validation

### Schema Validation

```bash
#!/bin/bash
# validate-schema.sh

# Define required fields per document type
validate_schema() {
  local file="$1"
  local doc_type=$(md-utils fm get --key type "$file" 2>/dev/null)

  case "$doc_type" in
    guide)
      required_fields="title author date category difficulty"
      ;;
    api)
      required_fields="title version endpoint method"
      ;;
    tutorial)
      required_fields="title author date level duration"
      ;;
    *)
      required_fields="title date"
      ;;
  esac

  errors=()

  for field in $required_fields; do
    if ! md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
      errors+=("Missing required field: $field")
    fi
  done

  if [ ${#errors[@]} -gt 0 ]; then
    echo "INVALID: $file (type: $doc_type)"
    printf '  %s\n' "${errors[@]}"
    return 1
  fi

  return 0
}

# Validate all files
error_count=0

find docs/ -name "*.md" | while read -r file; do
  if ! validate_schema "$file"; then
    ((error_count++))
  fi
done

if [ $error_count -eq 0 ]; then
  echo "✓ All documents pass schema validation"
  exit 0
else
  echo "✗ Found $error_count validation errors"
  exit 1
fi
```

### Type Checking

```bash
#!/bin/bash
# validate-types.sh

# Check field value types
validate_field_type() {
  local file="$1"
  local field="$2"
  local expected_type="$3"

  value=$(md-utils fm get --key "$field" "$file" 2>/dev/null)

  case "$expected_type" in
    date)
      if ! date -d "$value" >/dev/null 2>&1; then
        echo "Invalid date in $file: $field=$value"
        return 1
      fi
      ;;
    number)
      if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "Invalid number in $file: $field=$value"
        return 1
      fi
      ;;
    boolean)
      if ! [[ "$value" =~ ^(true|false)$ ]]; then
        echo "Invalid boolean in $file: $field=$value"
        return 1
      fi
      ;;
    array)
      if ! [[ "$value" =~ ^\[.*\]$ ]]; then
        echo "Invalid array in $file: $field=$value"
        return 1
      fi
      ;;
  esac

  return 0
}

# Validate all documents
find docs/ -name "*.md" | while read -r file; do
  validate_field_type "$file" "date" "date"
  validate_field_type "$file" "version" "number"
  validate_field_type "$file" "draft" "boolean"
  validate_field_type "$file" "tags" "array"
done
```

### Constraint Validation

```bash
#!/bin/bash
# validate-constraints.sh

# Check value constraints
validate_constraints() {
  local file="$1"

  # Category must be from allowed list
  category=$(md-utils fm get --key category "$file" 2>/dev/null)
  allowed_categories="guide tutorial reference api changelog"

  if [ -n "$category" ] && ! echo "$allowed_categories" | grep -qw "$category"; then
    echo "Invalid category in $file: $category"
    echo "  Allowed: $allowed_categories"
    return 1
  fi

  # Version must match semantic versioning
  version=$(md-utils fm get --key version "$file" 2>/dev/null)

  if [ -n "$version" ] && ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version in $file: $version (expected semver)"
    return 1
  fi

  # Date must not be in future
  date=$(md-utils fm get --key date "$file" 2>/dev/null)

  if [ -n "$date" ]; then
    if [[ "$date" > "$(date -I)" ]]; then
      echo "Future date in $file: $date"
      return 1
    fi
  fi

  return 0
}

find docs/ -name "*.md" -exec bash -c 'validate_constraints "$0"' {} \;
```

## Content Validation

### Completeness Checks

```bash
#!/bin/bash
# check-completeness.sh

check_content() {
  local file="$1"
  local issues=()

  # Check for TODO markers
  if grep -q "TODO" "$file"; then
    issues+=("Contains TODO markers")
  fi

  # Check for placeholder text
  if grep -qi "lorem ipsum\|placeholder\|FIXME" "$file"; then
    issues+=("Contains placeholder text")
  fi

  # Check minimum content length
  word_count=$(md-utils body "$file" | wc -w)

  if [ "$word_count" -lt 100 ]; then
    issues+=("Content too short: $word_count words")
  fi

  # Check for headings
  if ! grep -q "^#" "$file"; then
    issues+=("No headings found")
  fi

  if [ ${#issues[@]} -gt 0 ]; then
    echo "INCOMPLETE: $file"
    printf '  %s\n' "${issues[@]}"
    return 1
  fi

  return 0
}

find docs/ -name "*.md" -exec bash -c 'check_content "$0"' {} \;
```

### Link Validation

```bash
#!/bin/bash
# validate-links.sh

echo "=== Link Validation ==="

# Check internal links
echo "Checking internal links..."
find docs/ -name "*.md" | while read -r file; do
  # Extract markdown links
  grep -on '\[.*\](.*\.md)' "$file" | while IFS=: read -r line_num link; do
    link_path=$(echo "$link" | sed -n 's/.*](\(.*\.md\).*/\1/p')

    # Resolve relative path
    dir=$(dirname "$file")
    target="$dir/$link_path"

    # Check if target exists
    if [ ! -f "$target" ]; then
      echo "BROKEN: $file:$line_num"
      echo "  Link: $link_path"
    fi
  done
done

# Check external links (optional - can be slow)
echo -e "\nChecking external links..."
find docs/ -name "*.md" -exec \
  grep -oh 'http[s]*://[^)]*' {} \; | \
  sort -u | while read -r url; do

  if ! curl --output /dev/null --silent --head --fail "$url" 2>/dev/null; then
    echo "BROKEN: $url"
  fi
done
```

### Code Block Validation

```bash
#!/bin/bash
# validate-code-blocks.sh

# Check that code blocks have language specified
find docs/ -name "*.md" | while read -r file; do
  # Find code blocks without language
  if grep -n '^```$' "$file"; then
    echo "Code block without language: $file"
    grep -n '^```$' "$file"
  fi
done

# Validate bash code blocks (syntax check)
find docs/ -name "*.md" | while read -r file; do
  # Extract bash code blocks
  awk '/```bash/,/```/' "$file" | \
    grep -v '```' | \
    bash -n 2>&1 && continue || echo "Invalid bash syntax in: $file"
done
```

## Consistency Checks

### Naming Conventions

```bash
#!/bin/bash
# check-naming.sh

echo "=== Naming Convention Checks ==="

# Check filename conventions
find docs/ -name "*.md" | while read -r file; do
  filename=$(basename "$file")

  # Filenames should be lowercase with dashes
  if [[ ! "$filename" =~ ^[a-z0-9-]+\.md$ ]]; then
    echo "Invalid filename: $file"
    echo "  Expected: lowercase-with-dashes.md"
  fi
done

# Check heading case
find docs/ -name "*.md" | while read -r file; do
  # H1 should be title case
  h1=$(grep -m 1 "^# " "$file" | sed 's/^# //')
  title=$(md-utils fm get --key title "$file" 2>/dev/null)

  if [ -n "$h1" ] && [ -n "$title" ] && [ "$h1" != "$title" ]; then
    echo "H1/title mismatch in $file"
    echo "  H1: $h1"
    echo "  Title: $title"
  fi
done
```

### Formatting Standards

```bash
#!/bin/bash
# check-formatting.sh

check_formatting() {
  local file="$1"
  local issues=()

  # Check for trailing whitespace
  if grep -q '[[:space:]]$' "$file"; then
    issues+=("Trailing whitespace found")
  fi

  # Check for multiple blank lines
  if grep -Pzo '\n\n\n' "$file" >/dev/null 2>&1; then
    issues+=("Multiple consecutive blank lines")
  fi

  # Check for tabs (should use spaces)
  if grep -q $'\t' "$file"; then
    issues+=("Contains tabs (use spaces)")
  fi

  # Check line length
  long_lines=$(awk 'length>120' "$file" | wc -l)
  if [ "$long_lines" -gt 0 ]; then
    issues+=("$long_lines lines exceed 120 characters")
  fi

  if [ ${#issues[@]} -gt 0 ]; then
    echo "FORMATTING: $file"
    printf '  %s\n' "${issues[@]}"
    return 1
  fi

  return 0
}

find docs/ -name "*.md" -exec bash -c 'check_formatting "$0"' {} \;
```

### Metadata Consistency

```bash
#!/bin/bash
# check-metadata-consistency.sh

# Check that related docs share metadata
check_consistency() {
  local category="$1"

  echo "=== Checking $category consistency ==="

  # Get all docs in category
  docs=$(md-utils fm get --key category --recursive docs/ | \
    grep "$category" | cut -d: -f1)

  # Collect all tags used in category
  all_tags=$(echo "$docs" | while read -r file; do
    md-utils fm get --key tags "$file" 2>/dev/null
  done | jq -s 'add | unique')

  echo "Tags in $category: $all_tags"

  # Check for outliers (docs missing common tags)
  echo "$docs" | while read -r file; do
    tags=$(md-utils fm get --key tags "$file" 2>/dev/null)

    # Flag if missing common category tag
    if ! echo "$tags" | grep -q "$category"; then
      echo "Missing category tag: $file"
    fi
  done
}

# Check each category
for category in guide tutorial reference api; do
  check_consistency "$category"
done
```

## Automated Quality Reports

### Comprehensive Quality Report

```bash
#!/bin/bash
# quality-report.sh

output="reports/quality-$(date +%Y-%m-%d).md"

cat > "$output" << EOF
# Documentation Quality Report

Generated: $(date)

## Summary

- Total files: $(find docs/ -name "*.md" | wc -l)
- Files with issues: TBD

## Validation Results

EOF

echo "### Schema Validation" >> "$output"
./validate-schema.sh 2>&1 | tee -a "$output"

echo -e "\n### Content Completeness" >> "$output"
./check-completeness.sh 2>&1 | tee -a "$output"

echo -e "\n### Link Validation" >> "$output"
./validate-links.sh 2>&1 | tee -a "$output"

echo -e "\n### Formatting" >> "$output"
./check-formatting.sh 2>&1 | tee -a "$output"

echo -e "\n### Naming Conventions" >> "$output"
./check-naming.sh 2>&1 | tee -a "$output"

echo "✓ Quality report saved: $output"
```

### CI/CD Integration

```bash
#!/bin/bash
# .github/workflows/quality-check.sh

set -e  # Exit on first error

echo "=== Documentation Quality Check ==="

# Run all validation scripts
./scripts/validate-schema.sh
./scripts/check-completeness.sh
./scripts/validate-links.sh
./scripts/check-formatting.sh

echo "✓ All quality checks passed"
exit 0
```

### Pre-Commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Validate staged markdown files
staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.md$')

if [ -z "$staged_files" ]; then
  exit 0
fi

echo "Validating staged documentation..."

for file in $staged_files; do
  # Schema validation
  if ! ./scripts/validate-schema.sh "$file" >/dev/null 2>&1; then
    echo "✗ Schema validation failed: $file"
    exit 1
  fi

  # Formatting check
  if grep -q '[[:space:]]$' "$file"; then
    echo "✗ Trailing whitespace in: $file"
    exit 1
  fi

  # Check for TODOs
  if grep -q "TODO" "$file"; then
    echo "⚠ Found TODO in: $file"
  fi
done

echo "✓ Documentation validation passed"
```

## Metrics and KPIs

### Quality Metrics

```bash
#!/bin/bash
# calculate-metrics.sh

total_docs=$(find docs/ -name "*.md" | wc -l)

# Completeness rate
docs_with_required=$(find docs/ -name "*.md" -exec sh -c \
  'md-utils fm get --key title "$1" >/dev/null 2>&1 && \
   md-utils fm get --key date "$1" >/dev/null 2>&1 && \
   echo "$1"' _ {} \; | wc -l)

completeness_rate=$((docs_with_required * 100 / total_docs))

# Average content length
total_words=$(find docs/ -name "*.md" -exec md-utils body {} \; | wc -w)
avg_words=$((total_words / total_docs))

# Documentation coverage (docs with examples)
docs_with_examples=$(grep -rl '```' docs/ --include="*.md" | wc -l)
example_coverage=$((docs_with_examples * 100 / total_docs))

cat << EOF
=== Documentation Quality Metrics ===

Total Documents: $total_docs
Completeness Rate: $completeness_rate%
Average Words: $avg_words
Example Coverage: $example_coverage%

EOF
```

### Trend Tracking

```bash
#!/bin/bash
# track-quality-trends.sh

metrics_file="metrics/quality-$(date +%Y-%m-%d).json"

# Calculate current metrics
./calculate-metrics.sh | jq -Rs '
{
  date: "'$(date -I)'",
  total_docs: '$(find docs/ -name "*.md" | wc -l)',
  completeness_rate: '$(./calculate-completeness.sh)',
  avg_words: '$(./calculate-avg-words.sh)'
}' > "$metrics_file"

# Generate trend report
jq -s '
  [
    .[] | {
      date: .date,
      total: .total_docs,
      completeness: .completeness_rate
    }
  ]
' metrics/*.json > reports/quality-trends.json

echo "✓ Metrics tracked: $metrics_file"
```

## Best Practices

### Regular Quality Audits

```bash
# Weekly quality audit
0 0 * * 0 cd ~/docs && ./scripts/quality-report.sh

# Daily validation of changed files
0 0 * * * cd ~/docs && ./scripts/validate-recent.sh

# Monthly comprehensive review
0 0 1 * * cd ~/docs && ./scripts/comprehensive-audit.sh
```

### Continuous Improvement

```bash
#!/bin/bash
# auto-fix-common-issues.sh

# Fix trailing whitespace
find docs/ -name "*.md" -exec sed -i '' 's/[[:space:]]*$//' {} \;

# Add missing frontmatter
find docs/ -name "*.md" | while read -r file; do
  if ! md-utils fm get --key date "$file" >/dev/null 2>&1; then
    # Add creation date from git
    created=$(git log --format="%aI" --reverse "$file" | head -1)
    md-utils fm set --key date --value "$created" "$file" --in-place
  fi
done

# Standardize heading levels
# (requires custom logic)
```

### Quality Gates

```bash
#!/bin/bash
# quality-gate.sh - Block merge if quality below threshold

min_completeness=90
min_example_coverage=70

current_completeness=$(./calculate-completeness.sh)
current_coverage=$(./calculate-example-coverage.sh)

if [ "$current_completeness" -lt "$min_completeness" ]; then
  echo "✗ Completeness below threshold: $current_completeness% < $min_completeness%"
  exit 1
fi

if [ "$current_coverage" -lt "$min_example_coverage" ]; then
  echo "✗ Example coverage below threshold: $current_coverage% < $min_example_coverage%"
  exit 1
fi

echo "✓ Quality gates passed"
```

## See Also

- <doc:DocumentationMaint>
- <doc:BatchProcessing>
- <doc:../Scripting/ErrorHandling>
