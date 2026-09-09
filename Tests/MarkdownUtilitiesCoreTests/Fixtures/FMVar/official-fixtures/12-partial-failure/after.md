---
title: Current
values:
- 1
- nope
- 3
object:
  name: Ada
---

Title: <fm-var query="$.title">Current</fm-var>.

Shape: <fm-var query="$.object" default-zero="hidden">Retained scalar cache</fm-var>.

<fm-list query="$.values" format="ordered" item-type="integer" default-null="hidden">
<ol>
<li>Retained entire list</li>
</ol>
</fm-list>
