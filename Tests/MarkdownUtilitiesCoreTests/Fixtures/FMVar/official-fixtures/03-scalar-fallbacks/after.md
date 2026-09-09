---
nothing:
empty:
zero: 0
flag: false
---

Missing: <fm-var query="$.missing" type="integer" default-zero="Not *available*">Not &#42;available&#42;</fm-var>.

Null: <fm-var query="$.nothing" default-null="Unknown &amp; pending">Unknown &amp; pending</fm-var>.

Empty: <fm-var query="$.empty" default-zero="fallback" default-null="fallback"></fm-var>.

Zero: <fm-var query="$.zero" type="integer" default-zero="fallback">0</fm-var>.

False: <fm-var query="$.flag" type="boolean" default-zero="fallback">FALSE</fm-var>.
