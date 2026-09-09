---
text: A & B <em>x</em> *bold* _x_ ~x~ [x] | `x` \
markup: <fm-var query="$.secret">cached</fm-var>
secret: hidden
---

Text: <fm-var query="$.text">A &amp; B &lt;em&gt;x&lt;/em&gt; &#42;bold&#42; &#95;x&#95; &#126;x&#126; &#91;x&#93; &#124; &#96;x&#96; &#92;</fm-var>.

Nested-looking value: <fm-var query="$.markup">&lt;fm-var query="$.secret"&gt;cached&lt;/fm-var&gt;</fm-var>.
