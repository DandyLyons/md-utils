# Creating Hugo Posts

Automate Hugo post creation with templates and md-utils.

## Overview

Streamline your Hugo content creation workflow with automated post generation, template processing, and frontmatter management.

## Basic Post Creation

### Simple Post Template

```bash
#!/bin/bash
# new-post.sh

title="$1"
slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
file="content/posts/$(date +%Y/${slug}.md"

mkdir -p "$(dirname "$file")"

cat > "$file" << EOF
---
title: "$title"
date: $(date -I)T$(date +%H:%M:%S)Z
draft: true
tags: []
categories: []
author: "Your Name"
description: ""
---

# $title

Write your content here.
EOF

echo "Created: $file"
md-utils fm dump --format yaml "$file"
```

Usage:
```bash
./new-post.sh "My New Blog Post"
```

### With Category

```bash
#!/bin/bash
# new-post-with-category.sh

category="$1"
title="$2"
slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
file="content/posts/${category}/${slug}.md"

mkdir -p "$(dirname "$file")"

cat > "$file" << EOF
---
title: "$title"
date: $(date -I)T10:00:00Z
draft: true
categories: ["$category"]
tags: []
---

# $title
EOF

md-utils fm set --key author --value "$(git config user.name)" "$file" -i
echo "Created: $file"
```

## Template System

### Reusable Templates

Create template files:

```bash
# templates/post.md
---
title: "TITLE_PLACEHOLDER"
date: DATE_PLACEHOLDER
draft: true
tags: TAGS_PLACEHOLDER
categories: CATEGORIES_PLACEHOLDER
author: "AUTHOR_PLACEHOLDER"
---

# TITLE_PLACEHOLDER

Introduction paragraph here.

## Overview

Main content.

## Conclusion

Wrap up.
```

### Template Processor

```bash
#!/bin/bash
# create-from-template.sh

template="$1"
title="$2"
output="$3"

# Copy template
cp "$template" "$output"

# Replace placeholders
md-utils fm set --key title --value "$title" "$output" -i
md-utils fm set --key date --value "$(date -I)T10:00:00Z" "$output" -i
md-utils fm set --key author --value "$(git config user.name)" "$output" -i

# Replace in body
sed -i '' "s/TITLE_PLACEHOLDER/$title/g" "$output"

echo "Created from template: $output"
```

## Interactive Post Creation

### Guided Creation

```bash
#!/bin/bash
# interactive-post.sh

echo "Create New Hugo Post"
echo "===================="
echo ""

# Collect information
read -p "Title: " title
read -p "Category: " category
read -p "Tags (comma-separated): " tags_input
read -p "Description: " description

# Process tags
IFS=',' read -ra tags_array <<< "$tags_input"
tags_json=$(printf '%s\n' "${tags_array[@]}" | jq -R . | jq -s .)

# Create file
slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
file="content/posts/${category}/${slug}.md"
mkdir -p "$(dirname "$file")"

# Create with frontmatter only
cat > "$file" << EOF
---
title: "$title"
date: $(date -I)T$(date +%H:%M:%S)Z
draft: true
categories: ["$category"]
tags: []
author: "$(git config user.name)"
description: "$description"
---

# $title

Start writing here.
EOF

# Set tags using md-utils
md-utils fm set --key tags --value "$tags_json" "$file" -i

# Generate TOC placeholder
echo "" >> "$file"
echo "## Table of Contents" >> "$file"
echo "(Will be generated)" >> "$file"

echo ""
echo "Created: $file"
echo ""
md-utils fm dump --format yaml "$file"

# Open in editor
${EDITOR:-vim} "$file"
```

## Advanced Features

### Series Management

Create posts in a series:

```bash
#!/bin/bash
# new-series-post.sh

series="$1"
part="$2"
title="$3"

file="content/posts/series/${series}/part-${part}.md"
mkdir -p "$(dirname "$file")"

cat > "$file" << EOF
---
title: "$title"
date: $(date -I)T10:00:00Z
draft: true
series: "$series"
seriesPart: $part
tags: ["series", "$series"]
---

# $title

*This is part $part of the $series series.*

## Previous Posts

(Links to previous parts)

## Content
EOF

echo "Created series post: $file"
```

### With Featured Image

```bash
#!/bin/bash
# post-with-image.sh

title="$1"
image_url="$2"

slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
file="content/posts/${slug}.md"

cat > "$file" << EOF
---
title: "$title"
date: $(date -I)T10:00:00Z
draft: true
featuredImage: "$image_url"
featuredImageAlt: "$title featured image"
---

# $title
EOF

echo "Created post with featured image"
```

## Post Generation Workflows

### From Issue Tracker

```bash
#!/bin/bash
# create-from-issue.sh

issue_number="$1"

# Fetch issue details (example with GitHub)
issue_data=$(gh issue view "$issue_number" --json title,body,labels)

title=$(echo "$issue_data" | jq -r '.title')
body=$(echo "$issue_data" | jq -r '.body')
labels=$(echo "$issue_data" | jq -r '.labels[].name')

slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
file="content/posts/${slug}.md"

cat > "$file" << EOF
---
title: "$title"
date: $(date -I)T10:00:00Z
draft: true
tags: $(echo "$labels" | jq -R . | jq -s .)
source: "issue"
sourceId: $issue_number
---

$body
EOF

echo "Created post from issue #$issue_number"
```

### Scheduled Posts

```bash
#!/bin/bash
# schedule-post.sh

title="$1"
publish_date="$2"  # Format: 2024-01-24

slug=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
file="content/posts/${slug}.md"

cat > "$file" << EOF
---
title: "$title"
date: $(date -I)T10:00:00Z
publishDate: ${publish_date}T10:00:00Z
draft: false
---

# $title
EOF

echo "Scheduled for: $publish_date"
```

## See Also

- <doc:ManagingTaxonomies>
- <doc:BulkUpdates>
- <doc:HugoWorkflows>
- <doc:../Scripting/ShellIntegration>
