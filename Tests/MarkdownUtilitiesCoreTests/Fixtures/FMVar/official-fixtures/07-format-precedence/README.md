---
title: Document, scoped, and local formatting
description: Formatting precedence across unscoped declarations, scoped declarations,
  and local attributes.
---

# Document, scoped, and local formatting

Operation: synchronize every reference in `before.md` once, producing `after.md`.

Both references succeed. Later matching scoped declarations win over earlier scoped declarations and even later unscoped defaults. Local attributes win last. Configuration elements remain unchanged. Localized after text is illustrative, not a portable byte-exact oracle (Sections 2.3 and 3.8).
