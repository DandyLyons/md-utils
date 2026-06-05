# Frontmatter Commands

Read, search, and mutate YAML frontmatter from the `frontmatter` command group.

## Overview

The `frontmatter` command group, also available as `fm`, provides CRUD operations for Markdown YAML frontmatter. Commands can operate on one file, several files, or directories resolved through the shared global path options.

Common operations include reading values, setting values, checking for keys, removing or renaming keys, replacing an entire frontmatter block, dumping frontmatter in multiple formats, searching with JMESPath, sorting keys, touching empty keys, and mutating array values.

## Output Semantics

Commands that report values preserve the distinction between a missing key and a key whose YAML value is null. Machine-readable formats should be preferred when that distinction matters.
