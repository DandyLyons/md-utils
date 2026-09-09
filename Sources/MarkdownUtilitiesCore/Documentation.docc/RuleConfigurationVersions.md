# Rule Configuration Versions

Normalize supported serialized configurations into one executable model.

## Supported Versions

``MarkdownRuleConfigurationDecoder`` accepts configuration versions `0.1.0` and `0.2.0`. Legacy `schemaRules`, `schema`, and `frontmatterRequired` fields normalize into the same ``MarkdownRuleDefinition`` and ``MarkdownRuleCheck`` values as version `0.2.0` `rules` and `checks`.

Unknown versions, unknown keys, invalid operands, and fields that cannot be represented without changing behavior fail with ``MarkdownRuleConfigurationError``. The versioned decoder never drops an unsupported field. The separate `MarkdownRuleMatchExpression` decoder implements RFC 0002 grouping for standalone rules and programmatic hosts; this does not activate version `0.3.0` in the project configuration decoder. Legacy encoding refuses grouped expressions rather than discarding them.

``MarkdownRuleConfigurationEncoder`` writes either supported version from normalized definitions. Encoding `0.1.0` succeeds only when every definition is representable by the legacy schema-rule shape.

```swift
let configuration = try MarkdownRuleConfigurationDecoder.decode(source)
let registry = try MarkdownRuleCompiler().compile(configuration.rules)
let encoded = try MarkdownRuleConfigurationEncoder.encode(configuration)
```
