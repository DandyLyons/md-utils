# Content Selection Commands

Extract body text, line ranges, headings, and sections from Markdown files.

## Overview

Content selection commands expose focused ways to retrieve part of a Markdown document. Use `body` to omit frontmatter, `lines` to select by line number, `extract` to select a section, and the `section` command group to list, get, set, or move heading-based sections.

These commands are useful in scripts because they return selected content directly unless an option writes the result back to a file.

`toc` and `section list` default to headings-only Markdown
(`--format md-only-headings`), not bullet links. Use `--format md-bullet-links`
for anchor links. Both accept directories and recurse by default. Batch output
adds filename headers, including with JSON formats; it is not one JSON document.

`body` accepts paths or stdin; it does not implicitly scan the current directory.
`lines` and `explore` take one file. `extract`, `section get/set` and section moves
require exactly one resolved file. `section insert/remove` use `--into` for one
document. `section set` reads replacement body text from stdin or `--input`,
preserving the heading; it has no `--content` option.
