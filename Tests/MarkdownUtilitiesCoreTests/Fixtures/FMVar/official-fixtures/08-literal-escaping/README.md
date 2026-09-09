---
title: Literal text and markup injection
description: Escaping HTML and Markdown delimiters while treating reference markup
  inside scalar values as literal text.
---

# Literal text and markup injection

Operation: synchronize every reference in `before.md` once, producing `after.md`.

Both references succeed. All specified Markdown delimiters and HTML/XML text delimiters are escaped. Markup inside a scalar is literal and never recursively resolved (Sections 3.5 and 3.9).
