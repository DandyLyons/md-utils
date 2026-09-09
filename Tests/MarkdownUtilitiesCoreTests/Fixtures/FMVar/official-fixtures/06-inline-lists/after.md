---
names:
- Alice
- Bob
- Carol
---

<fm-format locale="en-US"></fm-format>

Team: <fm-list query="$.names" format="conjunction">Alice, Bob, and Carol</fm-list>.

Choose <fm-list query="$.names" format="disjunction">Alice, Bob, or Carol</fm-list>.

Units: <fm-list query="$.names" format="unit" list-style="narrow">Alice Bob Carol</fm-list>.
