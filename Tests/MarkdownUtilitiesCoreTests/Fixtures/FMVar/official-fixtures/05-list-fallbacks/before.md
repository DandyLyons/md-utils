---
empty: []
nothing:
nulls:
-
-
---

<fm-list query="$.missing" format="unordered" default-zero="No *items*">
<ul>
<li>stale-missing</li>
</ul>
</fm-list>

<fm-list query="$.empty" format="unordered" default-zero="No items">
<ul>
<li>stale-empty</li>
</ul>
</fm-list>

<fm-list query="$.nothing" format="unordered" default-null="Unknown">
<ul>
<li>stale-nothing</li>
</ul>
</fm-list>

<fm-list query="$.nulls" format="unordered" default-null="Unknown">
<ul>
<li>stale-nulls</li>
</ul>
</fm-list>
