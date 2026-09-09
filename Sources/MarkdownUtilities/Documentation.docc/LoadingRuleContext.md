# Loading Filesystem Rule Context

Acquire native record metadata and schema resources before portable rule evaluation.

## Records

``MarkdownRecordFileAdapter`` reads canonical Markdown content, constructs a project-relative `MarkdownRecordPath`, and records the filesystem modification timestamp in `MarkdownRecordContext.modificationDate`. This keeps filesystem access in `MarkdownUtilities` while allowing `MarkdownUtilitiesCore` to evaluate modification predicates deterministically from explicit input.

## Standalone rule storage

`MarkdownRuleFileStore(projectRoot:)` provides explicit loading, creation, replacement,
and removal of `.mdrule.json` resources. Discovery is recursive and ordered by source
path, ignores unrelated files, excludes `rules/legacy/`, and reports duplicate names
with both paths. Active symbolic links are rejected. Mutations preserve other rules,
types, and schemas; creation never overwrites an existing file.

`MarkdownRuleFile` validates and round-trips the proposed standalone rule envelope,
including recursive match and type-expression shapes. `typeBindings(for:)` resolves
exact filenames relative to `types/` to the definitions' declared identities. No
recursive basename fallback is performed. File discovery/serialization is separate
from expression evaluation and versioned project loading; these APIs do not activate
config 0.3.0 or change how legacy project configurations are interpreted.

## Schemas

`MarkdownRuleSchemaReferenceMigration.plan` prepares a legacy `schemaDirectory` plus
schema filename for migration without writing files. It returns the project-relative
resource and its equivalent reference from the destination mdtype. It checks resource
existence and project containment, including symlinks and nested external references.
For example, `book.schema.json` in the default directory becomes
`.md-utils/schemas/book.schema.json` relative to the project or
`../schemas/book.schema.json` from a root-level type file. Absolute legacy inputs and
references escaping the project are rejected. This planner is a building block for
the migration writer tracked under the config roadmap.

Use ``FileMarkdownSchemaResourceProvider`` with `MarkdownRuleCompiler` when rule checks refer to native JSON Schema files. Relative schema references resolve from the definition's source URL and are loaded during compilation. Missing or invalid resources therefore fail startup instead of appearing only when a matching file is encountered.

```swift
let record = try MarkdownRecordFileAdapter.read(file, projectRoot: projectRoot)
let compiler = MarkdownRuleCompiler(
  capabilities: [.modificationDate],
  schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: projectRoot)
)
```
