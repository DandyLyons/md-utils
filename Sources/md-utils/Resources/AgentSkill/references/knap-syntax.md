# Knap syntax cheatsheet

Read this when writing or debugging Knap templates. For type/rule setup, JSON
input, destination selection, preview and creation, start with
[Templates and file creation](templates.md). This reference covers the language
and standard filter families available through md-utils' SwiftKnap integration.

Authoritative references: [Knap](https://knap.md/),
[Variables](https://knap.md/variables), [Logic](https://knap.md/logic),
[Filters](https://knap.md/filters), [Playground](https://knap.md/playground).
md-utils currently pins SwiftKnap with bundled Knap 0.6.0; website examples may
advance independently. Verify a template with the installed `md-utils template
render` before relying on newer syntax. No separate Knap CLI is needed.

Contents: [expressions](#expressions-and-values), [filters](#filter-calls),
[conditions](#conditions-and-operators), [loops](#loops), [assignments](#local-assignments),
[comments](#comments-and-whitespace), [YAML](#frontmatter-and-yaml),
[filter reference](#standard-filter-reference), [boundaries](#md-utils-boundaries).

## Expressions and values

Ordinary Markdown is emitted as written. `{{ expression }}` inserts a value;
`{% tag %}` controls rendering; `{# comment #}` is removed.

| Form | Example | Meaning |
| --- | --- | --- |
| Named input | `{{ title }}` | Reads the top-level JSON property. |
| Nested object | `{{ author.name }}` | Reads a nested own property. |
| Array element | `{{ authors[0].name }}` | Array positions start at zero. |
| Quoted key | `{{ metadata["article:section"] }}` | Useful for punctuation or non-identifier keys. |
| Dynamic subscript | `{{ timestamps[loop.index0] }}` | Reads an index supplied by another expression. |
| Human-readable name | `{{ First name \| trim }}` | Output expressions support variable names containing spaces. |
| Literal | `{{ "Draft" }}`, `{{ 42 }}`, `{{ true }}`, `{{ null }}` | String, number, boolean and null values. |
| Filter chain | `{{ title \| trim \| upper }}` | Transforms left to right. |
| Fallback | `{{ subtitle ?? title ?? "Untitled" }}` | Chooses the first truthy value. |

Prefer simple identifier keys for data reused in control expressions; use quoted
brackets for awkward nested keys. Arrays and objects remain typed during
processing; raw output is not a human-friendly list/table or YAML serializer.
Choose a rendering filter explicitly. Use arrays for ordered data; do not rely
on input object key order.

## Filter calls

Filters follow a pipe; parameters follow a colon. Parameter grammar is
filter-specific: some accept a quoted string, a bare option, multiple colon
arguments, comma arguments or a tuple. Check the linked filter's reference.

```knap
{{ title | trim | upper }}
{{ title | replace:"old":"new" }}
{{ tags | join:", " }}
{{ tasks | list:task }}
{{ people | sort:("name", "desc") | map:"name" | join:", " }}
{{ summary | truncate:(80, "…") }}
{{ rows | slice:0,2 | table }}
```

Do not assume JavaScript method calls or another engine's filter names work.
Unknown filters and invalid arguments produce diagnostics. Markdown formatting
filters can also transform string elements within collections; for example
`{{ tags | bold | join:", " }}` emphasizes each tag before joining.

## Conditions and operators

[Conditional reference](https://knap.md/logic/if): the first satisfied branch wins.
Use `elseif`, and close the block with `endif`.

```knap
{% if status == "published" %}
Published
{% elseif status == "draft" %}
Draft for review
{% else %}
Status unknown
{% endif %}
```

| Operator | Example | Use |
| --- | --- | --- |
| `==`, `!=` | `status == "draft"` | Equality / inequality. |
| `>`, `<`, `>=`, `<=` | `rating >= 4` | Ordered comparisons. |
| `contains` | `tags contains "reference"` | Array membership or substring. |
| `and`, `&&` | `author and published` | Both truthy. |
| `or`, `\|\|` | `draft or archived` | Either truthy. |
| `not`, `!` | `not hidden` | Negation. |
| Parentheses | `(featured or premium) and published` | Explicit grouping. |
| `??` | `subtitle ?? "No subtitle"` | Truthy fallback, also allowed in output. |

Falsy values are missing/undefined, null, false, zero, empty string and empty
array. Empty objects are truthy. `??` is **not** a null-only coalescer: `0` and
`false` also trigger a fallback. Filters bind before `??`.
To retain a meaningful zero, branch explicitly:

```knap
{% if count == 0 %}
No items (0)
{% else %}
{{ count }} items
{% endif %}
```

Put optional sections inside conditions. Keep sections required by an MD type
present in every relevant branch; a condition can otherwise produce a
nonconforming document even when the template renders successfully.

## Loops

[Loop reference](https://knap.md/logic/for): iterate arrays with `for` / `endfor`.
Use `if` inside the loop for conditional entries, or filter the array first.

```knap
{% for person in people %}
{% if person.active %}
{{ loop.index }}. {{ person.name }} — {{ person.role }}
{% endif %}
{% endfor %}
```

| Loop value | Meaning |
| --- | --- |
| `loop.index` | Position starting at 1. |
| `loop.index0` | Position starting at 0. |
| `loop.first`, `loop.last` | Whether this is the first/last iteration. |
| `loop.length` | Number of entries. |
| `person_index` | Legacy zero-based index named after the iterator (`person` here). |

Loops and conditions can nest; loop metadata belongs to the active loop.
Iterations have newline separation; blank lines inside a loop can add paragraph
spacing. Inspect actual rendered Markdown rather than assuming tags remove all
surrounding whitespace. Prefer `list`, `table`, or `join` for simple collections.
For object iteration, convert it with `object:"entries"`, `object:"keys"`, or
`object:"values"` first; see [object](https://knap.md/filters/object).

## Local assignments

[Assignment reference](https://knap.md/logic/set): `set` names an expression and
emits no content. Later assignments can replace the value; there is no end tag.
Values assigned in a loop are local to that iteration.

```knap
{% set display_title = title | trim %}
{% set active_people = people | where:("active", true) %}
{{ display_title | h1 }}
{{ active_people | map:"name" | list }}
```

Assignments change template variables only. A `set filename = ...` does not
choose the file path for `rules new`; `--filename-data` reads the prepared JSON
before rendering.

## Comments and whitespace

`{# ... #}` can span lines and is omitted from output; embedded expressions
are not evaluated. Comments end at the first `#}` and cannot nest. Unclosed
comments fail. Surrounding whitespace stays, so a comment-only line can leave
a blank line.

```knap
{# Template authors: keep this heading aligned with the type contract. #}
## Review
{{ review }}
```

`{{ note | comment }}` instead emits a comment in the resulting Markdown.
md-utils preserves surrounding output whitespace (`trimOutput: false`). It does
not add another engine's whitespace-trimming syntax. Use ordinary blank lines
for paragraphs, and `indent` / `hard_break` when deliberately formatting content.

## Frontmatter and YAML

In default document mode, the template owns frontmatter delimiters and body.
Use [yaml](https://knap.md/filters/yaml) to serialize a value or
[yaml_property](https://knap.md/filters/yaml_property) for a complete key/value
entry. The latter handles scalar and collection values without manually deciding
which ones require quotes or indentation.

```knap
---
{{ title | yaml_property:"title" }}
{{ tags | yaml_property:"tags" }}
{{ published | yaml_property:"published" }}
---
{{ title | h1 }}
```

For a whole supplied metadata object, use `{{ metadata | yaml }}` between
delimiters. Avoid raw string interpolation into YAML. A value containing colons,
quotes, newlines, or `false` as text must retain its type. A YAML serialization
filter does not establish that the resulting document satisfies an MD type.

In explicit body mode, md-utils serializes the separate `frontmatter` object and
Knap renders only the body; use `{{ frontmatter.title }}` and `{{ data.summary }}`.
Do not include delimiter lines in a body template. See
[the body-mode scenario](templates.md#let-md-utils-serialize-frontmatter-separately).
Knap has no TOML serializer in this integration.

## Standard filter reference

These are the bundled standard filter families, including less common helpers.
The examples below show practical call forms; use the
[upstream filter index](https://knap.md/filters) for every parameter and alias.
HTML filters requiring a DOM (`html_to_json`, `remove_html`) are not registered
in md-utils.

### Markdown and links

| Filters | Example / purpose |
| --- | --- |
| `h1`, `h2`, `h3`, `h4`, `h5`, `h6` | `{{ title \| h2 }}`; heading level. |
| `bold`, `italic`, `strike`, `highlight` | `{{ title \| bold }}`; inline emphasis. |
| `blockquote`, `callout` | `{{ summary \| blockquote }}`, `{{ summary \| callout:info }}`. |
| `code`, `code_block` | `{{ source \| code_block:"swift" }}`; fenced code, or `code` for inline/language-specific formatting. |
| `math`, `math_block` | Inline or block math notation. |
| `hr`, `hard_break` | `{{ footer \| hr:before }}`; horizontal rules or hard line breaks. |
| `escape_md`, `comment` | Literal Markdown punctuation or output comments. |
| `link`, `image` | Markdown links/images from URL data; inspect the filter's supported labels and object shapes. |
| `wikilink`, `embed` | `{{ related \| wikilink }}`; wiki references or embedded references. |
| `footnote`, `fragment_link` | Footnote definitions or source links with text-fragment anchors. |
| `list` | `{{ tasks \| list:task }}`; options `bullet`, `numbered`, `task`, `numbered-task`. |
| `table`, `table_pretty` | Arrays/objects as compact/padded Markdown tables. |
| `yaml`, `yaml_property` | Typed YAML values / complete frontmatter entries. |

Useful references: [list](https://knap.md/filters/list),
[table](https://knap.md/filters/table), [link](https://knap.md/filters/link),
[wikilink](https://knap.md/filters/wikilink),
[escape_md](https://knap.md/filters/escape_md).

### Text

| Filters | Example / purpose |
| --- | --- |
| `trim`, `upper`, `lower`, `capitalize`, `title` | Whitespace/case, e.g. `{{ title \| trim \| upper }}`. |
| `camel`, `pascal`, `snake`, `kebab`, `uncamel` | Naming styles and splitting camel case. |
| `replace` | `{{ title \| replace:"old":"new" }}`; replacement/regex options are filter-specific. |
| `truncate`, `truncatewords` | `{{ summary \| truncate:(80, "…") }}` or word-count limits. |
| `indent` | `{{ content \| indent:2 }}`; indent nonempty lines. |
| `safe_name` | `{{ title \| safe_name:windows }}`; cleans text, does not set the output filename. |
| `encode_uri`, `decode_uri`, `unescape` | URI encoding/decoding and escaped text. |

References: [replace](https://knap.md/filters/replace),
[truncate](https://knap.md/filters/truncate),
[safe_name](https://knap.md/filters/safe_name).

### Collections and structured data

| Filters | Example / purpose |
| --- | --- |
| `first`, `last`, `length` | First/last entry or string/collection size. |
| `join`, `split` | `{{ tags \| join:", " }}`, `{{ csv_text \| split:"," }}`. |
| `compact`, `unique`, `reverse` | Remove null/empty-string entries, deduplicate, reverse. |
| `slice`, `nth` | `{{ rows \| slice:0,2 }}`; ranges or nth-pattern selection. |
| `sort` | `{{ people \| sort:("name", "desc") }}`; by values or object property. |
| `where` | `{{ people \| where:("active", true) }}`; exact property match. |
| `map` | `{{ people \| map:"name" }}` or `map:person => person.name`. |
| `merge` | Combine values into an array. |
| `object` | `{{ metadata \| object:"keys" }}`; keys, values or entries. |
| `parse_json` | Parse a string containing JSON into a typed value. |
| `sum` | `{{ expenses \| sum:"amount" }}`; add values/property values. |
| `template` | `{{ people \| template:"${name}: ${role}" \| list }}`; small per-item string template. |

`map` additionally supports restricted arrow expressions for constructing objects
and interpolating strings; it cannot call built-in filters inside the arrow.
Chain filters afterward. `${property}` inside the `template` filter is different
from the main `{{ expression }}` syntax. These are not arbitrary JavaScript
execution facilities. References: [map](https://knap.md/filters/map),
[template](https://knap.md/filters/template), [where](https://knap.md/filters/where),
[sort](https://knap.md/filters/sort), [object](https://knap.md/filters/object).

### Dates and numbers

| Filters | Example / purpose |
| --- | --- |
| `date` | `{{ created \| date:"YYYY-MM-DD" }}`; date formatting. |
| `date_modify` | `{{ created \| date_modify:"+1 day" \| date:"YYYY-MM-DD" }}`. |
| `duration` | Duration formatting from seconds or ISO 8601 duration values. |
| `calc` | `{{ price \| calc:"*2" }}`; simple arithmetic through a filter. |
| `round` | `{{ rating \| round:2 }}`; decimal places. |
| `number_format` | Numeric presentation with separators/optional decimal precision. |

Supply explicit dates in JSON when repeatability matters. Date/time/locale
filters can depend on runtime environment. References:
[date](https://knap.md/filters/date), [date_modify](https://knap.md/filters/date_modify),
[calc](https://knap.md/filters/calc), [number_format](https://knap.md/filters/number_format).

### Markup cleanup

`remove_attr`, `remove_tags`, `replace_tags`, `strip_attr`, `strip_tags` process
HTML text; `strip_md` (alias `stripmd`) removes Markdown formatting. Consult
[the cleanup index](https://knap.md/filters#html-cleanup) for allowed parameters.
Do not confuse these standard string filters with optional DOM-based HTML filters.

## md-utils boundaries

- Document mode expects a JSON object of named variables. Body mode expects
  `data` plus optional object `frontmatter`; it does not add document-mode aliases.
- No implicit `now`, filename, current document, Obsidian, browser or network
  variables are supplied. Pass required facts explicitly in JSON.
- Knap has no legacy-template translation in md-utils. Do not borrow Liquid/Jinja
  includes, macros, `elsif`, or host-specific variables without checking support.
- No custom filters or DOM integrations are installed. Rendering cannot read
  another file or fetch a URL to supply missing values.
- Integers outside ±9,007,199,254,740,991 must be strings; non-finite numbers fail.
  Templates, JSON input and output also have byte and engine execution limits.
- Input-schema defaults run before Knap. Schema defaults preserve supplied values;
  `??` is a rendering fallback with different truthiness rules.
- Rendering success is separate from type/rule conformance. Always finish the
  [creation workflow](templates.md#6-check-definitions-preview-create-and-validate)
  when the saved file must follow project contracts.
