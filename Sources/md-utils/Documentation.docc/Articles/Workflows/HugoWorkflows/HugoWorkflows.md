# Hugo Static Site Workflows

Automate Hugo site management with md-utils.

## Overview

md-utils provides powerful automation capabilities for Hugo static sites. This guide covers common workflows for creating posts, managing taxonomy, bulk updates, and deployment automation.

## Hugo Frontmatter Structure

Hugo uses YAML frontmatter for page metadata:

```yaml
---
title: "Post Title"
date: 2024-01-24T10:00:00Z
draft: false
tags: [tag1, tag2]
categories: [category1]
author: "Author Name"
description: "Post description"
---
```

## Common Hugo Fields

| Field | Type | Purpose |
|-------|------|---------|
| `title` | string | Page title |
| `date` | datetime | Publication date |
| `draft` | boolean | Draft status |
| `tags` | array | Content tags |
| `categories` | array | Content categories |
| `author` | string | Author name |
| `description` | string | Meta description |
| `weight` | number | Page ordering |
| `publishDate` | datetime | Scheduled publication |

## Directory Structure

Typical Hugo content directory:

```
content/
├── posts/
│   ├── 2024/
│   │   ├── post-1.md
│   │   └── post-2.md
│   └── 2023/
│       └── old-post.md
├── pages/
│   ├── about.md
│   └── contact.md
└── _index.md
```

## Workflow Topics

### Creating Posts

- <doc:CreatingPosts> - Templates and automated post creation

### Managing Taxonomies

- <doc:ManagingTaxonomies> - Working with tags and categories

### Bulk Updates

- <doc:BulkUpdates> - Mass updates to frontmatter

### Deployment

- <doc:DeploymentAutomation> - Pre-deployment checks and automation

## Quick Examples

### Create New Post

```bash
#!/bin/bash
# Create new Hugo post

title="$1"
slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
file="content/posts/$(date +%Y)/${slug}.md"

mkdir -p "$(dirname "$file")"

cat > "$file" << EOF
---
title: "$title"
date: $(date -I)T$(date +%H:%M:%S)Z
draft: true
tags: []
categories: []
---

# $title

Write your content here.
EOF

md-utils fm dump --format yaml "$file"
```

### Publish All Drafts

```bash
# Set draft=false for all posts
md-utils -r fm set --key draft --value "false" content/posts/ -i
```

### Update Dates

```bash
# Update modified timestamp
md-utils -r fm set --key lastmod --value "$(date -I)" content/ -i
```

### List All Tags

```bash
# Get unique tags across site
md-utils -r fm get --key tags content/ --format json | \\
    jq -r '.[]' | sort | uniq
```

## Integration with Hugo Commands

### Combine with Hugo CLI

```bash
# Create post with hugo, then enhance with md-utils
hugo new posts/my-post.md

# Add additional metadata
md-utils fm set --key author --value "Jane Doe" content/posts/my-post.md -i
md-utils fm set --key tags --value '["hugo", "tutorial"]' content/posts/my-post.md -i

# Generate TOC
md-utils toc content/posts/my-post.md >> content/posts/my-post.md
```

### Build Pipeline

```bash
#!/bin/bash
# Pre-build validation and enhancement

echo "Pre-build checks..."

# Ensure all posts have required fields
for file in content/posts/**/*.md; do
    if ! md-utils fm get --key title "$file" >/dev/null 2>&1; then
        echo "Missing title: $file"
        exit 1
    fi
done

# Update lastmod on changed files
git diff --name-only HEAD | grep '\.md$' | \\
    xargs -I {} md-utils fm set --key lastmod --value "$(date -I)" {} -i

# Build site
hugo

echo "Build complete!"
```

## See Also

- <doc:CreatingPosts>
- <doc:ManagingTaxonomies>
- <doc:BulkUpdates>
- <doc:DeploymentAutomation>
- [Hugo Documentation](https://gohugo.io/documentation/)
