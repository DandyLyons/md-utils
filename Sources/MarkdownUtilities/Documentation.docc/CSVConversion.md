# Exporting Markdown Records as CSV

Export frontmatter, body content, and native path metadata from multiple Markdown documents.

## Overview

``CSVConverter`` accepts parsed `MarkdownDocument` values and their source paths. Frontmatter keys become columns, while ``CSVOptions`` controls body and path-metadata columns. CSV remains in `MarkdownUtilities` because absolute and relative path columns currently use native PathKit and current-working-directory behavior.
