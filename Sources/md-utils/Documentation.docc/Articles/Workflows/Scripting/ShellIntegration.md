# Shell Integration

Integrate md-utils seamlessly into your shell environment and workflows.

## Overview

md-utils is designed to work naturally with shell commands, pipes, and standard Unix tools. This guide covers shell integration techniques, command-line patterns, and advanced shell features that make md-utils more powerful and convenient.

## Shell Aliases and Functions

### Bash/Zsh Aliases

```bash
# ~/.bashrc or ~/.zshrc

# Common operations
alias mdu='md-utils'
alias mdfm='md-utils fm'
alias mdtoc='md-utils toc'
alias mdtext='md-utils convert to-text'

# Shortcuts for frequent tasks
alias md-update='md-utils fm set --key modified --value "$(date -I)" --in-place'
alias md-draft='md-utils fm set --key draft --value "true" --in-place'
alias md-publish='md-utils fm set --key draft --value "false" --in-place'

# Recursive operations
alias md-validate='find . -name "*.md" -exec md-utils fm get --key title {} \; >/dev/null'
alias md-list-tags='md-utils fm get --key tags --recursive .'
```

### Shell Functions

```bash
# ~/.bashrc or ~/.zshrc

# Quick note creation
mdnote() {
  local title="$1"
  local file="${2:-$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr ' ' '-').md}"

  touch "$file"
  md-utils fm set --key title --value "$title" \
    --key created --value "$(date -Iseconds)" \
    --key draft --value "true" \
    "$file" --in-place

  echo "Created: $file"
  ${EDITOR:-vim} "$file"
}

# Search frontmatter
mdsearch() {
  local key="$1"
  local value="$2"
  local dir="${3:-.}"

  md-utils fm get --key "$key" --recursive "$dir" | grep "$value"
}

# Bulk tag addition
mdtag() {
  local tag="$1"
  shift
  local files=("$@")

  for file in "${files[@]}"; do
    # Get existing tags
    existing=$(md-utils fm get --key tags "$file" 2>/dev/null || echo "[]")

    # Add new tag
    new_tags=$(echo "$existing" | jq --arg tag "$tag" '. + [$tag] | unique')

    md-utils fm set --key tags --value "$new_tags" "$file" --in-place
    echo "Tagged $file: $tag"
  done
}

# Quick metadata view
mdinfo() {
  local file="$1"

  echo "=== $file ==="
  echo "Title: $(md-utils fm get --key title "$file" 2>/dev/null || echo 'N/A')"
  echo "Date:  $(md-utils fm get --key date "$file" 2>/dev/null || echo 'N/A')"
  echo "Tags:  $(md-utils fm get --key tags "$file" 2>/dev/null || echo 'N/A')"
  echo ""
  echo "Word count: $(md-utils body "$file" | wc -w)"
}
```

## Pipe Integration

### Input/Output Pipes

```bash
# Pipe file list to md-utils
find docs/ -name "*.md" | while read -r file; do
  md-utils fm get --key title "$file"
done

# Combine with other tools
md-utils fm get --key tags --recursive docs/ | \
  jq -s 'add | unique' | \
  sort

# Process md-utils output
md-utils fm dump docs/guide.md | \
  grep -E '^(title|author|date)=' | \
  column -t -s '='
```

### Process Substitution

```bash
# Compare metadata between directories
diff <(md-utils fm get --key title --recursive docs/) \
     <(md-utils fm get --key title --recursive archive/)

# Merge outputs
paste <(md-utils fm get --key title --recursive docs/) \
      <(md-utils fm get --key date --recursive docs/) \
      -d ,
```

### Command Substitution

```bash
# Use md-utils output in commands
title=$(md-utils fm get --key title post.md)
echo "Editing: $title"

# Dynamic file generation
for file in $(md-utils fm get --key draft --recursive docs/ | grep true | cut -d: -f1); do
  echo "Draft: $file"
done

# Backticks (legacy)
date=`md-utils fm get --key date post.md`
```

## File Operations

### Find and Execute

```bash
# Find and process
find docs/ -name "*.md" -exec \
  md-utils fm set --key processed --value "true" {} --in-place \;

# Find with conditions
find docs/ -name "*.md" -mtime -7 -exec \
  md-utils fm set --key recent --value "true" {} --in-place \;

# Complex find operations
find docs/ -type f -name "*.md" \
  ! -path "*/drafts/*" \
  ! -path "*/.git/*" \
  -exec md-utils toc {} --output toc/{} \;
```

### xargs Integration

```bash
# Basic xargs
ls docs/*.md | xargs md-utils fm get --key title

# Parallel processing
find docs/ -name "*.md" | \
  xargs -P 4 -I {} md-utils toc {} --output toc/{}

# With null delimiter (handles spaces in filenames)
find docs/ -name "*.md" -print0 | \
  xargs -0 md-utils fm set --key updated --value "true" --in-place
```

### While Loops

```bash
# Read line by line
md-utils fm get --key title --recursive docs/ | while IFS=: read -r file title; do
  echo "File: $file"
  echo "Title: $title"
  echo "---"
done

# Process with null delimiter
find docs/ -name "*.md" -print0 | while IFS= read -r -d '' file; do
  md-utils fm set --key processed --value "true" "$file" --in-place
done
```

## Environment Variables

### Configuration via Environment

```bash
# Set defaults via environment
export MD_UTILS_EXTENSIONS="md,markdown,mdown"
export MD_UTILS_OUTPUT_FORMAT="json"
export MD_UTILS_RECURSIVE=true

# Use in scripts
md-utils fm get --key title --recursive docs/
```

### Temporary Overrides

```bash
# Override for single command
MD_UTILS_OUTPUT_FORMAT=yaml md-utils fm dump post.md

# Multiple variables
MD_UTILS_RECURSIVE=false MD_UTILS_EXTENSIONS=md \
  md-utils fm get --key title docs/
```

## Shell Completion

### Bash Completion

```bash
# ~/.bash_completion.d/md-utils

_md_utils_completion() {
  local cur prev opts

  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  # Main commands
  if [ $COMP_CWORD -eq 1 ]; then
    opts="fm toc convert body help"
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
  fi

  # Subcommands
  case "${prev}" in
    fm)
      opts="get set list dump delete"
      COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
      ;;
    convert)
      opts="to-text"
      COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
      ;;
    --key)
      # Complete common keys
      opts="title date author tags category draft"
      COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
      ;;
    *)
      # Complete filenames
      COMPREPLY=( $(compgen -f -X '!*.md' -- ${cur}) )
      ;;
  esac
}

complete -F _md_utils_completion md-utils
```

### Zsh Completion

```zsh
# ~/.zsh/completions/_md-utils

#compdef md-utils

_md_utils() {
  local -a commands

  commands=(
    'fm:Frontmatter operations'
    'toc:Generate table of contents'
    'convert:Convert markdown to other formats'
    'body:Extract body content'
    'help:Show help'
  )

  _arguments -C \
    '1: :->command' \
    '*:: :->args'

  case $state in
    command)
      _describe 'command' commands
      ;;
    args)
      case $words[1] in
        fm)
          local -a fm_commands=(
            'get:Get frontmatter value'
            'set:Set frontmatter value'
            'list:List frontmatter keys'
            'dump:Dump all frontmatter'
            'delete:Delete frontmatter key'
          )
          _describe 'fm command' fm_commands
          ;;
      esac
      ;;
  esac
}

_md_utils "$@"
```

## Advanced Integration

### Custom Commands

```bash
#!/bin/bash
# ~/bin/md-daily

# Create daily note with md-utils

date_str=$(date +%Y-%m-%d)
daily_file="$HOME/notes/daily/$date_str.md"

if [ -f "$daily_file" ]; then
  echo "Daily note already exists"
else
  mkdir -p "$(dirname "$daily_file")"

  md-utils fm set --key title --value "Daily Note - $(date +%Y-%m-%d)" \
    --key date --value "$date_str" \
    --key type --value "daily" \
    --key tags --value "['daily']" \
    "$daily_file" --in-place

  cat >> "$daily_file" << 'EOF'
## Morning

- [ ] Review calendar
- [ ] Plan priorities

## Notes

EOF

  echo "Created: $daily_file"
fi

${EDITOR:-vim} "$daily_file"
```

### Directory-Specific Helpers

```bash
# .envrc (use with direnv)

# Auto-load md-utils helpers for this directory
export PATH="$PWD/scripts:$PATH"

# Set defaults for this project
export MD_UTILS_EXTENSIONS="md,markdown"
export DOCS_DIR="$PWD/docs"

# Load project-specific functions
source "$PWD/scripts/md-helpers.sh"
```

### Interactive Menus

```bash
#!/bin/bash
# md-menu.sh

# Interactive menu for md-utils operations

while true; do
  echo ""
  echo "=== md-utils Menu ==="
  echo "1. Update timestamps"
  echo "2. Generate TOCs"
  echo "3. Validate metadata"
  echo "4. Search by tag"
  echo "5. Quit"
  echo ""

  read -p "Select option: " choice

  case $choice in
    1)
      read -p "Directory [docs/]: " dir
      dir=${dir:-docs/}
      find "$dir" -name "*.md" -mtime -7 -exec \
        md-utils fm set --key modified --value "$(date -I)" {} --in-place \;
      echo "✓ Timestamps updated"
      ;;
    2)
      read -p "Directory [docs/]: " dir
      dir=${dir:-docs/}
      md-utils toc --recursive "$dir" --output toc/
      echo "✓ TOCs generated"
      ;;
    3)
      read -p "Directory [docs/]: " dir
      dir=${dir:-docs/}
      ./scripts/validate-docs.sh "$dir"
      ;;
    4)
      read -p "Tag: " tag
      md-utils fm get --key tags --recursive docs/ | grep "$tag"
      ;;
    5)
      exit 0
      ;;
    *)
      echo "Invalid option"
      ;;
  esac

  read -p "Press enter to continue..."
done
```

## Shell Scripting Best Practices

### Error Handling

```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined variable, pipe failure

# Check if md-utils is available
if ! command -v md-utils &> /dev/null; then
  echo "Error: md-utils not found" >&2
  exit 1
fi

# Validate file exists
if [ ! -f "$file" ]; then
  echo "Error: File not found: $file" >&2
  exit 1
fi

# Capture and check exit codes
if ! md-utils fm set --key test --value "value" "$file" --in-place; then
  echo "Error: Failed to update $file" >&2
  exit 1
fi
```

### Logging

```bash
#!/bin/bash

# Log function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a script.log
}

log "Starting processing..."
md-utils fm set --key processed --value "true" --recursive docs/ --in-place
log "Processing complete"
```

### Debugging

```bash
#!/bin/bash

# Enable debug mode
set -x  # Print commands before execution

# Or use conditional debugging
if [ "${DEBUG:-false}" = "true" ]; then
  set -x
fi

# Dry run mode
if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "Would run: md-utils fm set ..."
else
  md-utils fm set --key field --value "value" --in-place
fi
```

## See Also

- <doc:PipelinePatterns>
- <doc:ErrorHandling>
- <doc:Scripting>
- <doc:../../GlobalOptions>
