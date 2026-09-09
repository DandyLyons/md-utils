---
title: Missing, null, and falsy scalars
description: Distinct missing and null fallbacks while empty strings, zero, and false
  remain authoritative values.
---

# Missing, null, and falsy scalars

Operation: synchronize every reference in `before.md` once, producing `after.md`.

In document order: zero-result fallback, null-result fallback, then three successful scalar updates. Fallbacks are literal, bypass coercion, and are escaped. Empty strings, zero, and false do not trigger fallbacks (Section 3.7).
