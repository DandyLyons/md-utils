# Error Handling

Build robust scripts with comprehensive error handling.

## Overview

Proper error handling is essential for production scripts. This guide covers error detection, recovery strategies, logging, and best practices for building reliable automation with md-utils.

## Exit Codes

### Understanding Exit Codes

md-utils uses standard exit codes:

- `0`: Success
- `1`: General error
- `2`: Invalid arguments
- `3`: File not found
- `4`: Parse error

### Checking Exit Codes

```bash
# Basic check
md-utils fm get --key title post.md
if [ $? -ne 0 ]; then
  echo "Error: Failed to get title"
  exit 1
fi

# Inline check
if ! md-utils fm get --key title post.md; then
  echo "Error: Failed to get title"
  exit 1
fi

# Capture output and status
output=$(md-utils fm get --key title post.md 2>&1)
status=$?

if [ $status -ne 0 ]; then
  echo "Error: $output"
  exit $status
fi
```

## Error Detection

### File Validation

```bash
#!/bin/bash
# validate-input.sh

file="$1"

# Check file provided
if [ -z "$file" ]; then
  echo "Error: No file specified" >&2
  echo "Usage: $0 <file>" >&2
  exit 2
fi

# Check file exists
if [ ! -f "$file" ]; then
  echo "Error: File not found: $file" >&2
  exit 3
fi

# Check file is readable
if [ ! -r "$file" ]; then
  echo "Error: File not readable: $file" >&2
  exit 1
fi

# Check file is markdown
if [[ ! "$file" =~ \.md$ ]]; then
  echo "Error: Not a markdown file: $file" >&2
  exit 2
fi

# File is valid
echo "Processing: $file"
md-utils fm get --key title "$file"
```

### Command Availability

```bash
#!/bin/bash
# check-dependencies.sh

# Check if md-utils is available
if ! command -v md-utils &> /dev/null; then
  echo "Error: md-utils not found" >&2
  echo "Install from: https://github.com/user/md-utils" >&2
  exit 1
fi

# Check version
version=$(md-utils --version 2>/dev/null | head -1)
if [ -z "$version" ]; then
  echo "Error: Could not determine md-utils version" >&2
  exit 1
fi

echo "Using md-utils: $version"
```

### Metadata Validation

```bash
#!/bin/bash
# validate-metadata.sh

file="$1"

# Required fields
required_fields="title date author"

errors=()

for field in $required_fields; do
  if ! md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
    errors+=("Missing required field: $field")
  fi
done

if [ ${#errors[@]} -gt 0 ]; then
  echo "Validation failed for: $file" >&2
  printf '  %s\n' "${errors[@]}" >&2
  exit 1
fi

echo "✓ Validation passed: $file"
```

## Error Recovery

### Retry Logic

```bash
#!/bin/bash
# retry.sh

retry() {
  local max_attempts="$1"
  shift
  local cmd=("$@")
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    echo "Attempt $attempt/$max_attempts: ${cmd[*]}"

    if "${cmd[@]}"; then
      echo "✓ Success"
      return 0
    fi

    if [ $attempt -lt $max_attempts ]; then
      sleep $((attempt * 2))  # Exponential backoff
    fi

    ((attempt++))
  done

  echo "✗ Failed after $max_attempts attempts" >&2
  return 1
}

# Usage
retry 3 md-utils fm set --key field --value "value" post.md --in-place
```

### Fallback Operations

```bash
#!/bin/bash
# fallback.sh

file="$1"

# Try primary operation
if md-utils fm get --key title "$file" > /dev/null 2>&1; then
  title=$(md-utils fm get --key title "$file")
  echo "Title: $title"
else
  # Fallback: Extract from first heading
  echo "Warning: No frontmatter title, using first heading" >&2
  title=$(grep -m 1 '^# ' "$file" | sed 's/^# //')

  if [ -n "$title" ]; then
    echo "Title: $title"

    # Update frontmatter with extracted title
    md-utils fm set --key title --value "$title" "$file" --in-place
  else
    echo "Error: No title found" >&2
    exit 1
  fi
fi
```

### Graceful Degradation

```bash
#!/bin/bash
# graceful-degradation.sh

# Try to process all files, continue on errors
errors=0
successes=0

find docs/ -name "*.md" | while read -r file; do
  if md-utils toc "$file" --output toc/$(basename "$file") 2>/dev/null; then
    ((successes++))
  else
    echo "Warning: Failed to process: $file" >&2
    echo "$file" >> failed-files.log
    ((errors++))
  fi
done

echo "Processed: $successes success, $errors errors"

if [ $errors -gt 0 ]; then
  echo "Errors logged to: failed-files.log"
  exit 1
fi
```

## Error Reporting

### Logging

```bash
#!/bin/bash
# logging.sh

LOG_FILE="script.log"
LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # Log levels
  declare -A levels=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)
  local current_level=${levels[$LOG_LEVEL]}
  local msg_level=${levels[$level]}

  if [ $msg_level -ge $current_level ]; then
    echo "[$timestamp] $level: $message" | tee -a "$LOG_FILE"
  fi

  # Exit on error
  if [ "$level" = "ERROR" ]; then
    exit 1
  fi
}

# Usage
log INFO "Starting processing"
log DEBUG "Processing file: $file"

if ! md-utils fm get --key title "$file" >/dev/null 2>&1; then
  log ERROR "Failed to get title from: $file"
fi

log INFO "Processing complete"
```

### Error Messages

```bash
#!/bin/bash
# error-messages.sh

# Descriptive error messages
error() {
  local msg="$1"
  local code="${2:-1}"

  echo "Error: $msg" >&2

  # Show context
  echo "File: ${file:-unknown}" >&2
  echo "Line: ${LINENO}" >&2
  echo "Command: ${BASH_COMMAND}" >&2

  exit "$code"
}

# Usage
if [ ! -f "$file" ]; then
  error "File not found: $file" 3
fi

if ! md-utils fm get --key title "$file" >/dev/null 2>&1; then
  error "Missing title in $file" 4
fi
```

### Stack Traces

```bash
#!/bin/bash
# stack-trace.sh

# Enable error tracing
set -o errtrace

# Error handler with stack trace
error_handler() {
  local exit_code=$?
  local line_no=$1

  echo "Error occurred in script: ${BASH_SOURCE[0]}" >&2
  echo "Line number: $line_no" >&2
  echo "Exit code: $exit_code" >&2
  echo "" >&2
  echo "Stack trace:" >&2

  local frame=0
  while caller $frame; do
    ((frame++))
  done | while read -r line func file; do
    echo "  at $func ($file:$line)" >&2
  done

  exit $exit_code
}

# Register handler
trap 'error_handler ${LINENO}' ERR

# Script code here
md-utils fm get --key nonexistent-field post.md
```

## Defensive Programming

### Input Validation

```bash
#!/bin/bash
# input-validation.sh

validate_file() {
  local file="$1"

  # Check arguments
  if [ $# -ne 1 ]; then
    echo "Error: validate_file requires exactly 1 argument" >&2
    return 1
  fi

  # Check null/empty
  if [ -z "$file" ]; then
    echo "Error: File path is empty" >&2
    return 1
  fi

  # Check path injection
  if [[ "$file" =~ \.\./|^/ ]]; then
    echo "Error: Invalid file path: $file" >&2
    return 1
  fi

  # Check file type
  if [[ ! "$file" =~ \.md$ ]]; then
    echo "Error: Not a markdown file: $file" >&2
    return 1
  fi

  return 0
}

# Usage
if validate_file "$1"; then
  md-utils fm get --key title "$1"
else
  exit 1
fi
```

### Safe Defaults

```bash
#!/bin/bash
# safe-defaults.sh

# Use safe defaults
: "${DOCS_DIR:=docs}"
: "${OUTPUT_DIR:=output}"
: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"

# Validate defaults
if [ ! -d "$DOCS_DIR" ]; then
  echo "Error: DOCS_DIR does not exist: $DOCS_DIR" >&2
  exit 1
fi

# Create output directory safely
mkdir -p "$OUTPUT_DIR" || {
  echo "Error: Failed to create OUTPUT_DIR: $OUTPUT_DIR" >&2
  exit 1
}
```

### Atomic Operations

```bash
#!/bin/bash
# atomic-operations.sh

# Atomic file update
update_file_atomic() {
  local file="$1"
  local key="$2"
  local value="$3"

  # Create temporary file
  local tmp_file="${file}.tmp.$$"

  # Update temporary file
  if ! md-utils fm set --key "$key" --value "$value" "$file" > "$tmp_file"; then
    rm -f "$tmp_file"
    echo "Error: Failed to update $file" >&2
    return 1
  fi

  # Atomic rename
  if ! mv "$tmp_file" "$file"; then
    rm -f "$tmp_file"
    echo "Error: Failed to save $file" >&2
    return 1
  fi

  return 0
}

# Usage
update_file_atomic "post.md" "title" "New Title"
```

## Error Prevention

### Set Strict Mode

```bash
#!/bin/bash

# Strict error handling
set -euo pipefail

# -e: Exit on error
# -u: Error on undefined variable
# -o pipefail: Fail on pipe errors

# Also consider:
# set -x  # Debug mode (print commands)
# set -n  # Syntax check only (don't execute)
```

### Trap Errors

```bash
#!/bin/bash
# trap-errors.sh

cleanup() {
  local exit_code=$?

  # Cleanup temporary files
  rm -f /tmp/md-utils-*.tmp

  # Log completion
  if [ $exit_code -eq 0 ]; then
    echo "✓ Script completed successfully"
  else
    echo "✗ Script failed with exit code: $exit_code" >&2
  fi

  exit $exit_code
}

# Register cleanup on exit
trap cleanup EXIT

# Register error handler
trap 'echo "Error on line $LINENO" >&2' ERR

# Script code
md-utils fm get --key title post.md
```

### Pre-Flight Checks

```bash
#!/bin/bash
# pre-flight.sh

pre_flight_checks() {
  local errors=0

  # Check dependencies
  for cmd in md-utils jq find; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "Error: Required command not found: $cmd" >&2
      ((errors++))
    fi
  done

  # Check directories
  for dir in docs output; do
    if [ ! -d "$dir" ]; then
      echo "Error: Required directory not found: $dir" >&2
      ((errors++))
    fi
  done

  # Check permissions
  if [ ! -w "output" ]; then
    echo "Error: Output directory not writable: output" >&2
    ((errors++))
  fi

  # Check disk space
  available=$(df -P output | awk 'NR==2 {print $4}')
  required=1000000  # 1GB in KB

  if [ "$available" -lt "$required" ]; then
    echo "Error: Insufficient disk space" >&2
    ((errors++))
  fi

  if [ $errors -gt 0 ]; then
    echo "Pre-flight checks failed: $errors errors" >&2
    return 1
  fi

  echo "✓ Pre-flight checks passed"
  return 0
}

# Run checks before processing
if ! pre_flight_checks; then
  exit 1
fi

# Continue with script
echo "Starting processing..."
```

## Testing Error Handling

### Unit Tests

```bash
#!/bin/bash
# test-error-handling.sh

test_missing_file() {
  if ./script.sh nonexistent.md 2>/dev/null; then
    echo "✗ Should fail on missing file"
    return 1
  else
    echo "✓ Correctly handles missing file"
    return 0
  fi
}

test_invalid_metadata() {
  # Create test file without required field
  echo "# Test" > test.md

  if ./script.sh test.md 2>/dev/null; then
    echo "✗ Should fail on invalid metadata"
    rm test.md
    return 1
  else
    echo "✓ Correctly validates metadata"
    rm test.md
    return 0
  fi
}

# Run tests
tests=(test_missing_file test_invalid_metadata)
passed=0
failed=0

for test in "${tests[@]}"; do
  if $test; then
    ((passed++))
  else
    ((failed++))
  fi
done

echo ""
echo "Results: $passed passed, $failed failed"

[ $failed -eq 0 ]
```

### Integration Tests

```bash
#!/bin/bash
# integration-test.sh

# Setup
test_dir=$(mktemp -d)
trap "rm -rf $test_dir" EXIT

# Create test files
echo "---\ntitle: Test\n---\n# Test" > "$test_dir/test.md"

# Test successful operation
if ./pipeline.sh "$test_dir" "$test_dir/output"; then
  echo "✓ Pipeline succeeded on valid input"
else
  echo "✗ Pipeline failed on valid input"
  exit 1
fi

# Test error handling
if ./pipeline.sh /nonexistent /output 2>/dev/null; then
  echo "✗ Pipeline should fail on invalid input"
  exit 1
else
  echo "✓ Pipeline correctly handles invalid input"
fi

echo "✓ All integration tests passed"
```

## Best Practices

### Fail Fast

```bash
#!/bin/bash
set -e

# Fail immediately on error
md-utils fm get --key title post.md || exit 1

# Continue processing
md-utils toc post.md
```

### Provide Context

```bash
# Bad
echo "Error" >&2

# Good
echo "Error: Failed to process $file (missing title)" >&2
echo "  File: $file" >&2
echo "  Expected: frontmatter with title field" >&2
```

### Document Error Codes

```bash
#!/bin/bash
# documented-errors.sh

# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Invalid arguments
#   3 - File not found
#   4 - Missing metadata
#   5 - Permission denied

case "$error_type" in
  file_not_found)
    exit 3
    ;;
  missing_metadata)
    exit 4
    ;;
  permission_denied)
    exit 5
    ;;
  *)
    exit 1
    ;;
esac
```

### Monitor Production Scripts

```bash
#!/bin/bash
# monitored-script.sh

# Send metrics/alerts
report_error() {
  local error_msg="$1"

  # Log locally
  echo "Error: $error_msg" | tee -a errors.log

  # Send alert (email, Slack, etc.)
  if command -v mail &> /dev/null; then
    echo "$error_msg" | mail -s "Script Error" admin@example.com
  fi
}

# Usage
if ! md-utils fm set --key field --value "value" --recursive docs/ --in-place; then
  report_error "Failed to update frontmatter in docs/"
  exit 1
fi
```

## See Also

- <doc:ShellIntegration>
- <doc:PipelinePatterns>
- <doc:../GeneralMarkdown/QualityControl>
