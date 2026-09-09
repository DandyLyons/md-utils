---
nothing:
empty: []
nulls:
-
---

<fm-var query="$.missing">Keep missing</fm-var>

<fm-var query="$.nothing">Keep null</fm-var>

<fm-list query="$.empty" format="ordered">
<ol><li>Keep empty</li></ol>
</fm-list>

<fm-list query="$.nulls" format="unordered">
<ul><li>Keep nulls</li></ul>
</fm-list>
