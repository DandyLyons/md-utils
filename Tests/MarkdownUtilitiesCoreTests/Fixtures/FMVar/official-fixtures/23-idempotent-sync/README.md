---
title: "Already synchronized document"
description: "Unchanged output when successful synchronization reproduces existing scalar and list caches."
---

# Already synchronized document

Operation: synchronize every reference in `before.md` once, producing `after.md`.

Both references resolve successfully to their existing caches. The before and after documents are identical. This is also the second-pass expectation for deterministic successful cases (Section 3.1).
