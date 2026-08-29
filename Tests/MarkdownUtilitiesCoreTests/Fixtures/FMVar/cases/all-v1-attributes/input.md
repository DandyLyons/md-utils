---
title: Example
items: [one, two]
published: 2026-08-29T18:29:31Z
---
<fm-format for="date datetime timestamp array" locale="en-US" format="conjunction" list-style="long" calendar="gregory" numbering-system="latn" time-zone="UTC" hour-cycle="h23" hour12="false" date-style="long" time-style="medium" weekday="long" era="short" year="numeric" month="long" day="2-digit" day-period="long" hour="2-digit" minute="2-digit" second="2-digit" fractional-second-digits="3" time-zone-name="short" format-matcher="basic"></fm-format>
<fm-var src="self" key="published" default="Unknown" type="timestamp" format="iso" locale="en-US">2026-08-29T18:29:31Z</fm-var>
<fm-list src="self" key="items" item-type="string" format="conjunction" locale="en-US" list-style="long">one and two</fm-list>
