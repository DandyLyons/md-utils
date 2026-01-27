# Managing Hugo Taxonomies

Work with tags, categories, and custom taxonomies in Hugo sites.

## Overview

Hugo uses taxonomies (tags, categories, etc.) to organize content. md-utils makes it easy to manage, analyze, and update taxonomies across your site.

## Listing Taxonomies

### All Tags

```bash
# List all unique tags
md-utils -r fm get --key tags content/ --format json | \\
    jq -r '.[]' | sort | uniq

# Count tag usage
md-utils -r fm get --key tags content/ --format json | \\
    jq -r '.[]' | sort | uniq -c | sort -rn
```

### All Categories

```bash
# List categories
md-utils -r fm get --key categories content/ --format json | \\
    jq -r '.[]' | sort | uniq

# Category frequency
md-utils -r fm get --key categories content/ --format json | \\
    jq -r '.[]' | sort | uniq -c | sort -rn
```

## Adding Taxonomy Terms

### Add Tag to Posts

```bash
#!/bin/bash
# add-tag.sh - Add tag to posts

tag="$1"
shift
files="$@"

for file in $files; do
    # Get existing tags
    current=$(md-utils fm get --key tags "$file" --format json 2>/dev/null || echo '[]')

    # Add new tag if not present
    updated=$(echo "$current" | jq --arg tag "$tag" '. + [$tag] | unique')

    # Update file
    md-utils fm set --key tags --value "$updated" "$file" -i

    echo "Added '$tag' to $file"
done
```

Usage:
```bash
./add-tag.sh "tutorial" content/posts/*.md
```

### Add Category

```bash
#!/bin/bash
# add-category.sh

category="$1"
file="$2"

current=$(md-utils fm get --key categories "$file" --format json 2>/dev/null || echo '[]')
updated=$(echo "$current" | jq --arg cat "$category" '. + [$cat] | unique')

md-utils fm set --key categories --value "$updated" "$file" -i
```

## Removing Taxonomy Terms

### Remove Tag

```bash
#!/bin/bash
# remove-tag.sh

tag="$1"
file="$2"

current=$(md-utils fm get --key tags "$file" --format json)
updated=$(echo "$current" | jq --arg tag "$tag" 'del(.[] | select(. == $tag))')

md-utils fm set --key tags --value "$updated" "$file" -i
```

### Bulk Remove

```bash
#!/bin/bash
# Remove deprecated tag from all posts

deprecated_tag="old-tag"

for file in content/posts/**/*.md; do
    if md-utils fm get --key tags "$file" --format json | grep -q "\"$deprecated_tag\""; then
        current=$(md-utils fm get --key tags "$file" --format json)
        updated=$(echo "$current" | jq --arg tag "$deprecated_tag" 'del(.[] | select(. == $tag))')
        md-utils fm set --key tags --value "$updated" "$file" -i
        echo "Removed from: $file"
    fi
done
```

## Taxonomy Analysis

### Tag Statistics

```bash
#!/bin/bash
# taxonomy-stats.sh

echo "Taxonomy Statistics"
echo "==================="
echo ""

# Total posts
total=$(find content/posts -name "*.md" | wc -l)
echo "Total posts: $total"
echo ""

# Tag statistics
echo "Tag Statistics:"
all_tags=$(md-utils -r fm get --key tags content/posts/ --format json | jq -r '.[]')
unique_tags=$(echo "$all_tags" | sort | uniq | wc -l)
echo "  Unique tags: $unique_tags"
echo "  Most used tags:"
echo "$all_tags" | sort | uniq -c | sort -rn | head -10

echo ""

# Category statistics
echo "Category Statistics:"
all_cats=$(md-utils -r fm get --key categories content/posts/ --format json | jq -r '.[]')
unique_cats=$(echo "$all_cats" | sort | uniq | wc -l)
echo "  Unique categories: $unique_cats"
echo "  Most used categories:"
echo "$all_cats" | sort | uniq -c | sort -rn
```

### Find Posts by Tag

```bash
#!/bin/bash
# find-by-tag.sh

tag="$1"

echo "Posts tagged with '$tag':"
echo ""

for file in content/posts/**/*.md; do
    if md-utils fm get --key tags "$file" --format json 2>/dev/null | grep -q "\"$tag\""; then
        title=$(md-utils fm get --key title "$file")
        echo "- $title ($file)"
    fi
done
```

## Standardizing Taxonomies

### Normalize Tags

```bash
#!/bin/bash
# normalize-tags.sh - Convert tags to lowercase

for file in content/posts/**/*.md; do
    tags=$(md-utils fm get --key tags "$file" --format json 2>/dev/null)

    if [ -n "$tags" ]; then
        normalized=$(echo "$tags" | jq 'map(ascii_downcase) | unique | sort')
        md-utils fm set --key tags --value "$normalized" "$file" -i
    fi
done
```

### Merge Similar Tags

```bash
#!/bin/bash
# merge-tags.sh - Merge similar tags

declare -A tag_mapping=(
    ["javascript"]="js"
    ["typescript"]="ts"
    ["golang"]="go"
)

for file in content/posts/**/*.md; do
    tags=$(md-utils fm get --key tags "$file" --format json 2>/dev/null)

    if [ -n "$tags" ]; then
        # Replace tags according to mapping
        updated="$tags"
        for old in "${!tag_mapping[@]}"; do
            new="${tag_mapping[$old]}"
            updated=$(echo "$updated" | jq --arg old "$old" --arg new "$new" \\
                'map(if . == $old then $new else . end) | unique')
        done

        md-utils fm set --key tags --value "$updated" "$file" -i
    fi
done
```

## Taxonomy Reports

### Generate Tag Cloud Data

```bash
#!/bin/bash
# tag-cloud.sh - Generate tag cloud JSON

md-utils -r fm get --key tags content/posts/ --format json | \\
    jq -r '.[]' | sort | uniq -c | \\
    awk '{print "{\"tag\":\""$2"\",\"count\":"$1"}"}' | \\
    jq -s '.' > tag-cloud.json

echo "Generated: tag-cloud.json"
```

### Category Hierarchy

```bash
#!/bin/bash
# category-hierarchy.sh

echo "Category Hierarchy"
echo "=================="
echo ""

md-utils -r fm get --key categories content/ --format json | \\
    jq -r '.[]' | sort | uniq | while read -r category; do

    count=$(for file in content/**/*.md; do
        md-utils fm get --key categories "$file" --format json 2>/dev/null | \\
            grep -q "\"$category\"" && echo 1
    done | wc -l)

    echo "$category ($count posts)"

    # List recent posts in category
    for file in content/posts/**/*.md; do
        if md-utils fm get --key categories "$file" --format json 2>/dev/null | \\
           grep -q "\"$category\""; then
            title=$(md-utils fm get --key title "$file")
            echo "  - $title"
        fi
    done | head -5

    echo ""
done
```

## See Also

- <doc:CreatingPosts>
- <doc:BulkUpdates>
- <doc:HugoWorkflows>
