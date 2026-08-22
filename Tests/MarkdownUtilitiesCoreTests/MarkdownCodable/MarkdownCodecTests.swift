import Foundation
import MarkdownUtilitiesCore
import Testing
import TOML

@Suite("Markdown Codable codecs")
struct MarkdownCodecTests {
  @Test
  func `YAML codec round trips nested body with omitted frontmatter field`() throws {
    let article = Article(
      title: "Codec design",
      tags: ["swift", "markdown"],
      payload: Payload(summary: "A summary", content: "# Heading\n\nBody")
    )
    let field = MarkdownBodyField(\Article.payload.content, codingPath: ["payload", "content"])

    let markdown = try YAMLMarkdownEncoder().encode(article, body: field)

    #expect(markdown.hasPrefix("---\n"))
    #expect(markdown.contains("summary: A summary"))
    #expect(!markdown.contains("content: '# Heading"))
    #expect(try YAMLMarkdownDecoder().decode(Article.self, from: markdown, body: field) == article)
  }

  @Test
  func `TOML codec round trips nested body with omitted frontmatter field`() throws {
    let article = Article(
      title: "Codec design",
      tags: ["swift", "markdown"],
      payload: Payload(summary: "A summary", content: "# Heading\n\nBody")
    )
    let field = MarkdownBodyField(\Article.payload.content, codingPath: ["payload", "content"])

    let markdown = try TOMLMarkdownEncoder().encode(article, body: field)

    #expect(markdown.hasPrefix("+++\n"))
    #expect(markdown.contains("summary = \"A summary\""))
    #expect(!markdown.contains("content ="))
    #expect(try TOMLMarkdownDecoder().decode(Article.self, from: markdown, body: field) == article)
  }

  @Test
  func `include strategy retains body in both frontmatter formats`() throws {
    let value = Note(title: "Included", content: "Body")
    let field = MarkdownBodyField(\Note.content, codingPath: ["content"])
    var yamlEncoder = YAMLMarkdownEncoder()
    yamlEncoder.bodyFrontmatterStrategy = .include
    var tomlEncoder = TOMLMarkdownEncoder()
    tomlEncoder.bodyFrontmatterStrategy = .include

    let yaml = try yamlEncoder.encode(value, body: field)
    let toml = try tomlEncoder.encode(value, body: field)

    #expect(yaml.contains("content: Body"))
    #expect(toml.contains("content = \"Body\""))
    #expect(try YAMLMarkdownDecoder().decode(Note.self, from: yaml, body: field) == value)
    #expect(try TOMLMarkdownDecoder().decode(Note.self, from: toml, body: field) == value)
  }

  @Test
  func `renamed coding key is selected explicitly`() throws {
    let value = RenamedNote(title: "Renamed", content: "Selected body")
    let field = MarkdownBodyField(\RenamedNote.content, codingPath: ["markdown_body"])

    let yaml = try YAMLMarkdownEncoder().encode(value, body: field)
    let toml = try TOMLMarkdownEncoder().encode(value, body: field)

    #expect(!yaml.contains("markdown_body:"))
    #expect(!toml.contains("markdown_body ="))
    #expect(try YAMLMarkdownDecoder().decode(RenamedNote.self, from: yaml, body: field) == value)
    #expect(try TOMLMarkdownDecoder().decode(RenamedNote.self, from: toml, body: field) == value)
  }

  @Test
  func `body-only models preserve empty and delimiter-like bodies`() throws {
    let yamlField = MarkdownBodyField(\BodyOnly.content, codingPath: ["content"])
    let tomlField = MarkdownBodyField(\BodyOnly.content, codingPath: ["content"])
    let yamlValues = [BodyOnly(content: ""), BodyOnly(content: "---\nlooks like YAML")]
    let tomlValues = [BodyOnly(content: ""), BodyOnly(content: "+++\nlooks like TOML")]

    for value in yamlValues {
      let markdown = try YAMLMarkdownEncoder().encode(value, body: yamlField)
      #expect(markdown.hasPrefix("---\n---\n"))
      #expect(try YAMLMarkdownDecoder().decode(BodyOnly.self, from: markdown, body: yamlField) == value)
    }
    for value in tomlValues {
      let markdown = try TOMLMarkdownEncoder().encode(value, body: tomlField)
      #expect(markdown.hasPrefix("+++\n+++\n"))
      #expect(try TOMLMarkdownDecoder().decode(BodyOnly.self, from: markdown, body: tomlField) == value)
    }
  }

  @Test
  func `encoding is byte-for-byte deterministic`() throws {
    let value = Note(title: "Stable", content: "Body")
    let field = MarkdownBodyField(\Note.content, codingPath: ["content"])
    let yamlEncoder = YAMLMarkdownEncoder()
    let tomlEncoder = TOMLMarkdownEncoder()

    #expect(try yamlEncoder.encode(value, body: field) == yamlEncoder.encode(value, body: field))
    #expect(try tomlEncoder.encode(value, body: field) == tomlEncoder.encode(value, body: field))
  }

  @Test
  func `YAML supports an explicitly encoded null`() throws {
    let value = ExplicitNullNote(content: "Body")
    let field = MarkdownBodyField(\ExplicitNullNote.content, codingPath: ["content"])

    let markdown = try YAMLMarkdownEncoder().encode(value, body: field)

    let document = try MarkdownDocument(content: markdown)
    #expect(document.frontMatter["nullable"] == .null)
    #expect(try YAMLMarkdownDecoder().decode(ExplicitNullNote.self, from: markdown, body: field) == value)
  }

  @Test
  func `TOML preserves native temporal values`() throws {
    let value = TemporalNote(
      offset: Date(timeIntervalSince1970: 1_700_000_000),
      localDateTime: LocalDateTime(
        year: 2026,
        month: 8,
        day: 22,
        hour: 14,
        minute: 30,
        second: 5
      ),
      localDate: LocalDate(year: 2026, month: 8, day: 22),
      localTime: LocalTime(hour: 14, minute: 30, second: 5),
      content: "Body"
    )
    let field = MarkdownBodyField(\TemporalNote.content, codingPath: ["content"])

    let markdown = try TOMLMarkdownEncoder().encode(value, body: field)
    let document = try MarkdownDocument(content: markdown)

    guard case .offsetDateTime = document.frontMatter["offset"] else {
      Issue.record("Expected a TOML offset date-time")
      return
    }
    guard case .localDateTime = document.frontMatter["localDateTime"] else {
      Issue.record("Expected a TOML local date-time")
      return
    }
    guard case .localDate = document.frontMatter["localDate"] else {
      Issue.record("Expected a TOML local date")
      return
    }
    guard case .localTime = document.frontMatter["localTime"] else {
      Issue.record("Expected a TOML local time")
      return
    }
    #expect(try TOMLMarkdownDecoder().decode(TemporalNote.self, from: markdown, body: field) == value)
  }

  @Test
  func `TOML omits synthesized nil optional keys`() throws {
    let value = OptionalNote(title: "Optional", subtitle: nil, content: "Body")
    let field = MarkdownBodyField(\OptionalNote.content, codingPath: ["content"])

    let markdown = try TOMLMarkdownEncoder().encode(value, body: field)

    #expect(!markdown.contains("subtitle"))
    #expect(try TOMLMarkdownDecoder().decode(OptionalNote.self, from: markdown, body: field) == value)
  }

  @Test
  func `TOML rejects explicit keyed null with coding path`() {
    let value = ExplicitNullNote(content: "Body")
    let field = MarkdownBodyField(\ExplicitNullNote.content, codingPath: ["content"])

    #expect(throws: MarkdownCodecError.tomlNullNotRepresentable(codingPath: ["nullable"])) {
      try TOMLMarkdownEncoder().encode(value, body: field)
    }
  }

  @Test
  func `TOML rejects nil array element with coding path`() {
    let value = OptionalArrayNote(values: ["one", nil, "three"], content: "Body")
    let field = MarkdownBodyField(\OptionalArrayNote.content, codingPath: ["content"])

    #expect(throws: MarkdownCodecError.tomlNullNotRepresentable(codingPath: ["values", "[1]"])) {
      try TOMLMarkdownEncoder().encode(value, body: field)
    }
  }

  @Test
  func `wrong and absent frontmatter formats are rejected`() throws {
    let value = Note(title: "Format", content: "Body")
    let field = MarkdownBodyField(\Note.content, codingPath: ["content"])
    let yaml = try YAMLMarkdownEncoder().encode(value, body: field)
    let toml = try TOMLMarkdownEncoder().encode(value, body: field)

    #expect(throws: MarkdownCodecError.frontMatterFormatMismatch(expected: .yaml, actual: .toml)) {
      try YAMLMarkdownDecoder().decode(Note.self, from: toml, body: field)
    }
    #expect(throws: MarkdownCodecError.frontMatterFormatMismatch(expected: .toml, actual: .yaml)) {
      try TOMLMarkdownDecoder().decode(Note.self, from: yaml, body: field)
    }
    #expect(throws: MarkdownCodecError.frontMatterFormatMismatch(expected: .yaml, actual: nil)) {
      try YAMLMarkdownDecoder().decode(Note.self, from: "Body", body: field)
    }
  }

  @Test
  func `included frontmatter body must match Markdown body`() {
    let field = MarkdownBodyField(\Note.content, codingPath: ["content"])
    let yaml = "---\ncontent: Frontmatter\ntitle: Test\n---\nBody"
    let toml = "+++\ncontent = \"Frontmatter\"\ntitle = \"Test\"\n+++\nBody"

    #expect(throws: MarkdownCodecError.bodyFrontmatterValueMismatch(codingPath: ["content"])) {
      try YAMLMarkdownDecoder().decode(Note.self, from: yaml, body: field)
    }
    #expect(throws: MarkdownCodecError.bodyFrontmatterValueMismatch(codingPath: ["content"])) {
      try TOMLMarkdownDecoder().decode(Note.self, from: toml, body: field)
    }
  }

  @Test
  func `invalid and blocked coding paths report codec errors`() {
    let value = Note(title: "Paths", content: "Body")
    let empty = MarkdownBodyField(\Note.content, codingPath: [])
    let emptyComponent = MarkdownBodyField(\Note.content, codingPath: [""])
    let missing = MarkdownBodyField(\Note.content, codingPath: ["missing"])
    let blocked = MarkdownBodyField(\Note.content, codingPath: ["title", "content"])

    #expect(throws: MarkdownCodecError.emptyBodyCodingPath) {
      try YAMLMarkdownEncoder().encode(value, body: empty)
    }
    #expect(throws: MarkdownCodecError.emptyBodyCodingPathComponent(index: 0)) {
      try YAMLMarkdownEncoder().encode(value, body: emptyComponent)
    }
    #expect(throws: MarkdownCodecError.bodyFieldMissing(codingPath: ["missing"])) {
      try YAMLMarkdownEncoder().encode(value, body: missing)
    }
    #expect(
      throws: MarkdownCodecError.bodyCodingPathBlocked(
        codingPath: ["title", "content"],
        component: "title"
      )
    ) {
      try YAMLMarkdownEncoder().encode(value, body: blocked)
    }
  }

  @Test
  func `manual encoding that disagrees with body key path is rejected`() {
    let value = MismatchedNote(content: "Body")
    let field = MarkdownBodyField(\MismatchedNote.content, codingPath: ["content"])

    #expect(throws: MarkdownCodecError.bodyFieldValueMismatch(codingPath: ["content"])) {
      try YAMLMarkdownEncoder().encode(value, body: field)
    }
    #expect(throws: MarkdownCodecError.bodyFieldValueMismatch(codingPath: ["content"])) {
      try TOMLMarkdownEncoder().encode(value, body: field)
    }
  }

  @Test
  func `non-string encoded body field is rejected`() {
    let value = NonStringBodyNote(content: "Body")
    let field = MarkdownBodyField(\NonStringBodyNote.content, codingPath: ["content"])

    #expect(throws: MarkdownCodecError.bodyFieldIsNotString(codingPath: ["content"])) {
      try YAMLMarkdownEncoder().encode(value, body: field)
    }
    #expect(throws: MarkdownCodecError.bodyFieldIsNotString(codingPath: ["content"])) {
      try TOMLMarkdownEncoder().encode(value, body: field)
    }
  }

  @Test
  func `decoded body must still agree with key path`() throws {
    let source = TransformingDecodeNote(content: "Body")
    let field = MarkdownBodyField(\TransformingDecodeNote.content, codingPath: ["content"])
    let yaml = try YAMLMarkdownEncoder().encode(source, body: field)
    let toml = try TOMLMarkdownEncoder().encode(source, body: field)

    #expect(throws: MarkdownCodecError.decodedBodyValueMismatch(codingPath: ["content"])) {
      try YAMLMarkdownDecoder().decode(TransformingDecodeNote.self, from: yaml, body: field)
    }
    #expect(throws: MarkdownCodecError.decodedBodyValueMismatch(codingPath: ["content"])) {
      try TOMLMarkdownDecoder().decode(TransformingDecodeNote.self, from: toml, body: field)
    }
  }

  @Test
  func `TOML rejects unsigned integers outside its range`() {
    let value = UnsignedNote(count: UInt64.max, content: "Body")
    let field = MarkdownBodyField(\UnsignedNote.content, codingPath: ["content"])

    #expect(throws: MarkdownCodecError.tomlIntegerOutOfRange(codingPath: ["count"])) {
      try TOMLMarkdownEncoder().encode(value, body: field)
    }
  }

  @Test
  func `non-mapping roots are rejected`() {
    let yamlField = MarkdownBodyField(\[String].firstBody, codingPath: ["content"])
    let tomlField = MarkdownBodyField(\[String].firstBody, codingPath: ["content"])

    #expect(throws: MarkdownCodecError.encodedRootIsNotMapping(format: .yaml)) {
      try YAMLMarkdownEncoder().encode(["Body"], body: yamlField)
    }
    #expect(throws: MarkdownCodecError.encodedRootIsNotMapping(format: .toml)) {
      try TOMLMarkdownEncoder().encode(["Body"], body: tomlField)
    }
  }

  @Test
  func `user info reaches custom encoding and decoding`() throws {
    let key = try #require(CodingUserInfoKey(rawValue: "markdown-codec-test"))
    let field = MarkdownBodyField(\UserInfoNote.content, codingPath: ["content"])
    let value = UserInfoNote(content: "Body", observedValue: "configured")
    var yamlEncoder = YAMLMarkdownEncoder()
    yamlEncoder.userInfo[key] = "configured"
    var yamlDecoder = YAMLMarkdownDecoder()
    yamlDecoder.userInfo[key] = "configured"
    var tomlEncoder = TOMLMarkdownEncoder()
    tomlEncoder.userInfo[key] = "configured"
    var tomlDecoder = TOMLMarkdownDecoder()
    tomlDecoder.userInfo[key] = "configured"

    let yaml = try yamlEncoder.encode(value, body: field)
    let toml = try tomlEncoder.encode(value, body: field)

    #expect(try yamlDecoder.decode(UserInfoNote.self, from: yaml, body: field) == value)
    #expect(try tomlDecoder.decode(UserInfoNote.self, from: toml, body: field) == value)
  }
}

private struct Article: Codable, Equatable {
  let title: String
  let tags: [String]
  let payload: Payload
}

private struct Payload: Codable, Equatable {
  let summary: String
  let content: String
}

private struct Note: Codable, Equatable {
  let title: String
  let content: String
}

private struct RenamedNote: Codable, Equatable {
  let title: String
  let content: String

  enum CodingKeys: String, CodingKey {
    case title
    case content = "markdown_body"
  }
}

private struct BodyOnly: Codable, Equatable {
  let content: String
}

private struct OptionalNote: Codable, Equatable {
  let title: String
  let subtitle: String?
  let content: String
}

private struct OptionalArrayNote: Codable {
  let values: [String?]
  let content: String
}

private struct TemporalNote: Codable, Equatable {
  let offset: Date
  let localDateTime: LocalDateTime
  let localDate: LocalDate
  let localTime: LocalTime
  let content: String
}

private struct MismatchedNote: Encodable {
  let content: String

  enum CodingKeys: String, CodingKey {
    case content
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("Different", forKey: .content)
  }
}

private struct NonStringBodyNote: Encodable {
  let content: String

  enum CodingKeys: String, CodingKey {
    case content
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(42, forKey: .content)
  }
}

private struct TransformingDecodeNote: Codable {
  let content: String

  enum CodingKeys: String, CodingKey {
    case content
  }

  init(content: String) {
    self.content = content
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    content = try container.decode(String.self, forKey: .content) + " transformed"
  }
}

private struct UnsignedNote: Encodable {
  let count: UInt64
  let content: String
}

private struct ExplicitNullNote: Codable, Equatable {
  let content: String

  enum CodingKeys: String, CodingKey {
    case nullable
    case content
  }

  init(content: String) {
    self.content = content
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decodeNil(forKey: .nullable) else {
      throw DecodingError.dataCorruptedError(
        forKey: .nullable,
        in: container,
        debugDescription: "Expected an explicit null"
      )
    }
    content = try container.decode(String.self, forKey: .content)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeNil(forKey: .nullable)
    try container.encode(content, forKey: .content)
  }
}

private struct UserInfoNote: Codable, Equatable {
  let content: String
  let observedValue: String

  enum CodingKeys: String, CodingKey {
    case content
    case observedValue
  }

  init(content: String, observedValue: String) {
    self.content = content
    self.observedValue = observedValue
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    content = try container.decode(String.self, forKey: .content)
    observedValue = Self.observedValue(in: decoder.userInfo)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(content, forKey: .content)
    try container.encode(Self.observedValue(in: encoder.userInfo), forKey: .observedValue)
  }

  private static func observedValue(in userInfo: [CodingUserInfoKey: Any]) -> String {
    guard let key = CodingUserInfoKey(rawValue: "markdown-codec-test") else { return "missing" }
    return userInfo[key] as? String ?? "missing"
  }
}

private extension Array where Element == String {
  var firstBody: String { first ?? "" }
}
