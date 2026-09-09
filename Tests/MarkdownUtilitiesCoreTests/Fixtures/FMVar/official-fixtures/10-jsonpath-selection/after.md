---
build.version: 3
books:
- title: Budget
  price: 5
- title: Premium
  price: 15
names:
- Ada
- Bob
---

Version: <fm-var query="$['build.version']">3</fm-var>.

Budget: <fm-var query="$.books[?@.price &lt; 10 &amp;&amp; @.price &gt; 0].title">Budget</fm-var>.

First selected: <fm-var query="$.names[1,0,1]">Bob</fm-var>.
