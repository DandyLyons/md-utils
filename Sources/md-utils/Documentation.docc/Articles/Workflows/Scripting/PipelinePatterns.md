# Pipeline Patterns

Build efficient data processing pipelines with md-utils.

## Overview

md-utils excels at pipeline-based processing, where data flows through a series of transformations. This guide covers common pipeline patterns, composition techniques, and strategies for building maintainable, efficient data processing workflows.

## Basic Pipeline Concepts

### Unix Pipeline Philosophy

md-utils follows Unix philosophy:
- Do one thing well
- Work with text streams
- Compose into larger tools
- Use standard I/O

### Pipeline Structure

```
Input → Transform → Filter → Process → Output
```

## Simple Pipelines

### Linear Processing

```bash
# Extract → Transform → Output
md-utils fm get --key title --recursive docs/ | \
  sort | \
  uniq
```

```bash
# Read → Process → Write
md-utils body post.md | \
  wc -w | \
  xargs echo "Word count:"
```

### Data Extraction

```bash
# Extract all tags, flatten, count
md-utils fm get --key tags --recursive docs/ | \
  jq -r '.[]' | \
  sort | \
  uniq -c | \
  sort -rn
```

```bash
# Get all authors, format as list
md-utils fm get --key author --recursive docs/ | \
  cut -d: -f2 | \
  sort -u | \
  sed 's/^/- /'
```

## Multi-Stage Pipelines

### Sequential Processing

```bash
#!/bin/bash
# multi-stage.sh

# Stage 1: Extract frontmatter
md-utils fm dump --recursive docs/ --format json > stage1-raw.json

# Stage 2: Transform data
jq 'map({title: .title, date: .date, category: .category})' \
  stage1-raw.json > stage2-transformed.json

# Stage 3: Group by category
jq 'group_by(.category)' \
  stage2-transformed.json > stage3-grouped.json

# Stage 4: Generate report
jq -r '
  .[] |
  "\(.[0].category):\n" +
  (map("  - \(.title) (\(.date))") | join("\n"))
' stage3-grouped.json > final-report.txt

echo "✓ Pipeline complete: final-report.txt"
```

### Parallel Stages

```bash
#!/bin/bash
# parallel-stages.sh

# Run multiple extractions in parallel
md-utils toc --recursive docs/ --output toc/ &
md-utils convert to-text --recursive docs/ --output plain/ &
md-utils fm dump --recursive docs/ --format json > metadata.json &

# Wait for all to complete
wait

echo "✓ All stages complete"
```

## Data Transformation Patterns

### Filter and Map

```bash
# Filter by condition, map to new format
md-utils fm get --key category --recursive docs/ | \
  grep "api" | \
  cut -d: -f1 | \
  while read -r file; do
    title=$(md-utils fm get --key title "$file")
    echo "$file → $title"
  done
```

### Aggregation

```bash
#!/bin/bash
# aggregate.sh

# Count documents by category
declare -A category_counts

md-utils fm get --key category --recursive docs/ | \
  cut -d: -f2 | \
  while read -r category; do
    ((category_counts[$category]++))
  done

# Output results
for category in "${!category_counts[@]}"; do
  echo "$category: ${category_counts[$category]}"
done | sort -t: -k2 -rn
```

### Join Operations

```bash
# Join data from multiple sources
join -t: \
  <(md-utils fm get --key title --recursive docs/ | sort) \
  <(md-utils fm get --key date --recursive docs/ | sort)
```

## Complex Pipelines

### Extract-Transform-Load (ETL)

```bash
#!/bin/bash
# etl-pipeline.sh

# Extract
echo "=== Extract ==="
md-utils fm dump --recursive docs/ --format json > extract.json

# Transform
echo "=== Transform ==="
jq '
  map({
    id: (.file | split("/")[-1] | split(".")[0]),
    title: .title,
    date: .date,
    category: .category,
    word_count: 0
  })
' extract.json > transform.json

# Enrich with word counts
jq -c '.[]' transform.json | while read -r doc; do
  file=$(echo "$doc" | jq -r '.id').md
  word_count=$(find docs/ -name "$file" -exec md-utils body {} \; | wc -w)

  echo "$doc" | jq --arg wc "$word_count" '.word_count = ($wc | tonumber)'
done | jq -s '.' > enriched.json

# Load
echo "=== Load ==="
# Import to database, API, etc.
curl -X POST -H "Content-Type: application/json" \
  -d @enriched.json \
  http://api.example.com/documents

echo "✓ ETL complete"
```

### Multi-Source Aggregation

```bash
#!/bin/bash
# multi-source.sh

# Combine data from multiple sources
{
  # Source 1: Main docs
  md-utils fm dump --recursive docs/ --format json | \
    jq '.[] | {source: "docs", file, title, date}'

  # Source 2: Blog posts
  md-utils fm dump --recursive blog/ --format json | \
    jq '.[] | {source: "blog", file, title, date}'

  # Source 3: Archive
  md-utils fm dump --recursive archive/ --format json | \
    jq '.[] | {source: "archive", file, title, date}'
} | jq -s 'sort_by(.date) | reverse'
```

### Conditional Branching

```bash
#!/bin/bash
# conditional-pipeline.sh

# Process differently based on metadata
md-utils fm get --key type --recursive docs/ | \
  while IFS=: read -r file type; do
    case "$type" in
      api)
        # API docs pipeline
        md-utils toc "$file" --output api-toc/
        md-utils fm set --key api_version --value "2.0" "$file" --in-place
        ;;
      guide)
        # Guide pipeline
        md-utils convert to-text "$file" --output guides-text/
        md-utils fm set --key reviewed --value "$(date -I)" "$file" --in-place
        ;;
      tutorial)
        # Tutorial pipeline
        md-utils body "$file" > tutorials/$(basename "$file")
        ;;
    esac
  done
```

## Stream Processing

### Real-Time Processing

```bash
#!/bin/bash
# stream-processor.sh

# Watch for new/modified files and process
fswatch -0 docs/ | while read -d "" file; do
  if [[ "$file" == *.md ]]; then
    echo "Processing: $file"

    # Pipeline for changed file
    md-utils fm set --key modified --value "$(date -Iseconds)" "$file" --in-place
    md-utils toc "$file" --output toc/$(basename "$file")

    echo "✓ Processed: $file"
  fi
done
```

### Buffer and Batch

```bash
#!/bin/bash
# batch-stream.sh

batch_size=100
buffer=()

# Process in batches
find docs/ -name "*.md" | while read -r file; do
  buffer+=("$file")

  # Process when batch is full
  if [ ${#buffer[@]} -ge $batch_size ]; then
    echo "Processing batch of ${#buffer[@]} files..."

    # Process batch
    printf '%s\n' "${buffer[@]}" | \
      xargs -P 4 -I {} md-utils toc {} --output toc/{}

    # Clear buffer
    buffer=()
  fi
done

# Process remaining files
if [ ${#buffer[@]} -gt 0 ]; then
  echo "Processing final batch of ${#buffer[@]} files..."
  printf '%s\n' "${buffer[@]}" | \
    xargs -P 4 -I {} md-utils toc {} --output toc/{}
fi
```

## Pipeline Optimization

### Reduce I/O

```bash
# Inefficient: Multiple reads
for file in docs/**/*.md; do
  title=$(md-utils fm get --key title "$file")
  date=$(md-utils fm get --key date "$file")
  author=$(md-utils fm get --key author "$file")
done

# Efficient: Single read, multiple extractions
md-utils fm dump --recursive docs/ --format json | \
  jq -r '.[] | "\(.file)|\(.title)|\(.date)|\(.author)"'
```

### Parallel Processing

```bash
# Sequential (slow)
find docs/ -name "*.md" | while read -r file; do
  md-utils toc "$file" --output toc/$(basename "$file")
done

# Parallel (fast)
find docs/ -name "*.md" | \
  parallel -j 8 md-utils toc {} --output toc/{/}

# Or with xargs
find docs/ -name "*.md" | \
  xargs -P 8 -I {} md-utils toc {} --output toc/{}
```

### Lazy Evaluation

```bash
# Only process what's needed
find docs/ -name "*.md" | \
  head -10 | \
  while read -r file; do
    md-utils toc "$file"
  done

# Process until condition met
find docs/ -name "*.md" | \
  while read -r file; do
    result=$(md-utils fm get --key status "$file" 2>/dev/null)

    if [ "$result" = "complete" ]; then
      break
    fi

    # Process file
    md-utils fm set --key status --value "complete" "$file" --in-place
  done
```

## Error Handling in Pipelines

### Pipeline Failure Modes

```bash
# Default: Pipeline continues on error
cmd1 | cmd2 | cmd3

# Fail on first error (set -e doesn't work with pipes)
set -o pipefail
cmd1 | cmd2 | cmd3 || exit 1

# Capture individual command status
cmd1 | cmd2 | cmd3
status=("${PIPESTATUS[@]}")

for i in "${!status[@]}"; do
  if [ "${status[$i]}" -ne 0 ]; then
    echo "Command $((i+1)) failed with status ${status[$i]}"
  fi
done
```

### Graceful Degradation

```bash
# Continue processing even if some files fail
find docs/ -name "*.md" | while read -r file; do
  if md-utils fm get --key title "$file" >/dev/null 2>&1; then
    # Process successfully
    md-utils toc "$file" --output toc/$(basename "$file")
  else
    # Log error and continue
    echo "Error processing: $file" >> errors.log
  fi
done
```

### Error Recovery

```bash
#!/bin/bash
# pipeline-with-recovery.sh

set -o pipefail

# Stage 1
if ! md-utils fm dump --recursive docs/ > stage1.json; then
  echo "Stage 1 failed, attempting recovery..."

  # Recovery: Process files individually
  find docs/ -name "*.md" | while read -r file; do
    md-utils fm dump "$file" 2>/dev/null
  done | jq -s '.' > stage1.json
fi

# Stage 2
if ! jq '.[] | {title, date}' stage1.json > stage2.json; then
  echo "Stage 2 failed, cannot continue"
  exit 1
fi

echo "✓ Pipeline complete"
```

## Testing Pipelines

### Dry Run Mode

```bash
#!/bin/bash
# pipeline-dry-run.sh

DRY_RUN="${DRY_RUN:-false}"

run_command() {
  if [ "$DRY_RUN" = "true" ]; then
    echo "Would run: $*"
  else
    "$@"
  fi
}

# Use dry run mode
run_command md-utils fm set --key test --value "value" --recursive docs/ --in-place
```

### Test Data

```bash
#!/bin/bash
# test-pipeline.sh

# Create test data
test_dir=$(mktemp -d)
cp docs/sample*.md "$test_dir/"

# Run pipeline on test data
./pipeline.sh "$test_dir" "$test_dir/output"

# Verify results
if diff -r expected/ "$test_dir/output/"; then
  echo "✓ Pipeline test passed"
else
  echo "✗ Pipeline test failed"
  exit 1
fi

# Cleanup
rm -rf "$test_dir"
```

### Pipeline Monitoring

```bash
#!/bin/bash
# monitored-pipeline.sh

# Track progress
total=$(find docs/ -name "*.md" | wc -l)
processed=0

find docs/ -name "*.md" | while read -r file; do
  md-utils toc "$file" --output toc/$(basename "$file")

  ((processed++))

  # Progress indicator
  if [ $((processed % 10)) -eq 0 ]; then
    percent=$((processed * 100 / total))
    echo "Progress: $processed/$total ($percent%)"
  fi
done

echo "✓ Pipeline complete: $processed files processed"
```

## Best Practices

### Pipeline Documentation

```bash
#!/bin/bash
# documented-pipeline.sh

# Pipeline: Extract metadata → Transform → Generate report
#
# Stages:
#   1. Extract frontmatter from all docs
#   2. Filter by category
#   3. Sort by date
#   4. Format as markdown report
#
# Input: docs/ directory
# Output: report.md

md-utils fm dump --recursive docs/ --format json | \  # Stage 1
  jq '.[] | select(.category == "guide")' | \          # Stage 2
  jq -s 'sort_by(.date) | reverse' | \                 # Stage 3
  jq -r '.[] | "- [\(.title)](\(.file)) - \(.date)"'   # Stage 4
```

### Modular Pipelines

```bash
#!/bin/bash
# modular-pipeline.sh

# Break pipeline into reusable functions
extract_metadata() {
  md-utils fm dump --recursive "$1" --format json
}

transform_data() {
  jq 'map({title, date, category})'
}

generate_report() {
  jq -r '.[] | "\(.title) - \(.date)"'
}

# Compose pipeline
extract_metadata docs/ | \
  transform_data | \
  generate_report > report.txt
```

### Version Control

```bash
# Track pipeline versions
git add pipelines/
git commit -m "Update ETL pipeline v2.0"
git tag pipeline-v2.0
```

## See Also

- <doc:ShellIntegration>
- <doc:ErrorHandling>
- <doc:../GeneralMarkdown/BatchProcessing>
