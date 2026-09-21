# Rendering Markdown with Stencil Templating Language

Turn JSON facts into a Markdown document with reusable body layout and valid YAML frontmatter.

## Overview

[Stencil](https://github.com/stencilproject/stencil) is a [template language](https://en.wikipedia.org/wiki/Template_processor) similar to [Django](https://docs.djangoproject.com/en/6.1/ref/templates/language/). You define a template with placeholders in Stencil syntax. Then you provide data to fill those placeholders, then the template system injects your data into the template to produce the final document.

### Body vs. Frontmatter in Templates
md-utils uses Stencil syntax for the **body only**. Supply frontmatter as a JSON
object; md-utils will convert it to valid YAML frontmatter. You do not
write YAML or escape YAML values in your template.

This guide covers the supported md-utils workflow. For the full language, see
the official [Stencil documentation](https://stencil.fuller.li/en/latest/),
[syntax overview](https://stencil.fuller.li/en/latest/templates.html), and
[built-in tags and filters](https://stencil.fuller.li/en/latest/builtins.html).
Examples for other Stencil applications may assume loaders, custom filters, or
Swift objects that md-utils does not provide.

## Render your first document

Save this as `report.json`:

```json
{
  "frontmatter": {
    "title": "Sales: September",
    "published": false,
    "tags": ["sales", "monthly"]
  },
  "data": {
    "summary": "Revenue increased.",
    "regions": [
      {"name": "North", "revenue": 24000},
      {"name": "South", "revenue": 18000}
    ]
  }
}
```

Save this body template as `report.stencil`:

```stencil
# {{ frontmatter.title }}

{{ data.summary }}

{% for region in data.regions %}- {{ region.name }}: {{ region.revenue }}
{% empty %}No regional results.
{% endfor %}
```

Render to the terminal, or write a Markdown file:

```console
md-utils template render --template ./report.stencil --data ./report.json
md-utils template render --template ./report.stencil --data ./report.json --output ./report.md
```

When working from the repository, use `swift run md-utils` in place of `md-utils`.
Output includes YAML such as `title: 'Sales: September'`, followed by the rendered
heading, summary, and list. Yams chooses the quoting style and sorts metadata keys.

Output filenames must use `.md` or `.markdown`, case-insensitively. Parent
directories must already exist. Successful output replaces an existing file
atomically; validation/rendering failures leave it untouched. Without `--output`,
stdout receives the Markdown bytes without an added trailing newline.

## Understand the input envelope

| Field | Meaning |
| --- | --- |
| `data` | Required; any JSON value, including an object, array, scalar, or null. Access it as `data` in Stencil. |
| `frontmatter` | Optional object; its values are accessible as `frontmatter.title`, for example. |

Omit `frontmatter` for a body-only document. An empty object `{}` generates an
empty YAML mapping. `"frontmatter": null` is invalid, but null values **inside**
the object are valid. Numbers, booleans, nested objects, arrays, and strings keep
their structured types in YAML. JSON input is the only CLI input format currently
supported; YAML/TOML/CSV input files are not accepted.

Input keys are not promoted to the template's top level: use `data.summary`, not
`summary`. With a root array, write `{% for item in data %}`. No application-specific
Swift objects, functions, or custom context variables are exposed.

## Stencil basics

### Insert values and comments

```stencil
# {{ frontmatter.title }}
Owner: {{ data.owner.name }}
{# This authoring note is not included in the document. #}
```

Ordinary Markdown remains literal text. `{{ ... }}` inserts a value, `{% ... %}`
controls rendering, and `{# ... #}` is a template comment.

### Choose conditional content

```stencil
{% if data.approved %}Approved.
{% elif data.pending %}Awaiting review.
{% else %}Not approved.
{% endif %}
```

Stencil supplies comparisons and `and`, `or`, and `not`. A condition is a truthiness
test, not a schema check. For example, empty strings and arrays are false; a
nonempty string containing `"false"` is not the boolean `false`. Use actual JSON
booleans and validate required types with a schema.

### Repeat content and handle empty arrays

```stencil
{% for item in data.items %}- {{ item.name }}
{% empty %}No items available.
{% endfor %}
```

**`{% empty %}` is supported.** An empty array `[]` renders the empty branch. A
missing collection also reaches that branch. Arrays retain their input order.
A null entry inside an array is retained: `["A", null, "B"]` still has three
entries, even though printing the null entry produces no text. It is not an empty
array and does not trigger the empty branch.

### Apply built-in filters

```stencil
{{ data.owner|uppercase }}
{{ data.tags|join:", " }}
{{ data.missingLabel|default:"Untitled" }}
```

Filters use Stencil's existing pipe syntax. md-utils does not register extra
Markdown or serialization filters. With the current Stencil version, `default`
supplies a fallback for a missing lookup, but not for a present empty string.
Because md-utils presents null as an empty string, null does not trigger that
fallback either. Use an explicit `if`/`else` when you want one fallback for all
false-like values.

### Control whitespace in lists and tables

md-utils uses Stencil's default no-trimming mode. Tag lines can therefore leave
blank lines. Place loop tags next to the text they govern when exact layout matters:

```stencil
| Region | Revenue |
| --- | ---: |
{% for region in data.regions %}| {{ region.name }} | {{ region.revenue }} |
{% empty %}| No regions | 0 |
{% endfor %}
```

Stencil also provides explicit whitespace-control markers; see its
[whitespace reference](https://stencil.fuller.li/en/latest/templates.html#whitespace-control).
Preview output after trimming changes: removing a newline can join table rows or
list items together.

## Differences specific to md-utils

### Frontmatter belongs to the input, not the template

Do not start the body template with a `---` or `+++` delimiter line. md-utils
checks both template source and rendered body, including delimiters introduced
through data. A leading `---` horizontal rule is also reserved; use `***` instead.
TOML output is not yet supported by this feature.

### Missing and null body values are permissive

| Value | Direct body interpolation | Condition |
| --- | --- | --- |
| Missing field | Empty text | False |
| JSON null | Empty text | False |
| Empty string | Empty text | False |
| Empty array | Prefer a loop; `{% empty %}` handles it | False |

md-utils recursively converts null to an empty string **only in Stencil's
presentation copy**. This avoids Foundation null appearing as `<null>` and truthy
as it can in other Swift/Stencil integrations. Dictionary keys and array positions
remain present. Filters and comparisons also see that empty-string presentation.
Schema validation and YAML serialization continue to see actual null values.

There is no strict missing-variable mode yet. A misspelled field may silently
render empty. Use a schema to require input fields, and review template output;
a schema does not detect every typo in template expressions.

### Body interpolation does not escape Markdown

Yams protects the syntax of generated frontmatter. Body values are inserted as
text without context-aware Markdown escaping. A pipe in a table cell or brackets
in a link can change the output structure. Prepare body values for their intended
context before rendering. Parsing the final Markdown is not HTML sanitization or
a guarantee that every table, list, or link expresses the intended structure.

### Templates are self-contained

No template loader is configured. Executed `{% include %}` and `{% extends %}`
operations that request another template fail; there are no search directories
or include flags. Custom filters from other Stencil applications are unavailable.

### Output is Markdown only

Non-Markdown generation is explicitly unsupported. A `.swift` or `.py` output
path is rejected instead of selecting a comment wrapper. Future embedded-metadata
integration depends on [issue #134](https://github.com/DandyLyons/md-utils/issues/134).
Shell redirection does not change stdout's Markdown representation.

## Validate input before rendering

Save an optional schema as `report.schema.json`:

```json
{
  "type": "object",
  "required": ["frontmatter", "data"],
  "properties": {
    "frontmatter": {
      "type": "object",
      "required": ["title"],
      "properties": {"title": {"type": "string"}}
    },
    "data": {
      "type": "object",
      "required": ["summary", "regions"],
      "properties": {
        "summary": {"type": "string"},
        "regions": {"type": "array"}
      }
    }
  }
}
```

```console
md-utils template render --template ./report.stencil --data ./report.json --schema ./report.schema.json --output ./report.md
```

The schema validates the complete envelope, not just `data` or `frontmatter`.
It does not populate defaults, compute values, or map fields. Validation occurs
before Stencil runs; the assembled document is parsed before output is written.

## Use the Swift API

```swift
import MarkdownUtilitiesCore
import MarkdownUtilitiesTemplates

let input = MarkdownTemplateInput(
  frontmatter: ["title": .string("Sales: September")],
  data: .object(["summary": .string("Revenue increased.")])
)
let result = try await MarkdownTemplateRenderer().render(
  template: "# {{ frontmatter.title }}\n\n{{ data.summary }}\n",
  input: input
)
print(result.source, terminator: "")
// result.document is the MarkdownDocument parsed from result.source.
```

The library performs no file writes. Callers control persistence; future server
integration must restrict template configuration to administrators.

## Limits and troubleshooting

Defaults are 16 MiB template source, 64 MiB JSON input, and 64 MiB assembled
output. Library callers can supply ``MarkdownTemplateLimits``. Output limits are
checked after rendering/serialization: these are byte guardrails, not hard bounds
on memory, loop iterations, recursion, or elapsed time. Keep workloads appropriate
for your hardware.

| Symptom | What to check |
| --- | --- |
| Unexpected empty text | Check `data.`/`frontmatter.` paths, nulls, and missing fields. |
| Include or inheritance error | Use one self-contained template. |
| Unknown filter | Use a built-in Stencil filter; app-specific filters are not installed. |
| Frontmatter delimiter error | Remove metadata fences from the body template and input body text. |
| Unsupported output filename | Choose `.md` or `.markdown`, or omit output for Markdown stdout. |
| Broken table layout | Check literal pipes, newlines in values, and loop whitespace. |

For repeatable reports, supply dates in input and avoid time-dependent tags such
as `now`, whose availability also differs across Stencil platforms. Full
byte-identical output across arbitrary Stencil features is not promised.
Batch rendering, formatting helpers, TOML generation, and includes tooling remain
future features.
