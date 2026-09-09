---
name: &name Ada
copy: *name
base: &base {role: Editor}
profile:
  "<<": *base
---

<fm-var query="$.copy">old-copy</fm-var>

<fm-var query="$.profile.role" default-zero="No merged role">old-role</fm-var>

<fm-var query="$.profile['&lt;&lt;'].role">old-literal</fm-var>
