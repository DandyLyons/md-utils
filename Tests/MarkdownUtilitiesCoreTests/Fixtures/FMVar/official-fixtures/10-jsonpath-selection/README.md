---
title: JSONPath selection and attribute decoding
description: JSONPath selection with escaped attributes, literal property names, and
  ordered multi-node results.
---

# JSONPath selection and attribute decoding

Operation: synchronize every reference in `before.md` once, producing `after.md`.

All three succeed. Decode attribute entities before evaluating JSONPath. The final query intentionally selects multiple nodes in array-selector order: Bob, Ada, Bob; fm-var renders only the first. Authors should generally avoid multiple-node scalar queries (Sections 3.6, 3.9, 4.1).
