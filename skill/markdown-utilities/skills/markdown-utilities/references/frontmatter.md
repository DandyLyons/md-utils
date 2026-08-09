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

### Remove the complete frontmatter block
```bash
# Prompts for exactly y before removing each frontmatter block
md-utils fm remove-frontmatter document.md

# Short alias, noninteractive confirmation, and mapped non-Markdown files
md-utils fm rmfm posts/ --yes --include-non-md
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

## Check Unique Frontmatter Values

`fm unique` evaluates one JMESPath expression per note and checks that the
selected scalar value is unique. Strings, numbers, and booleans are supported.

```bash
# Check every ID in a directory
md-utils fm unique 'id' notes/

# Select a nested value
md-utils fm unique 'metadata.id' notes/

# Check one note's ID against a directory
md-utils fm unique 'id' --reference foo.md notes/

# Require every note to have an ID
md-utils fm unique 'id' --require-value notes/
```

Missing and null values are skipped unless `--require-value` is supplied. Arrays,
objects, and array projections such as `authors[].id` are unsupported; there is
currently no `--each` option.

Simple selectors such as `id` work without shell quoting, but single-quote the
entire JMESPath expression so Bash and Zsh preserve it exactly. In particular,
never double-quote an expression containing JMESPath backtick literals because
the shell interprets backticks as command substitution.

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
