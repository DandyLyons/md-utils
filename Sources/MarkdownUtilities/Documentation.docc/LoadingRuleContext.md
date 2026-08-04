# Loading Filesystem Rule Context

Acquire native record metadata and schema resources before portable rule evaluation.

## Records

``MarkdownRecordFileAdapter`` reads canonical Markdown content, constructs a project-relative `MarkdownRecordPath`, and records the filesystem modification timestamp in `MarkdownRecordContext.modificationDate`. This keeps filesystem access in `MarkdownUtilities` while allowing `MarkdownUtilitiesCore` to evaluate modification predicates deterministically from explicit input.

## Schemas

Use ``FileMarkdownSchemaResourceProvider`` with `MarkdownRuleCompiler` when rule checks refer to native JSON Schema files. Relative schema references resolve from the definition's source URL and are loaded during compilation. Missing or invalid resources therefore fail startup instead of appearing only when a matching file is encountered.

```swift
let record = try MarkdownRecordFileAdapter.read(file, projectRoot: projectRoot)
let compiler = MarkdownRuleCompiler(
  capabilities: [.modificationDate],
  schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: projectRoot)
)
```
