---
title: Per-element atomic failure
description: Independent reference updates with atomic cache preservation for shape
  and type-parsing errors.
---

# Per-element atomic failure

Operation: synchronize every reference in `before.md` once, producing `after.md`.

Title succeeds; the scalar mapping produces wrong-value-shape; the list produces type-parsing error on nope. Neither error is hidden by fallbacks. No partial list update occurs, but the independent valid reference still updates (Sections 3.6–3.7).
