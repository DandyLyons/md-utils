import Foundation
import Yams

/// Encodes a keyed Codable model as Markdown with YAML frontmatter.
public struct YAMLMarkdownEncoder {
  public var bodyFrontmatterStrategy: MarkdownBodyFrontmatterStrategy
  public var userInfo: [CodingUserInfoKey: any Sendable]

  public init() {
    bodyFrontmatterStrategy = .omit
    userInfo = [:]
  }

  public func encode<Value: Encodable>(
    _ value: Value,
    body bodyField: MarkdownBodyField<Value>
  ) throws -> String {
    try MarkdownCodecSupport.validate(bodyField)
    let body = value[keyPath: bodyField.keyPath]
    let encoder = YAMLEncoder()
    encoder.options.sortKeys = true
    let yaml = try encoder.encode(value, userInfo: userInfo.reduce(into: [:]) { result, entry in
      result[entry.key] = entry.value
    })

    let decoded: FrontMatter
    do {
      decoded = try FrontMatterConversion.parse(yaml, format: .yaml)
    } catch YAMLConversionError.notAMapping {
      throw MarkdownCodecError.encodedRootIsNotMapping(format: .yaml)
    }
    try MarkdownCodecSupport.verifyEncodedBody(
      in: decoded,
      codingPath: bodyField.codingPath,
      expectedBody: body
    )

    let projected: FrontMatter
    switch bodyFrontmatterStrategy {
    case .omit:
      projected = try MarkdownCodecSupport.removingBody(from: decoded, at: bodyField.codingPath)
    case .include:
      projected = decoded
    }
    return try MarkdownCodecSupport.render(
      frontMatter: MarkdownCodecSupport.sortedRecursively(projected),
      body: body,
      format: .yaml
    )
  }
}

/// Decodes a keyed Codable model from Markdown with YAML frontmatter.
public struct YAMLMarkdownDecoder {
  public var userInfo: [CodingUserInfoKey: any Sendable]

  public init() {
    userInfo = [:]
  }

  public func decode<Value: Decodable>(
    _ type: Value.Type,
    from markdown: String,
    body bodyField: MarkdownBodyField<Value>
  ) throws -> Value {
    try MarkdownCodecSupport.validate(bodyField)
    let document = try MarkdownDocument(content: markdown)
    guard document.frontMatterFormat == .yaml else {
      throw MarkdownCodecError.frontMatterFormatMismatch(
        expected: .yaml,
        actual: document.frontMatterFormat
      )
    }
    let composed = try MarkdownCodecSupport.insertingBody(
      document.body,
      into: document.frontMatter,
      at: bodyField.codingPath
    )
    let yaml = try FrontMatterConversion.serialize(
      MarkdownCodecSupport.sortedRecursively(composed),
      format: .yaml
    )
    let decoder = YAMLDecoder()
    let value = try decoder.decode(type, from: yaml, userInfo: userInfo.reduce(into: [:]) { result, entry in
      result[entry.key] = entry.value
    })
    guard value[keyPath: bodyField.keyPath] == document.body else {
      throw MarkdownCodecError.decodedBodyValueMismatch(codingPath: bodyField.codingPath)
    }
    return value
  }
}
