# Rendering Markdown with Knap

Generate Markdown with [Knap](https://knap.md), executed by SwiftKnap. Supply
structured facts and a reusable body template; md-utils validates the input and
assembled document before writing it.

## Render a document

Save `report.json`:

```json
{
  "frontmatter": {"title": "Weekly report", "tags": ["work"]},
  "data": {"summary": "Completed the migration", "items": ["CLI", "Server"]}
}
```

Save `report.knap`:

```text
{{ frontmatter.title | h1 }}

{{ data.summary }}

{{ data.items | list }}
```

```console
md-utils template render --template ./report.knap --data ./report.json --output ./report.md
```

Omit `--output` for stdout. Warnings go to stderr. Optional
`--schema ./report.schema.json` validates the entire envelope without adding defaults.

## Language

Use [Knap variables](https://knap.md/variables), [logic](https://knap.md/logic), and
[filters](https://knap.md/filters). For example:

```text
{% if data.items %}{% for item in data.items %}- {{ item | bold }}
{% endfor %}{% else %}No items.
{% endif %}
```

`{{ data.title ?? "Untitled" }}` uses Knap truthiness: missing, null, zero, false,
empty strings, and empty arrays use the fallback. Objects are true even when empty.
Standard `list`, `table`, `h1`, and `bold` filters handle Markdown formatting.
DOM-dependent filters and custom host integrations are not installed.

`data` is required and accepts any JSON value. Optional `frontmatter` must be an
object. Its values are serialized as YAML, not interpolated into YAML source.
Leave frontmatter delimiters out of body templates. Use arrays for ordered reports.
Supply integers outside ±9,007,199,254,740,991 as strings.

Knap is the sole language. There is no old-template compatibility or translation.

## Library

```swift
let renderer = MarkdownTemplateRenderer()
let result = try await renderer.render(
  template: "{{ frontmatter.title | h1 }}\n{{ data | list }}",
  input: MarkdownTemplateInput(
    frontmatter: ["title": .string("Tasks")],
    data: .array([.string("Write"), .string("Review")]),
  ),
)
// result.source, result.document, and result.warnings
```

The shared engine is reused across renders. SwiftKnap owns execution and platform
differences. Errors preserve stage and upstream diagnostics; warnings do not fail
rendering. Library callers can set byte guardrails and SwiftKnap render limits.
These are not a wall-clock deadline or an execution sandbox.

Server creation shares this renderer with administrator-configured templates.
Identity, rule/type validation, and persistence belong to the mutation service.
Updates never rerender a creation template.
