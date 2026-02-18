# Common Use Cases

Practical recipes for the `md-utils` CLI.

## Search & Filter

```bash
# Find files with a specific tag
md-utils fm array contains --key tags --value swift posts/

# Find files by frontmatter value
md-utils fm search --key status --value published posts/

# Find files missing a key
find posts/ -name "*.md" | xargs -I {} sh -c 'md-utils fm has --key author {} || echo {}'

# JMESPath search (files where status is "draft")
md-utils fm search "status == 'draft'" posts/
```

## Batch Updates

```bash
# Set a key across all files in a directory
md-utils fm set --key author --value "Jane Doe" posts/

# Recursively update a date field
md-utils fm set --key updated --value "2026-01-24" posts/

# Tag all files in a directory
md-utils fm array append --key tags --value tutorial posts/*.md

# Find files with a tag, then publish them
md-utils fm array contains --key tags --value swift posts/ \
  | xargs md-utils fm set --key published --value true
```

## Document Structure

```bash
# Generate TOC for a document
md-utils toc document.md

# Generate TOC in markdown bullet format and save it
md-utils toc document.md --format md-bullet-links > toc.md

# Generate TOC for every file in a directory
for file in docs/*.md; do echo "## $file"; md-utils toc "$file"; echo; done

# Extract a named section
md-utils extract --name "Introduction" document.md

# Extract a section and save it
md-utils extract --index 2 document.md --output section.md

# Promote a heading in place
md-utils headings promote --index 3 document.md --in-place
```

## Data Extraction & Analysis

```bash
# Get all titles across a directory
md-utils fm dump posts/ | jq -r '.[].title'

# Dump all frontmatter as YAML
md-utils fm dump posts/ --format yaml

# Count published posts
md-utils fm dump posts/ | jq '[.[] | select(.status == "published")] | length'

# Get unique authors
md-utils fm dump posts/ | jq -r '.[].author' | sort -u

# Extract specific lines with line numbers
md-utils lines document.md -s 1 -e 50 --numbered

# Get body content only (strip frontmatter)
md-utils body document.md
```

## Pipelines

```bash
# Extract a section, then convert to plain text
md-utils extract --name "API Reference" document.md | md-utils convert to-text

# Find files with tag and extract their TOC
md-utils fm array contains --key tags --value swift posts/ \
  | xargs -I {} md-utils toc {}

# Find drafts, search for pattern in them
md-utils fm search "status == 'draft'" posts/ \
  | xargs grep -l "TODO"

# Check wikilinks across a vault
md-utils links check posts/ --root ~/vault
```
