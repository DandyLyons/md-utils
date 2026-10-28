# Find matching documents

`query` returns documents' paths, complete frontmatter, or a count. JSONPath
selects values to test, not fragments to return. Retrieve document bodies or
sections separately from a returned path.

```bash
md-utils query notes/ --key Status --equals 'Read'
md-utils query notes/ --json-path '$.authors[*].name' --equals 'Daniel'
md-utils query notes/ --key rating --vtype integer --greater-than-or-equal 3 --less-than 5
md-utils query notes/ --missing-key Status --output frontmatter --oformat json
md-utils query notes/ --key Created --vformat DateTime --same-day '2026-10-28' --timezone UTC
md-utils query notes/ --is-type Article
md-utils query notes/ --in-rule published
md-utils query rel out --help
```

Keys are literal and case-sensitive. String **values** are case-insensitive by
default; `--case-sensitive` opts into exact case. `--key` and `--json-path` are
exclusive. Quote JSONPath expressions. Supported JSONPath syntax comprises
members, quoted members, array indices and wildcards; filters, descendants,
unions and slices are rejected.

One condition per invocation; a lower and upper bound is one range. Bounds must
match the same value. `--match any|all` defaults to any; both require a nonempty
selection. `--exists`/`--missing` test the selection itself and reject `--match`.
Null is present and is tested with `--is-null`. `--contains` tests immediate array
membership. Missing values and incompatible kinds do not satisfy `--not-equals`.

`--value-type`/`--vtype`: string (default), boolean, integer, number, null, array,
object. JSON operands encode arrays/objects. Integers and integral floats compare
numerically; strings and booleans are never coerced. `--value-format`/`--vformat`
accepts Date, LocalTime, DateTime, UUID, Wikilink and their existing full format
names. A format requires string operand encoding; compatible native temporal
values can still be compared without declaring them string-typed.

Dates remain calendar dates. `--same-day|--same-week|--same-month|--same-year`
take a reference date. `--before`/`--after` compare calendar dates with a date
reference, or instants with a timestamp reference. `--date-mode timezone|written`
defaults to timezone; `--timezone local` resolves once to the device zone.
`--week-start sunday|monday` defaults to Sunday. Ambiguous/nonexistent local
datetimes are unknown when an instant is required. See the full
[comparison contract](https://github.com/DandyLyons/md-utils/blob/main/docs/query-design.md).

`--output paths|frontmatter|count` defaults to paths. `--output-format`/`--oformat`
accepts text, json, json-pretty. JSON includes invocation, effective query, scope,
execution, summary, results and diagnostics. Frontmatter results separate
`frontMatter` entries (`path`, `frontmatter`, `valueMetadata`) from
`noFrontMatter`, `emptyFrontMatter`, and `unavailable`. Typed metadata preserves
native timestamps and non-finite numbers. It never overwrites an authored `$path`.

`--limit 20` limits returned lists, not evaluation; 0 returns all. Counts remain
complete. Results are ordered by path, not date. For “latest five,” request all
candidate frontmatter with `--limit 0`, verify completion, normalize the relevant
dates, then sort descending and take five. There is no built-in date sort/top-N
option. See [the latest-sermon investigation](discovery-workflows.md#7-find-the-latest-five-sermon-notes)
for the complete survey → query → inspect workflow.

Use `--contains` for an array tag; `--equals` tests a value in the chosen domain.
A metadata property named `type` is distinct from `--is-type` conformance to a
configured mdtype. V1 accepts one condition (or one paired range); separate tag
and date queries can be intersected by their returned paths.

`--diagnostic-limit 100` caps diagnostic entries only; omissions alone
never fail a query. `--print0` emits exact NUL-separated paths and requires text
path output. Progress and warnings use stderr; `--no-progress` suppresses delayed
“Please be patient” feedback.
Human text uses the shared CLI terminal colors; JSON and NUL path output remain
unstyled. Existing terminal detection and color environment conventions apply.

Scope follows survey: files/folders, `--project-root`, repeatable `--exclude`,
`--files-from`/`--files-from0`, `--markdown-only`, `--no-recursive`, `--max-files`.
File-list paths are project-root-relative; CLI paths are working-directory-relative.
Hidden entries and symlinks are skipped. An existing index may be refreshed;
`--no-index` bypasses it. `--index-only`/`--indexed-only` uses published evidence
without source/config reads or fallback; type/rule conditions are unsupported
in this mode. Old indices lacking typed query evidence report incompleteness.

No matches succeeds. Malformed/unreadable/required unavailable evidence preserves
confirmed matches but exits nonzero; inspect JSON `complete`, `summary`, and
`diagnostics`. Usage errors fail before scanning. Query does not repair files.
