import Testing
import MarkdownUtilitiesCore
@testable import MarkdownUtilitiesTemplates

@Suite("Template resource creation")
struct TemplateResourceCreationCodecTests {
  private func creator(schema: JSONValue? = nil) throws -> TemplateResourceCreationCodec {
    TemplateResourceCreationCodec(codec: try MarkdownResourceCodec(configuration: .init(
      frontmatterFields: ["title"], bodyWritable: true, protectedFields: ["id"])),
      template: .init(template: "# Book\n\n{{ data.description }}\n", inputSchema: schema))
  }

  @Test
  func `shared rendering produces a complete proposal with explicit host identity`() async throws {
    let codec = try creator()
    let result = try await codec.plan(input: .init(frontmatter: ["title": .string("Dune")],
      data: .object(["description": .string("A novel.")])), identity: .init(rawValue: "17"),
      protectedFrontmatter: ["id": .string("17")])
    let document = try MarkdownDocument(content: result.record.content)
    #expect(document.frontMatter["title"] == .string("Dune"))
    #expect(document.frontMatter["id"] == .string("17"))
    #expect(document.body == "# Book\n\nA novel.\n")
    #expect(result.original == nil)
    #expect(result.baselineRevision == nil)
    #expect(result.record.revision == nil)
    let rendered = try await MarkdownTemplateRenderer().render(template: codec.template.template,
      input: .init(frontmatter: ["title": .string("Dune"), "id": .string("17")],
        data: .object(["description": .string("A novel.")])))
    #expect(result.record.content == rendered.source)
  }

  @Test
  func `input schema rejects missing values and does not invent defaults`() async throws {
    let schema: JSONValue = .object(["type": .string("object"), "properties": .object([
      "frontmatter": .object(["type": .string("object"), "required": .array([.string("title")]),
        "properties": .object(["title": .object(["default": .string("Invented")])])])
    ])])
    await #expect(throws: MarkdownTemplateError.self) {
      try await creator(schema: schema).plan(input: .init(frontmatter: [:], data: .object([:])),
        identity: .init(rawValue: "17"))
    }
    let result = try await creator().plan(input: .init(frontmatter: [:], data: .object([:])), identity: .init(rawValue: "17"))
    #expect(try MarkdownDocument(content: result.record.content).frontMatter["title"] == nil)
  }

  @Test(arguments: ["unknown", "id", "$md-utils"])
  func `creation refuses unknown or protected request fields`(_ key: String) async throws {
    await #expect(throws: ResourceCodecError.self) {
      try await creator().plan(input: .init(frontmatter: [key: .string("bad")], data: .object([:])),
        identity: .init(rawValue: "17"))
    }
  }
}
