# Rule Runtime Capabilities

Separate portable rule semantics from facilities supplied by a host.

## Capability Matrix

| Feature | Core | Native adapter | CLI | Server requirement |
| --- | --- | --- | --- | --- |
| Paths, frontmatter fields, headings, sections, body counts, and wikilinks | Built in | No extra work | Available | Available |
| File modification predicates | Evaluated from ``MarkdownRecordContext/modificationDate`` | Acquires metadata | Available | Host must supply metadata |
| JMESPath frontmatter query | Provider protocol only | Not supplied | Serialized CLI provider | Unsupported unless a provider is supplied |

``MarkdownRuleRuntimeCapability`` makes these requirements explicit. ``MarkdownRuleCompiler`` rejects a definition when its capability is unavailable, before record processing begins.

JMESPath remains outside the portable target. A host supplies ``MarkdownRuleQueryCapabilityProvider`` to validate and evaluate expressions, while Core owns JSON conversion and result truthiness. The CLI serializes access to its JMESPath dependency because that dependency does not currently satisfy the package's strict-concurrency and portability requirements.

Modification dates are explicit record metadata. Core never reads the filesystem; a missing date on a record that reaches a modification predicate produces failed assessment evidence rather than silently treating the predicate as false.
