---
title: Malformed query versus structural mismatch
description: Distinguishing malformed JSONPath queries from valid queries that select
  no nodes.
---

# Malformed query versus structural mismatch

Operation: synchronize every reference in `before.md` once, producing `after.md`.

First: malformed-query error because the query lacks $. Second: valid query with a structural mismatch selects zero nodes and writes the fallback. Query syntax validity is independent of the data (Sections 3.7 and 4.1).
