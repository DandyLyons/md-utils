import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("Writable resource codecs")
struct ResourceCodecTests {
  private func codec(body: Bool = true) throws -> MarkdownResourceCodec {
    try MarkdownResourceCodec(configuration: .init(frontmatterFields: ["title", "due", "author", "value"],
      bodyWritable: body, protectedFields: ["id"]))
  }

  private func source(_ content: String) throws -> ResourceMutationSource {
    try ResourceMutationSource(record: MarkdownRecord(identity: .init(rawValue: "17"), content: content,
      context: .init(path: MarkdownRecordPath("books/17.md")), revision: .init(rawValue: "sha-original")),
      expectedRevision: .init(rawValue: "sha-original"))
  }

  @Test(arguments: [FrontMatterFormat.yaml, .toml])
  func `metadata changes preserve body and supported values`(_ format: FrontMatterFormat) throws {
    let metadata = format == .yaml ? "title: Old\nid: '17'\nprivate: keep\ndue: soon\n" :
      "title = 'Old'\nid = '17'\nprivate = 'keep'\ndue = 'soon'\n"
    let body = "\n## Description\r\nUnicode 👩🏽‍💻 e\u{301}\r\n\n"
    let original = try source(format.delimiter + "\n" + metadata + format.delimiter + "\n" + body)
    let edit = ResourceEdit.patch(frontmatter: ["title": .set(.string("New")), "due": .remove,
      "author": .set(.object(["name": .string("A"), "active": .boolean(true)]))], body: nil)
    let proposed = try codec().plan(edit, source: original)
    let document = try MarkdownDocument(content: proposed.record.content)
    #expect(document.body.utf8.elementsEqual(body.utf8))
    #expect(document.frontMatterFormat == format)
    #expect(document.frontMatter["title"] == .string("New"))
    #expect(document.frontMatter["id"] == .string("17"))
    #expect(document.frontMatter["private"] == .string("keep"))
    #expect(document.frontMatter["due"] == nil)
    #expect(proposed.record.identity == original.record.identity)
    #expect(proposed.record.context == original.record.context)
    #expect(proposed.record.revision == nil)
    #expect(proposed.baselineRevision == original.record.revision)
    #expect(try codec().plan(edit, source: original) == proposed)
  }

  @Test
  func `body edits preserve original frontmatter bytes and no ops preserve all bytes`() throws {
    let prefix = "---\n# discouraged but untouched for body edits\nid: '17'\ntitle: Old # comment\n---\n"
    let original = try source(prefix + "Body\n")
    let changed = try codec().plan(.patch(frontmatter: [:], body: "New\r\n"), source: original)
    #expect(changed.record.content.utf8.elementsEqual((prefix + "New\r\n").utf8))
    let same = try codec().plan(.patch(frontmatter: ["title": .set(.string("Old")), "due": .remove], body: nil), source: original)
    #expect(same.record.content.utf8.elementsEqual(original.record.content.utf8))
  }

  @Test
  func `replacement deletes omitted writable fields and retains protected values`() throws {
    let original = try source("---\nid: '17'\ntitle: Old\ndue: soon\nprivate: keep\n---\nOld body")
    let result = try codec().plan(.replace(frontmatter: ["title": .string("New")], body: "New body"), source: original)
    let document = try MarkdownDocument(content: result.record.content)
    #expect(document.frontMatter["due"] == nil)
    #expect(document.frontMatter["id"] == .string("17"))
    #expect(document.frontMatter["private"] == .string("keep"))
    #expect(document.body == "New body")
    #expect(throws: ResourceCodecError.self) {
      try codec().plan(.replace(frontmatter: [:], body: nil), source: original)
    }
  }

  @Test
  func `null removal and omission are distinct and nested objects replace as units`() throws {
    let original = try source("---\ndue: soon\nauthor: {name: A, email: a@example.com}\n---\nBody")
    let result = try codec().plan(.patch(frontmatter: ["due": .set(.null),
      "author": .set(.object(["name": .string("B")]))], body: nil), source: original)
    let document = try MarkdownDocument(content: result.record.content)
    #expect(document.frontMatter["due"] == .null)
    #expect(document.frontMatter["author"] == .object(FrontMatter(["name": .string("B")])))
    let retained = try codec().plan(.patch(frontmatter: [:], body: nil), source: original)
    #expect(retained.record.content == original.record.content)
    let removed = try codec().plan(.patch(frontmatter: ["due": .remove], body: nil), source: original)
    #expect(try MarkdownDocument(content: removed.record.content).frontMatter["due"] == nil)
  }

  @Test(arguments: ["id", "$md-utils", "unknown", "author.email"])
  func `unknown protected and nested path fields fail`(_ field: String) throws {
    let original = try source("# Body")
    #expect(throws: ResourceCodecError.self) {
      try codec().plan(.patch(frontmatter: [field: .set(.string("bad"))], body: nil), source: original)
    }
    #expect(throws: ResourceCodecError.self) {
      try codec().plan(.replace(frontmatter: [field: .string("bad")], body: "Body"), source: original)
    }
  }

  @Test
  func `read only body and unrepresentable TOML null fail`() throws {
    let original = try source("+++\ntitle = 'Old'\n+++\nBody")
    #expect(throws: ResourceCodecError.self) {
      try codec(body: false).plan(.patch(frontmatter: [:], body: "New"), source: original)
    }
    #expect(throws: ResourceCodecError.self) {
      try codec().plan(.patch(frontmatter: ["author": .set(.object(["name": .null]))], body: nil), source: original)
    }
  }

  @Test(arguments: ["---\ntitle: x", "---\r\ntitle: x\r\n---\r\nBody", "---\ntitle: x\n---suffix\nBody",
    "\u{FEFF}---\ntitle: x\n---\nBody", "---\n[invalid\n---\nBody"])
  func `malformed and unsupported source is rejected`(_ text: String) throws {
    let original = try source(text)
    #expect(throws: (any Error).self) {
      try codec().plan(.patch(frontmatter: ["title": .set(.string("New"))], body: nil), source: original)
    }
  }

  @Test
  func `missing revision stale revision and non Markdown paths fail`() throws {
    let record = MarkdownRecord(identity: .init(rawValue: "17"), content: "Body")
    #expect(throws: ResourceCodecError.self) {
      try ResourceMutationSource(record: record, expectedRevision: .init(rawValue: "old"))
    }
    var revised = record
    revised.revision = .init(rawValue: "new")
    #expect(throws: ResourceCodecError.self) {
      try ResourceMutationSource(record: revised, expectedRevision: .init(rawValue: "old"))
    }
    revised.context.path = try MarkdownRecordPath("code.swift")
    let original = try ResourceMutationSource(record: revised, expectedRevision: .init(rawValue: "new"))
    #expect(throws: ResourceCodecError.self) {
      try codec().plan(.patch(frontmatter: [:], body: "New"), source: original)
    }
  }

  @Test(arguments: ["false", "17", "null", "2026-10-01", "a: b", "---", "\nmultiline\ntext\n"])
  func `string values round trip without implicit scalar conversion`(_ value: String) throws {
    let original = try source("# Body")
    let result = try codec().plan(.patch(frontmatter: ["value": .set(.string(value))], body: nil), source: original)
    #expect(try MarkdownDocument(content: result.record.content).frontMatter["value"] == .string(value))
  }

  @Test
  func `body replacement cannot introduce frontmatter when none existed`() throws {
    let original = try source("Body")
    #expect(throws: ResourceCodecError.self) {
      try codec().plan(.patch(frontmatter: [:], body: "---\ntitle: injected\n---\nBody"), source: original)
    }
  }

  @Test(arguments: ["value: !custom hello",
    "value: 1\nvalue: 2", "value: {<<: {name: A}}", "42: value"])
  func `unsupported YAML representations cannot be silently rewritten`(_ metadata: String) throws {
    let original = try source("---\n" + metadata + "\n---\nBody")
    #expect(throws: (any Error).self) {
      try codec().plan(.patch(frontmatter: ["title": .set(.string("New"))], body: nil), source: original)
    }
  }

  @Test
  func `typed values round trip deterministically and TOML dates remain native`() throws {
    let values: [String: ResourceFieldPatch] = ["value": .set(.array([
      .boolean(false), .integer(42), .number(1.25), .object(["z": .string("last"), "a": .string("first")])]))]
    let yaml = try codec().plan(.patch(frontmatter: values, body: nil), source: source("Body"))
    let parsed = try MarkdownDocument(content: yaml.record.content)
    #expect(parsed.frontMatter["value"] == .array([.boolean(false), .integer(42), .number(1.25),
      .object(FrontMatter([("a", .string("first")), ("z", .string("last"))]))]))
    let toml = try source("+++\ndate = 2026-10-01\ntime = 12:34:56\n+++\nBody")
    let original = try MarkdownDocument(content: toml.record.content)
    let result = try codec().plan(.patch(frontmatter: ["title": .set(.string("New"))], body: nil), source: toml)
    let encoded = try MarkdownDocument(content: result.record.content)
    #expect(encoded.frontMatter["date"] == original.frontMatter["date"])
    #expect(encoded.frontMatter["time"] == original.frontMatter["time"])
  }

  @Test
  func `expanded YAML aliases preserve their values without promising source syntax`() throws {
    let original = try source("---\nvalue: &shared hello\nother: *shared\n---\nBody")
    let result = try codec().plan(.patch(frontmatter: ["title": .set(.string("New"))], body: nil), source: original)
    let parsed = try MarkdownDocument(content: result.record.content)
    #expect(parsed.frontMatter["value"] == .string("hello"))
    #expect(parsed.frontMatter["other"] == .string("hello"))
  }
}
