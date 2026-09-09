---
nothing:
empty:
zero: 0
flag: false
---

Missing: <fm-var query="$.missing" type="integer" default-zero="Not *available*">old-missing</fm-var>.

Null: <fm-var query="$.nothing" default-null="Unknown &amp; pending">old-null</fm-var>.

Empty: <fm-var query="$.empty" default-zero="fallback" default-null="fallback">old-empty</fm-var>.

Zero: <fm-var query="$.zero" type="integer" default-zero="fallback">old-zero</fm-var>.

False: <fm-var query="$.flag" type="boolean" default-zero="fallback">old-flag</fm-var>.
