---
values:
- A
- B
mixed:
- A
-
nested:
- - A
objects:
- name: A
scalar: A
---

<fm-list query="$.values[*]" format="unordered" default-zero="No items">
<ul>
<li>Retained 1</li>
</ul>
</fm-list>

<fm-list query="$.mixed" format="unordered" default-zero="No items">
<ul>
<li>Retained 2</li>
</ul>
</fm-list>

<fm-list query="$.nested" format="unordered" default-zero="No items">
<ul>
<li>Retained 3</li>
</ul>
</fm-list>

<fm-list query="$.objects" format="unordered" default-zero="No items">
<ul>
<li>Retained 4</li>
</ul>
</fm-list>

<fm-list query="$.scalar" format="unordered" default-zero="No items">
<ul>
<li>Retained 5</li>
</ul>
</fm-list>
