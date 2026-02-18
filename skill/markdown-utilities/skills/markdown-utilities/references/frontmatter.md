# Frontmatter Operations Reference

## Basic CRUD

### Get a value
```bash
md-utils fm get --key title document.md
```

### Set a value
```bash
md-utils fm set --key author --value "Jane Doe" document.md
# Batch: applies to all .md files in the directory
md-utils fm set --key status --value published posts/
```

### Check if key exists
```bash
md-utils fm has --key published document.md
# Exit code 0 = exists, non-zero = not found
```

### List all keys
```bash
md-utils fm list document.md
```

### Remove a key
```bash
md-utils fm remove --key draft document.md
```

### Rename a key
```bash
md-utils fm rename --old-key pubDate --new-key date document.md
```

### Replace entire frontmatter
```bash
md-utils fm replace --data '{"title":"New Title","author":"Jane"}' document.md
```

### Add keys without values (touch)
```bash
md-utils fm touch --key reviewed document.md
```

### Sort keys alphabetically
```bash
md-utils fm sort-keys document.md --in-place
```

## Dump Frontmatter

Output entire frontmatter in various formats:

```bash
# Single file (JSON by default)
md-utils fm dump post.md

# YAML format
md-utils fm dump post.md --format yaml

# Multiple files: outputs JSON array with "$path" key injected
md-utils fm dump posts/ --format json

# Pipe to jq
md-utils fm dump posts/ | jq '.[].title'

# Pipe to yq
md-utils fm dump posts/ --format yaml | yq '.[].title'

# Cat-style headers (legacy)
md-utils fm dump posts/ --cat-headers
```

**Formats:** `json` (default), `yaml`, `raw`, `plist`

## Search with JMESPath

`fm search` filters files using a JMESPath expression evaluated against each file's frontmatter. Outputs matching file paths.

```bash
# Find files where status is "published"
md-utils fm search "status == 'published'" posts/

# Find files where a key exists
md-utils fm search "author" posts/

# Combine with xargs to act on results
md-utils fm search "status == 'draft'" posts/ | xargs md-utils fm set --key reviewed --value false
```

## Array Operations

For frontmatter keys that hold arrays (e.g. `tags: [swift, ios]`):

```bash
# Check if array contains value (outputs matching file paths)
md-utils fm array contains --key tags --value swift posts/

# Append a value
md-utils fm array append --key tags --value tutorial posts/*.md

# Prepend a value
md-utils fm array prepend --key tags --value featured posts/*.md

# Remove first occurrence of a value
md-utils fm array remove --key tags --value draft posts/*.md
```

## Common Pipelines

```bash
# Find files tagged 'swift' and mark them published
md-utils fm array contains --key tags --value swift posts/ \
  | xargs md-utils fm set --key published --value true

# Find files with BOTH 'swift' AND 'tutorial' tags
md-utils fm array contains --key tags --value swift posts/ \
  | xargs -I {} sh -c 'md-utils fm array contains --key tags --value tutorial {} && echo {}'

# List all unique authors across a directory
md-utils fm dump posts/ | jq -r '.[].author' | sort -u

# Count published posts
md-utils fm dump posts/ | jq '[.[] | select(.status == "published")] | length'

# Find files missing a required key
find posts/ -name "*.md" | xargs -I {} sh -c 'md-utils fm has --key author {} || echo {}'
```
