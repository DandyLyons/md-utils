# Frontmatter Commands

Read, search, and mutate YAML frontmatter from the `frontmatter` command group.

## Overview

The `frontmatter` command group, also available as `fm`, provides CRUD operations for Markdown YAML frontmatter. Commands can operate on one file, several files, or directories resolved through the shared global path options.

Common operations include reading values, setting values, checking for keys, removing or renaming keys, replacing or completely removing an entire frontmatter block, dumping frontmatter in multiple formats, searching with JMESPath, checking uniqueness, sorting keys, touching empty keys, and mutating array values.

## Removing Complete Frontmatter

Use `fm remove-frontmatter`, or its `rmfm` alias, to delete the complete
frontmatter block while preserving the document body:

```bash
md-utils fm remove-frontmatter post.md
md-utils fm rmfm notes/ --include-non-md
md-utils fm rmfm post.md --yes
```

The command asks for `y` confirmation once per file that contains frontmatter.
Pass `-y` or `--yes` to skip the confirmation. Mapped non-Markdown files are
included in batch operations only when `--include-non-md` is supplied.

## Uniqueness Checks

Use `fm unique` to check that a scalar selected by JMESPath is unique across a
directory or explicit list of paths:

```bash
md-utils fm unique 'id' notes/
md-utils fm unique 'metadata.id' notes/
md-utils fm unique 'id' --reference foo.md notes/
```

Collection mode reports every collision. `--reference` instead checks only the
reference note's selected value and ignores unrelated collisions. Missing and
null results are skipped by default; use `--require-value` to reject them.

The expression must produce one string, number, or boolean for each note. Arrays,
objects, and projections such as `authors[].id` are unsupported. A future
`--each` option is outside the current command's scope.

Simple selectors such as `id` are safe unquoted, but single-quoting the complete
expression is recommended. Richer JMESPath syntax may contain characters that
Bash or Zsh interpret. Double-quoted expressions do not protect JMESPath backtick
literals from shell command substitution.

## Output Semantics

Commands that report values preserve the distinction between a missing key and a key whose YAML value is null. Machine-readable formats should be preferred when that distinction matters.
