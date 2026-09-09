---
title: "Embedded line break"
description: "Cache preservation when a selected scalar contains an unsupported embedded line break."
---

# Embedded line break

Operation: synchronize every reference in `before.md` once, producing `after.md`.

Expect value error and an unchanged cache: version 1 does not support embedded line breaks in selected scalar text (Section 3.9).
