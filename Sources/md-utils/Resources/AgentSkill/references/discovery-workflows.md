# Discover a collection through focused investigations

Use `survey` to learn a folder's patterns, `query` to select matching documents,
then `explore` to read relevant sections. Let each result choose the next question.
Run the relevant follow-ups below, rather than executing every command for every task.

Examples assume the current directory is the collection's project root (where
`.md-utils/` lives). Replace `notes/`, filenames, property keys, and contract names
with ones returned by your investigation. Property and type names are case-sensitive.
Query string values are case-insensitive by default; use `--case-sensitive` when
the distinction matters. Survey uses `--format`; query uses `--output-format`
(alias `--oformat`). These flags are not interchangeable.

| Question | Start with | What it gives you |
| --- | --- | --- |
| What patterns matter across these files? | `survey` | Coverage, common metadata, relevant contracts, and next-step hints. |
| Which documents match a value, date, type, or rule? | `query` | Paths, frontmatter, or counts with explicit completion and provenance. |
| Where is the useful content in this document? | `explore --tree` | Heading structure and source lines, without dumping the body. |
| What does a particular finding mean? | Focused `survey`, `fm`, `types`, `rules`, or `rel` commands | Values, definitions, selection explanations, and individual-file evidence. |

## 1. “I have an unfamiliar folder. Where do I start?”

```sh
md-utils survey notes/
```

Read the coverage, common keys, relevant rule/type names, and printed hints.
Choose the next investigation from those findings: a frequent unfamiliar key
leads to scenario 2; a contract name to scenario 3 or 4; a representative long
document to scenario 5. There is usually no need to request every metric.
For a broader property inventory, use `md-utils survey keys notes/`.

For agents, `--format json` returns a compact report with counts, completion,
bounded evidence, and executable hint arguments. `--format json-pretty` has the
same data with indentation. Keep unavailable evidence distinct from zero findings.

## 2. “What does this frontmatter property mean, and what are its conventions?”

```sh
md-utils survey key Status notes/
md-utils survey values Status notes/
md-utils fm has --key Status notes/ --include-non-md
```

`key` reveals prevalence, missing/null values, and value kinds. `values` reveals
the informal vocabulary and its distribution. In `fm has` output, choose a file
marked `true`; null also counts as present. Then inspect that file's actual value:

```sh
md-utils fm get --key Status notes/example.md
```

Use scenario 5 to read relevant prose, or inspect the governing type/rule through
scenarios 3–4. Frequency establishes convention, not domain meaning or a required
contract. Use the single investigation example printed by `survey values` when
you need frontmatter for files containing one particular value.

```sh
md-utils query notes/ --key Status --equals 'Read' --case-sensitive
md-utils query notes/ --key Status --equals 'Read' --output frontmatter --oformat json
```

For an array such as `tags`, use `--contains sermonNotes` rather than scalar
`--equals`. `survey values tags sermons/ --elements` discovers the actual member
spelling. For nested arrays, select nodes with a quoted JSONPath such as
`--json-path '$.authors[*].name' --equals 'Daniel'`. Results still identify whole
documents. Use `--missing-key Status` to investigate missing metadata separately.

## 3. “Which types are used by this file or folder?”

```sh
md-utils survey types notes/
md-utils types describe Book
md-utils types verify notes/example.md --include-confirmed
```

Choose `Book` from the inventory. Read its relevance label: a definition merely
present in the project is different from one referenced by a matching rule.
`describe` explains its contract; `verify` checks the file's explicit type hints.
Use scenario 4 to establish which types a rule actually requires for that file.
No type hints does not mean that no rules apply.

If you instead want to test whether files structurally fit a candidate type,
opt into a targeted assessment:

```sh
md-utils survey type-matches notes/ --type Book
md-utils query notes/ --is-type Book
```

If the report lists `notes/draft.md` as a failing example, inspect its diagnostics:

```sh
md-utils types check Book notes/draft.md
```

Structural conformance does not establish intended usage. Start with a named type
and narrow folder before trying every type. Survey summarizes conformance;
query returns the matching documents. A frontmatter property named `type` may
contain informal labels or wikilinks: it is not automatically a loaded mdtype.

## 4. “Which rules govern this file or folder, and why?”

```sh
md-utils survey rules notes/
md-utils rules matching notes/example.md --explain
md-utils rules describe books
md-utils rules files-matching books
md-utils query notes/ --in-rule books
```

The survey identifies relevant rules. `matching` explains the specific file's
selection; use a returned rule name such as `books` in `describe` to inspect its
requirements and in `files-matching` to see its population. Named-rule commands
can cover files outside the surveyed folder. Add `--include-non-md` to the rule
matching commands when investigating supported non-Markdown hosts.
`query notes/ --in-rule books` restricts the selected population to that folder;
membership does not imply that the documents satisfy the rule's requirements.

If coverage is the question, branch to `survey uncovered notes/` or
`survey overlaps notes/`. Unknown selection is not confirmed non-selection;
overlap can be intentional. If conformance is the question, use
`md-utils rules validate books`, remembering that it checks the rule's full scope.

## 5. “This document is huge. Where is the part I need?”

```sh
md-utils explore notes/example.md --tree
```

Choose a returned heading. If it is `Lifecycle`, read just that section:

```sh
md-utils explore notes/example.md --expand Lifecycle
```

For repeated titles, use the returned heading line with `--expand-line`.
For a large branch, use `--tree-section-title Lifecycle` to inspect its descendants
before expanding them. `--expand-frontmatter` exposes metadata when needed.
`explore` operates on one Markdown file; survey a folder to choose that file first.

## 6. “How do these documents connect, and what link needs investigation?”

```sh
md-utils survey relationships notes/
```

Read link totals, named groups, inside/outside destinations, and coverage limits.
Follow the printed hint to a source with unresolved or unavailable evidence.
For a chosen source, retain detailed provenance for an agent or inspect broken links:

```sh
md-utils rel out notes/example.md --root . --detail evidence --json
md-utils links check notes/example.md --root .
```

The project root defines the destination namespace; selecting `notes/` does not
confine targets to that folder. Current relationship survey sources are Markdown.
Broken-link checks and conformance checks can exit nonzero for findings; inspect
their output. Investigation does not imply permission to repair files.

## 7. “Find the latest five sermon notes.”

First narrow to the sermon folder discovered in the collection. Inspect its
classification and date fields instead of guessing a property name or relying on
filesystem modification times:

```sh
md-utils survey keys sermons/ --top 0 --no-index
md-utils survey values tags sermons/ --elements --no-index
md-utils survey key date sermons/ --no-index
md-utils query sermons/ --key tags --contains sermonNotes --markdown-only --output frontmatter --oformat json --limit 0 --no-index
```

Check `complete`, `summary.unknown`, `summary.omitted`, and `results.unavailable`
before ranking results. Use the sermon date, not the file's edit date. Request
**all matches before sorting**: query orders paths, so `--limit 5` does not mean
“latest five.” Query currently has no date-sort or top-N option. Sort the returned
frontmatter by the chosen date semantics, descending, and take five afterward.
For uniformly validated `YYYY-MM-DD` dates, lexical date sorting works; for mixed
dates/local datetimes/offset timestamps, normalize to a deliberate calendar or
instant policy first. Do not silently rank missing or invalid dates.

Check untagged documents when tags may be incomplete:

```sh
md-utils query sermons/ --missing-key tags --markdown-only --output frontmatter --oformat json --limit 0 --no-index
```

Once the date distribution supplies a useful cutoff, a separate date query can
confirm the candidate window. This example means strictly after September 26:

```sh
md-utils query sermons/ --key date --after '2026-09-26' --markdown-only --output frontmatter --oformat json --limit 0 --no-index
```

This second command selects by date, not by tag: compare its paths with the sermon
candidates. V1 does not combine independent tag and date predicates. Narrowing to
a known sermon folder helps, but series indexes and templates can still live there.
Native YAML dates and date strings can both participate in temporal comparisons;
inspect survey's kind counts before imposing a particular string format.

Finally, report paths and dates, retaining “untitled” when the title is absent.
Use scenario 5 on an individual result only if the user needs its content.

## Keep investigations small and interpretable

- Scope to the smallest useful folder; widen only when the result calls for it.
- Inspect `fileIssues`, incomplete metrics, and printed hints before interpreting
  missing results. `survey coverage notes/` and `survey malformed-fm notes/`
  investigate coverage and parse failures.
- Prefer bounded reports and selected sections. Use `--top 0` or `--limit 0` when
  the question requires complete result lists. These limits affect display, not sampling.
- An existing index can accelerate surveys. `--index-only` is a published snapshot
  view with capability limits; it does not certify current files. Some investigations
  remain expensive even with concise output.

Detailed command references: [Survey](survey.md),
[document queries](query.md),
[document exploration](headings-sections.md),
[frontmatter](frontmatter.md),
[types](types.md),
[rules](rules.md), and
[relationships](relationships.md).
