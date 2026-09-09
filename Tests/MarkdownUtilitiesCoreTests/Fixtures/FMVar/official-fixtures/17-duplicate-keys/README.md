---
title: Duplicate YAML keys
description: Rejection of duplicate YAML mapping keys before JSONPath evaluation.
---

# Duplicate YAML keys

Operation: synchronize every reference in `before.md` once, producing `after.md`.

Expect query-argument error and an unchanged cache. Projection rejects the entire source before querying, even when the selected path would otherwise be usable (Sections 3.7 and 4.2).
