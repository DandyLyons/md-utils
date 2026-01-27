# Batch Processing

Efficiently process large collections of Markdown files with md-utils.

## Overview

Batch processing allows you to perform operations on hundreds or thousands of Markdown files efficiently. md-utils is designed for high-performance batch operations with built-in recursive directory scanning, filtering, and parallel processing capabilities.

## Basic Patterns

### Recursive Processing

```bash
# Process all files recursively
md-utils fm set --key processed --value "true" \
  --recursive docs/ \
  --in-place

# Process with custom extensions
md-utils fm get --key title \
  --recursive docs/ \
  --extensions md,markdown,mdown

# Include hidden files
md-utils toc --recursive docs/ --include-hidden
```

### File Filtering

```bash
# Process only modified files
find docs/ -name "*.md" -mtime -7 -exec \
  md-utils fm set --key updated --value "$(date -I)" {} --in-place \;

# Process files matching pattern
find docs/ -name "*-guide.md" | \
  xargs md-utils fm set --key type --value "guide" --in-place

# Exclude specific directories
find docs/ -name "*.md" \
  ! -path "*/drafts/*" \
  ! -path "*/archive/*" \
  ! -path "*/.git/*"
```

### Output Organization

```bash
# One output file per input
md-utils convert to-text \
  --recursive docs/ \
  --output output/

# Preserve directory structure
md-utils toc --recursive docs/ --output toc/

# Custom output naming
find docs/ -name "*.md" | while read -r file; do
  basename="${file%.md}"
  md-utils body "$file" > "${basename}-body.txt"
done
```

## Parallel Processing

### GNU Parallel

```bash
# Install: brew install parallel

# Process files in parallel
find docs/ -name "*.md" | \
  parallel md-utils fm set --key processed --value "true" {} --in-place

# Limit concurrent jobs
find docs/ -name "*.md" | \
  parallel -j 4 md-utils toc {} --output toc/{/.}.md

# Show progress
find docs/ -name "*.md" | \
  parallel --progress md-utils convert to-text {} --output plain/{/.}.txt
```

### xargs Parallel

```bash
# Process with xargs (macOS/Linux)
find docs/ -name "*.md" -print0 | \
  xargs -0 -P 8 -I {} md-utils fm set --key batch --value "true" {} --in-place

# With error handling
find docs/ -name "*.md" | \
  xargs -P 4 -I {} sh -c 'md-utils toc "$1" > /dev/null 2>&1 || echo "Error: $1"' _ {}
```

### Background Jobs

```bash
#!/bin/bash
# batch-parallel.sh

max_jobs=8
job_count=0

find docs/ -name "*.md" | while read -r file; do
  # Process in background
  md-utils fm set --key processed --value "true" "$file" --in-place &

  ((job_count++))

  # Wait when max jobs reached
  if [ $job_count -ge $max_jobs ]; then
    wait -n  # Wait for any job to complete
    ((job_count--))
  fi
done

# Wait for remaining jobs
wait
echo "✓ Batch processing complete"
```

## Large-Scale Operations

### Processing Thousands of Files

```bash
#!/bin/bash
# mass-update.sh

docs_dir="$1"
total=$(find "$docs_dir" -name "*.md" | wc -l)
processed=0

echo "Processing $total files..."

find "$docs_dir" -name "*.md" | while read -r file; do
  md-utils fm set --key last_batch --value "$(date -I)" "$file" --in-place

  ((processed++))

  # Progress indicator
  if [ $((processed % 100)) -eq 0 ]; then
    percent=$((processed * 100 / total))
    echo "Progress: $processed/$total ($percent%)"
  fi
done

echo "✓ Complete: $processed files processed"
```

### Chunked Processing

```bash
#!/bin/bash
# chunked-batch.sh - Process in chunks to avoid memory issues

chunk_size=100

find docs/ -name "*.md" | split -l "$chunk_size" - chunk-

for chunk in chunk-*; do
  echo "Processing chunk: $chunk"

  while read -r file; do
    md-utils fm set --key chunk --value "$chunk" "$file" --in-place
  done < "$chunk"

  rm "$chunk"
done

echo "✓ All chunks processed"
```

### Streaming Processing

```bash
# Process files as they're found (memory efficient)
find docs/ -name "*.md" -print0 | while IFS= read -r -d '' file; do
  # Process immediately without storing in memory
  md-utils fm set --key streamed --value "true" "$file" --in-place
done
```

## Bulk Metadata Operations

### Mass Field Update

```bash
#!/bin/bash
# bulk-update-field.sh

field="$1"
value="$2"
directory="$3"

echo "Updating $field=$value in $directory"

count=0

find "$directory" -name "*.md" | while read -r file; do
  md-utils fm set --key "$field" --value "$value" "$file" --in-place
  ((count++))
done

echo "✓ Updated $count files"
```

### Conditional Updates

```bash
#!/bin/bash
# conditional-batch-update.sh

# Update field only if condition is met
find docs/ -name "*.md" | while read -r file; do
  category=$(md-utils fm get --key category "$file" 2>/dev/null)

  if [ "$category" = "api" ]; then
    md-utils fm set --key api_version --value "2.0" \
      --key updated --value "$(date -I)" \
      "$file" --in-place

    echo "Updated: $file"
  fi
done
```

### Multi-Field Updates

```bash
# Update multiple fields in one pass
update_multiple_fields() {
  local file="$1"

  md-utils fm set --key processed --value "true" \
    --key batch_id --value "$(date +%s)" \
    --key processor --value "md-utils" \
    "$file" --in-place
}

export -f update_multiple_fields

find docs/ -name "*.md" | parallel update_multiple_fields {}
```

## Data Extraction

### Extract to CSV

```bash
#!/bin/bash
# extract-to-csv.sh

output="docs-export.csv"

# Header
echo "file,title,author,date,category" > "$output"

# Data
find docs/ -name "*.md" | while read -r file; do
  title=$(md-utils fm get --key title "$file" 2>/dev/null | sed 's/,/;/g')
  author=$(md-utils fm get --key author "$file" 2>/dev/null | sed 's/,/;/g')
  date=$(md-utils fm get --key date "$file" 2>/dev/null)
  category=$(md-utils fm get --key category "$file" 2>/dev/null)

  echo "$file,$title,$author,$date,$category" >> "$output"
done

echo "✓ Exported to: $output"
```

### Extract to JSON

```bash
#!/bin/bash
# extract-to-json.sh

output="docs-export.json"

echo "[" > "$output"

find docs/ -name "*.md" | while read -r file; do
  # Get all frontmatter as JSON
  fm_json=$(md-utils fm dump "$file" --format json 2>/dev/null || echo "{}")

  # Add file path
  jq --arg path "$file" '. + {file: $path}' <<< "$fm_json" >> "$output"

  echo "," >> "$output"
done

# Remove trailing comma and close array
sed -i '' '$d' "$output"
echo "" >> "$output"
echo "]" >> "$output"

echo "✓ Exported to: $output"
```

### Aggregate Statistics

```bash
#!/bin/bash
# aggregate-stats.sh

echo "=== Documentation Statistics ==="

# Total files
total=$(find docs/ -name "*.md" | wc -l)
echo "Total files: $total"

# By category
echo -e "\n### By Category"
md-utils fm get --key category --recursive docs/ | \
  cut -d: -f2 | sort | uniq -c | sort -rn

# By author
echo -e "\n### By Author"
md-utils fm get --key author --recursive docs/ | \
  cut -d: -f2 | sort | uniq -c | sort -rn

# By date (year)
echo -e "\n### By Year"
md-utils fm get --key date --recursive docs/ | \
  cut -d: -f2 | cut -d- -f1 | sort | uniq -c | sort -rn
```

## Transformation Pipelines

### Multi-Stage Processing

```bash
#!/bin/bash
# pipeline.sh

docs_dir="$1"
output_dir="$2"

echo "Stage 1: Update metadata"
md-utils fm set --key pipeline_version --value "1.0" \
  --recursive "$docs_dir" --in-place

echo "Stage 2: Generate TOCs"
md-utils toc --recursive "$docs_dir" --output "$output_dir/toc/"

echo "Stage 3: Convert to plain text"
md-utils convert to-text --recursive "$docs_dir" --output "$output_dir/plain/"

echo "Stage 4: Extract frontmatter"
./extract-to-json.sh "$docs_dir" > "$output_dir/metadata.json"

echo "✓ Pipeline complete"
```

### Error Recovery

```bash
#!/bin/bash
# batch-with-recovery.sh

error_log="batch-errors.log"
success_count=0
error_count=0

find docs/ -name "*.md" | while read -r file; do
  if md-utils fm set --key processed --value "true" "$file" --in-place 2>/dev/null; then
    ((success_count++))
  else
    echo "ERROR: $file" | tee -a "$error_log"
    ((error_count++))
  fi
done

echo "✓ Batch complete: $success_count success, $error_count errors"

if [ $error_count -gt 0 ]; then
  echo "Errors logged to: $error_log"
fi
```

### Rollback Support

```bash
#!/bin/bash
# batch-with-rollback.sh

backup_dir="backups/batch-$(date +%s)"

# Create backup
echo "Creating backup..."
mkdir -p "$backup_dir"
find docs/ -name "*.md" -exec cp --parents {} "$backup_dir" \;

# Perform batch operation
if md-utils fm set --key version --value "2.0" --recursive docs/ --in-place; then
  echo "✓ Batch operation successful"
  read -p "Keep changes? (y/n) " -n 1 -r
  echo

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Rolling back..."
    cp -r "$backup_dir"/docs/* docs/
    echo "✓ Rollback complete"
  fi
else
  echo "✗ Batch operation failed, rolling back..."
  cp -r "$backup_dir"/docs/* docs/
  echo "✓ Rollback complete"
fi
```

## Performance Optimization

### Batch vs. Individual

```bash
# Slow: Process files individually
for file in docs/**/*.md; do
  md-utils fm set --key processed --value "true" "$file" --in-place
done

# Fast: Use recursive mode
md-utils fm set --key processed --value "true" --recursive docs/ --in-place
```

### Minimize File I/O

```bash
# Inefficient: Multiple passes
md-utils fm set --key field1 --value "value1" --recursive docs/ --in-place
md-utils fm set --key field2 --value "value2" --recursive docs/ --in-place
md-utils fm set --key field3 --value "value3" --recursive docs/ --in-place

# Efficient: Single pass (if tool supports it)
find docs/ -name "*.md" | while read -r file; do
  md-utils fm set --key field1 --value "value1" \
    --key field2 --value "value2" \
    --key field3 --value "value3" \
    "$file" --in-place
done
```

### Progress Monitoring

```bash
#!/bin/bash
# batch-with-progress.sh

total=$(find docs/ -name "*.md" | wc -l)
processed=0
start_time=$(date +%s)

find docs/ -name "*.md" | while read -r file; do
  md-utils fm set --key processed --value "true" "$file" --in-place

  ((processed++))

  # Update progress every 10 files
  if [ $((processed % 10)) -eq 0 ]; then
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    rate=$((processed / elapsed))
    remaining=$((total - processed))
    eta=$((remaining / rate))

    echo "Progress: $processed/$total ($((processed * 100 / total))%) - ETA: ${eta}s"
  fi
done
```

## Best Practices

### Always Test First

```bash
# Test on small subset
test_dir="docs/test"
md-utils fm set --key test --value "value" --recursive "$test_dir" --in-place

# Verify
md-utils fm get --key test --recursive "$test_dir"

# If successful, apply to all
md-utils fm set --key test --value "value" --recursive docs/ --in-place
```

### Use Dry Run

```bash
# Dry run: show what would happen without making changes
find docs/ -name "*.md" | while read -r file; do
  echo "Would update: $file"
  # md-utils fm set --key field --value "value" "$file" --in-place
done
```

### Backup Before Batch Operations

```bash
# Always backup
tar -czf "docs-backup-$(date +%s).tar.gz" docs/

# Run batch operation
md-utils fm set --key version --value "2.0" --recursive docs/ --in-place
```

## See Also

- <doc:DocumentationMaint>
- <doc:QualityControl>
- <doc:../Scripting/PipelinePatterns>
