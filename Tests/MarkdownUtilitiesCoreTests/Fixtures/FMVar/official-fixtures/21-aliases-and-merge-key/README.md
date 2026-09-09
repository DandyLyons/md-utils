---
title: "Expanded aliases and literal merge key"
description: "YAML alias expansion with the merge key treated as an ordinary string key."
---

# Expanded aliases and literal merge key

Operation: synchronize every reference in `before.md` once, producing `after.md`.

In order: success, zero-result fallback, success. Aliases expand, but YAML Core treats << as an ordinary key rather than merging the mapping (Section 4.2).
