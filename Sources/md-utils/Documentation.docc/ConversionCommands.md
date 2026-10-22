# Conversion Commands

Convert Markdown files to other text formats from the command line.

## Overview

The `convert` command group exposes format conversion features from the `MarkdownUtilities` library. Current commands convert Markdown to plain text and CSV.

Use plain text conversion when Markdown syntax should be stripped while retaining
readable prose. Use CSV conversion to combine document frontmatter and optional
bodies for spreadsheet or data-processing tools; it does not extract Markdown tables.

`convert to-text` writes a single file or stdin to stdout by default. Batches
require `--output ./output/` or `--in-place`. The latter writes sibling `.txt`
files, retains original Markdown files and may overwrite existing `.txt` files.
Batch output uses flat basenames; it does not preserve the input directory tree.

`convert to-csv ./posts/` recursively combines files into `posts.csv` in the
working directory. Other input forms default to `output.csv`; `--output` selects
a file. `$body` is included by default; `--no-body` omits it. YAML and TOML
frontmatter keys become columns, and arrays/objects become JSON strings.
