# Encoding Codable Models as Markdown

Store a keyed Codable model in a Markdown document with YAML or TOML frontmatter and one caller-selected string body.

## Choose a frontmatter format

The Markdown codecs are format-specific because YAML and TOML do not share one data model. Use ``YAMLMarkdownEncoder`` and ``YAMLMarkdownDecoder`` when explicit null values are required. Use ``TOMLMarkdownEncoder`` and ``TOMLMarkdownDecoder`` for TOML tables and native temporal values.

There is intentionally no format-neutral `MarkdownEncoder` or automatic decoder. Choosing the codec makes the document contract explicit.

## Select the body

Declare a ``MarkdownBodyField`` with both the model key path and its encoded coding path:

```swift
struct Article: Codable, Equatable {
  var title: String
  var content: String

  enum CodingKeys: String, CodingKey {
    case title
    case content = "markdown_body"
  }
}

let bodyField = MarkdownBodyField(
  \Article.content,
  codingPath: ["markdown_body"]
)
```

The key path reads the body from an encoded or decoded model. The coding path locates the same value in frontmatter, including renamed `CodingKeys` and nested mappings. Coding paths support mapping keys only.

## Encode and decode YAML

```swift
let article = Article(title: "Example", content: "# Hello\n")
let encoder = YAMLMarkdownEncoder()
let markdown = try encoder.encode(article, body: bodyField)
let decoded = try YAMLMarkdownDecoder().decode(
  Article.self,
  from: markdown,
  body: bodyField
)
```

The body field is omitted from frontmatter by default. Set ``YAMLMarkdownEncoder/bodyFrontmatterStrategy`` to ``MarkdownBodyFrontmatterStrategy/include`` to retain it in both places. When included, the two values must agree during decoding.

## Encode and decode TOML

```swift
let encoder = TOMLMarkdownEncoder()
let markdown = try encoder.encode(article, body: bodyField)
let decoded = try TOMLMarkdownDecoder().decode(
  Article.self,
  from: markdown,
  body: bodyField
)
```

Synthesized keyed optional properties whose value is `nil` are absent from TOML and decode back to `nil`. Explicit `encodeNil` calls and nil elements in collections throw ``MarkdownCodecError/tomlNullNotRepresentable(codingPath:)`` because silently discarding them would be lossy.

## Round-trip guarantees

Both codec pairs require a top-level keyed model, one nonoptional `String` body, and an exact match between the key-path and coding-path values. The selected body string is preserved exactly. Frontmatter is sorted and normalized, so comments, quoting, whitespace, and source layout are not preserved.

These codecs provide a typed persistence primitive. They do not define a universal representation for arbitrary Codable values or the writable server `ResourceCodec` contract.
