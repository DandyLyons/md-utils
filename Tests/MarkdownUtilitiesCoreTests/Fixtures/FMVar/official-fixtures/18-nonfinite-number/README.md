---
title: "Non-finite YAML number"
description: "Rejection of non-finite YAML numbers during query-argument projection."
---

# Non-finite YAML number

Operation: synchronize every reference in `before.md` once, producing `after.md`.

Expect query-argument error and an unchanged cache. Projection rejects the entire source before querying, even when the selected path would otherwise be usable (Sections 3.7 and 4.2).
