---
names:
- Alice
- Bob
- Carol
---

<fm-format locale="en-US"></fm-format>

Team: <fm-list query="$.names" format="conjunction">old-team</fm-list>.

Choose <fm-list query="$.names" format="disjunction">old-choice</fm-list>.

Units: <fm-list query="$.names" format="unit" list-style="narrow">old-units</fm-list>.
