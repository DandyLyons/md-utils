# Record Identity

Derive stable primary identities and collision-safe logical-path fallbacks for collections of Markdown records.

## Identity Policy

`MarkdownRecordIdentityPolicy` selects one primary identity source:

- `existingIdentity` uses the identity supplied by the record store;
- `logicalPath` uses the complete normalized collection-relative path; and
- `frontmatter(path:format:)` reads a nested value from schema-visible user frontmatter.

Logical-path fallback is enabled by default. It provides an unambiguous recovery route for a record whose configured primary identity is missing, invalid, or duplicated. A host may explicitly disable fallback, but doing so does not disable primary collision detection. Reserved `$md-utils` metadata is not available to frontmatter identity paths.

```swift
let policy = MarkdownRecordIdentityPolicy(
  source: .frontmatter(
    path: ["metadata", "slug"],
    format: .slug(.strictASCII)
  )
)

let index = await MarkdownRecordIdentityIndex.build(
  records: records,
  policy: policy
)
```

## Formats and Normalization

String identities are exact and case-sensitive. Integer identities accept lossless integers and use canonical base-10 text. UUID identities accept valid UUID spelling case-insensitively and normalize to lowercase hyphenated text before collision detection.

Slug validation is selected explicitly:

- `strictASCII` accepts lowercase ASCII letters and digits separated by single hyphens;
- `unicode` accepts lowercase Unicode letters and digits separated by non-adjacent hyphens or underscores; and
- `preserve` accepts ASCII letters and digits separated by single hyphens while preserving authored case.

Missing and null values are reported as missing identities. Malformed YAML or TOML, invalid formats, arrays, objects, booleans, non-integral numbers, and lossy conversions produce structured invalid-identity diagnostics. Identity status is independent from Markdown type conformance.

## Stability and Collisions

Existing and frontmatter-derived primary identities survive a record move. A logical-path primary identity and every logical-path fallback change when a record moves or is renamed. The full normalized relative path is used; basenames are never treated as globally unique.

The immutable index assesses the collection once and retains every candidate. Duplicate primary identities produce a diagnostic containing every available conflicting logical path. `lookup(primary:)` and `lookup(logicalPath:)` return `notFound`, one record candidate, or a conflict containing all candidates; lookup never selects the first collision.

Primary and logical-path lookup use separate namespaces. This matches server routing, where a primary item route and the reserved logical-path fallback route identify the same canonical record without creating an identity collision.

## Relationship to `fm unique`

The `md-utils fm unique` command audits arbitrary frontmatter scalars selected with JMESPath across filesystem inputs. The Core identity index instead applies one portable identity policy to `MarkdownRecord` values and builds reusable server-oriented lookup state. They share exact scalar and collision-reporting principles, but the Core API has no JMESPath, filesystem, CLI rendering, or `PathKit` dependency.
