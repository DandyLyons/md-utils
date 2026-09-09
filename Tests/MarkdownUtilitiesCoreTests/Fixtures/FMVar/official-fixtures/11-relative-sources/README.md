---
title: Relative Markdown and YAML sources
description: Resolving relative references to Markdown frontmatter and standalone
  YAML sources.
---

# Relative Markdown and YAML sources

Operation: synchronize every reference in `before.md` once, producing `after.md`.

Both succeed. Establish the base URI as the file URI of before.md and permit reads of the provided sources directory. Read Markdown frontmatter and the standalone YAML document respectively; leave both source files unchanged (Sections 3.4–3.5).
