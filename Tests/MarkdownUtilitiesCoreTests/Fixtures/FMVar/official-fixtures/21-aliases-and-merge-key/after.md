---
name: &name Ada
copy: *name
base: &base {role: Editor}
profile:
  "<<": *base
---

<fm-var query="$.copy">Ada</fm-var>

<fm-var query="$.profile.role" default-zero="No merged role">No merged role</fm-var>

<fm-var query="$.profile['&lt;&lt;'].role">Editor</fm-var>
