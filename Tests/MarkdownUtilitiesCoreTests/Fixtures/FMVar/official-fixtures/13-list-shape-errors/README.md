---
title: Unsupported list shapes
description: Cache preservation when list queries select invalid cardinalities or
  unsupported member shapes.
---

# Unsupported list shapes

Operation: synchronize every reference in `before.md` once, producing `after.md`.

No caches change. In order: wrong-value-shape (multiple selected nodes), unsupported-item-shape (mixed null), unsupported-item-shape (nested sequence), unsupported-item-shape (mapping member), wrong-value-shape (scalar). Fallbacks do not hide errors (Sections 3.6–3.7).
