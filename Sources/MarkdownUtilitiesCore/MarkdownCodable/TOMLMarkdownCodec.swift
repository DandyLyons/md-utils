import Foundation
import TOML

/// Encodes a keyed Codable model as Markdown with TOML frontmatter.
public struct TOMLMarkdownEncoder {
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
    try TOMLNullValidator.validate(value, userInfo: userInfo)

    let body = value[keyPath: bodyField.keyPath]
    let encoder = TOMLEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.userInfo = userInfo
    let toml = try encoder.encodeToString(value)

    let decoded: FrontMatter
    do {
      decoded = try FrontMatterConversion.parse(toml, format: .toml)
    } catch FrontMatterConversionError.invalidTOML {
      throw MarkdownCodecError.encodedRootIsNotMapping(format: .toml)
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
      format: .toml
    )
  }
}

/// Decodes a keyed Codable model from Markdown with TOML frontmatter.
public struct TOMLMarkdownDecoder {
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
    guard document.frontMatterFormat == .toml else {
      throw MarkdownCodecError.frontMatterFormatMismatch(
        expected: .toml,
        actual: document.frontMatterFormat
      )
    }
    let composed = try MarkdownCodecSupport.insertingBody(
      document.body,
      into: document.frontMatter,
      at: bodyField.codingPath
    )
    let toml = try FrontMatterConversion.serialize(
      MarkdownCodecSupport.sortedRecursively(composed),
      format: .toml
    )
    let decoder = TOMLDecoder()
    decoder.userInfo = userInfo
    let value = try decoder.decode(type, from: toml)
    guard value[keyPath: bodyField.keyPath] == document.body else {
      throw MarkdownCodecError.decodedBodyValueMismatch(codingPath: bodyField.codingPath)
    }
    return value
  }
}
