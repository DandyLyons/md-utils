# Content Selection Commands

Extract body text, line ranges, headings, and sections from Markdown files.

## Overview

Content selection commands expose focused ways to retrieve part of a Markdown document. Use `body` to omit frontmatter, `lines` to select by line number, `extract` to select a section, and the `section` command group to list, get, set, or move heading-based sections.

These commands are useful in scripts because they return selected content directly unless an option writes the result back to a file.
