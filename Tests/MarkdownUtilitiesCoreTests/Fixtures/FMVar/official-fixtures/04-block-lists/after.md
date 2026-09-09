---
steps:
- Install
- Review
- Install
flags:
- true
- false
---

<fm-list query="$.steps" format="ordered">
<ol>
<li>Install</li>
<li>Review</li>
<li>Install</li>
</ol>
</fm-list>

<fm-list query="$.flags" format="unordered" item-type="boolean">
<ul>
<li>TRUE</li>
<li>FALSE</li>
</ul>
</fm-list>
