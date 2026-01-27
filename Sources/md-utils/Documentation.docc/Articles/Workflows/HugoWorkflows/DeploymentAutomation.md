# Hugo Deployment Automation

Automate pre-deployment validation and content preparation.

## Overview

Ensure content quality and consistency before deploying your Hugo site with automated checks, validation, and content enhancement.

## Pre-Deployment Checklist

### Complete Validation Script

```bash
#!/bin/bash
# pre-deploy.sh - Run before deployment

errors=0

echo "Pre-Deployment Validation"
echo "========================="
echo ""

# Check required fields
echo "Checking required frontmatter fields..."
required_fields=("title" "date")

for file in content/posts/**/*.md; do
    for field in "${required_fields[@]}"; do
        if ! md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
            echo "  ERROR: $file missing $field"
            ((errors++))
        fi
    done
done

# Check for drafts
echo ""
echo "Checking for drafts..."
draft_count=0

for file in content/posts/**/*.md; do
    if [ "$(md-utils fm get --key draft "$file" 2>/dev/null)" = "true" ]; then
        echo "  WARNING: Draft found: $file"
        ((draft_count++))
    fi
done

echo "  Found $draft_count drafts"

# Validate dates
echo ""
echo "Validating dates..."

for file in content/posts/**/*.md; do
    date=$(md-utils fm get --key date "$file" 2>/dev/null)

    if [ -z "$date" ]; then
        echo "  ERROR: Missing date in $file"
        ((errors++))
    elif ! date -d "$date" >/dev/null 2>&1; then
        echo "  ERROR: Invalid date format in $file: $date"
        ((errors++))
    fi
done

# Check for broken links (basic)
echo ""
echo "Checking internal links..."
# (Implementation depends on your link style)

# Summary
echo ""
echo "Summary"
echo "-------"
echo "Errors: $errors"
echo "Warnings: $draft_count drafts"

if [ $errors -gt 0 ]; then
    echo ""
    echo "FAILED: Fix errors before deploying"
    exit 1
else
    echo ""
    echo "PASSED: Ready for deployment"
    exit 0
fi
```

## Field Validation

### Ensure Required Fields

```bash
#!/bin/bash
# validate-fields.sh

required=("title" "date" "author" "description")

echo "Validating required fields..."
missing_count=0

for file in content/posts/**/*.md; do
    missing_fields=()

    for field in "${required[@]}"; do
        if ! md-utils fm get --key "$field" "$file" >/dev/null 2>&1; then
            missing_fields+=("$field")
        fi
    done

    if [ ${#missing_fields[@]} -gt 0 ]; then
        echo "$file missing: ${missing_fields[*]}"
        ((missing_count++))
    fi
done

if [ $missing_count -eq 0 ]; then
    echo "✓ All files have required fields"
else
    echo "✗ $missing_count files missing required fields"
    exit 1
fi
```

### Validate Field Types

```bash
#!/bin/bash
# validate-types.sh

for file in content/posts/**/*.md; do
    # Check tags is array
    tags=$(md-utils fm get --key tags "$file" --format json 2>/dev/null)

    if [ -n "$tags" ] && ! echo "$tags" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo "ERROR: tags is not array in $file"
    fi

    # Check draft is boolean
    draft=$(md-utils fm get --key draft "$file" 2>/dev/null)

    if [ -n "$draft" ] && [[ ! "$draft" =~ ^(true|false)$ ]]; then
        echo "ERROR: draft is not boolean in $file"
    fi
done
```

## Content Enhancement

### Generate TOC for All Posts

```bash
#!/bin/bash
# add-toc.sh - Add TOC to all posts

for file in content/posts/**/*.md; do
    # Check if TOC already exists
    if ! grep -q "## Table of Contents" "$file"; then
        # Get body
        body=$(md-utils body "$file")

        # Generate TOC
        toc=$(md-utils toc --min-level 2 "$file")

        # Reconstruct file
        {
            md-utils fm dump --format raw --include-delimiters "$file"
            echo ""
            md-utils toc --max-level 1 "$file"
            echo ""
            echo "## Table of Contents"
            echo ""
            echo "$toc"
            echo ""
            echo "$body" | tail -n +2  # Skip h1
        } > "${file}.tmp"

        mv "${file}.tmp" "$file"

        echo "Added TOC to: $file"
    fi
done
```

### Update Metadata

```bash
#!/bin/bash
# update-deployment-metadata.sh

deployment_date=$(date -I)

for file in content/**/*.md; do
    # Update lastmod
    md-utils fm set --key lastmod --value "$deployment_date" "$file" -i

    # Add build info
    md-utils fm set --key lastBuild --value "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$file" -i

    # Add git commit if available
    if git rev-parse HEAD >/dev/null 2>&1; then
        commit=$(git rev-parse --short HEAD)
        md-utils fm set --key gitCommit --value "$commit" "$file" -i
    fi
done
```

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/deploy.yml
name: Deploy Hugo Site

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Hugo
        uses: peaceiris/actions-hugo@v2
        with:
          hugo-version: 'latest'

      - name: Install md-utils
        run: |
          # Install md-utils (adjust for your installation method)
          brew install md-utils

      - name: Pre-deployment validation
        run: |
          chmod +x ./scripts/pre-deploy.sh
          ./scripts/pre-deploy.sh

      - name: Update metadata
        run: |
          # Update lastmod for changed files
          git diff --name-only ${{ github.event.before }} | grep '\.md$' | \\
            xargs -I {} md-utils fm set --key lastmod --value "$(date -I)" {} -i

      - name: Build
        run: hugo --minify

      - name: Deploy
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./public
```

### GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - build
  - deploy

validate:
  stage: validate
  script:
    - ./scripts/pre-deploy.sh

build:
  stage: build
  script:
    - hugo --minify
  artifacts:
    paths:
      - public

deploy:
  stage: deploy
  script:
    - ./scripts/deploy.sh
  only:
    - main
```

## Automated Reports

### Deployment Summary

```bash
#!/bin/bash
# deployment-summary.sh

echo "Deployment Summary"
echo "=================="
echo ""
echo "Generated: $(date)"
echo ""

# Count posts
total_posts=$(find content/posts -name "*.md" | wc -l)
echo "Total posts: $total_posts"

# Count drafts
draft_count=$(for file in content/posts/**/*.md; do
    [ "$(md-utils fm get --key draft "$file" 2>/dev/null)" = "true" ] && echo 1
done | wc -l)

echo "Published: $((total_posts - draft_count))"
echo "Drafts: $draft_count"

# Recent posts
echo ""
echo "Recently updated:"
md-utils -r fm get --key lastmod content/posts/ | \\
    sort -t: -k2 -r | head -5

# Tag summary
echo ""
echo "Top tags:"
md-utils -r fm get --key tags content/posts/ --format json | \\
    jq -r '.[]' | sort | uniq -c | sort -rn | head -10
```

### Quality Report

```bash
#!/bin/bash
# quality-report.sh

echo "Content Quality Report"
echo "====================="
echo ""

# Check for missing descriptions
echo "Posts without descriptions:"
for file in content/posts/**/*.md; do
    if ! md-utils fm get --key description "$file" >/dev/null 2>&1; then
        echo "  - $file"
    fi
done

# Check for short content
echo ""
echo "Posts with low word count (<300):"
for file in content/posts/**/*.md; do
    count=$(md-utils body --format plain-text "$file" | wc -w)

    if [ "$count" -lt 300 ]; then
        title=$(md-utils fm get --key title "$file")
        echo "  - $title: $count words"
    fi
done
```

## See Also

- <doc:BulkUpdates>
- <doc:CreatingPosts>
- <doc:HugoWorkflows>
- <doc:../Scripting/ErrorHandling>
