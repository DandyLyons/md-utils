---
title: Host-denied source
description: Cache preservation when host policy denies access to a syntactically
  valid remote source.
---

# Host-denied source

Operation: synchronize every reference in `before.md` once, producing `after.md`.

Host setup: deny all remote source access. Expect source-access error and an unchanged cache; do not make a network request. The URI syntax is valid, and neither fallback applies (Sections 3.4 and 3.7).
