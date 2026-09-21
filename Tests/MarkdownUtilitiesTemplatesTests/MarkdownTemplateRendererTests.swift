import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesTemplates
import Testing

@Suite("Single-document Stencil prototype")
struct MarkdownTemplateRendererTests {
  @Test
  func `Yams preserves explicit JSON values and strings requiring quoting`() async throws {
    let frontmatter: [String: JSONValue] = [
      "title": .string("Sales: September"),
      "booleanLooking": .string("true"), "numberLooking": .string("42"),
      "nullLooking": .string("null"), "dateLooking": .string("2026-09-20"),
      "multiline": .string("first\n---\nlast"),
      "nested": .object(["items": .array([.null, .boolean(false), .integer(1), .number(1.5)])]),
      "emptyObject": .object([:]), "emptyArray": .array([]),
    ]
    let input = MarkdownTemplateInput(frontmatter: frontmatter, data: .object([:]))
    let result = try await MarkdownTemplateRenderer().render(
      template: "# {{ frontmatter.title }}\n", input: input)
    #expect(result.document.body == "# Sales: September\n")
    #expect(result.document.frontMatterFormat == .yaml)
    // Check parsed values and types rather than depending on a particular quoting style.
    #expect(result.document.frontMatter["title"] == .string("Sales: September"))
    #expect(result.document.frontMatter["booleanLooking"] == .string("true"))
    #expect(result.document.frontMatter["numberLooking"] == .string("42"))
    #expect(result.document.frontMatter["nullLooking"] == .string("null"))
    #expect(result.document.frontMatter["dateLooking"] == .string("2026-09-20"))
    #expect(result.document.frontMatter["multiline"] == .string("first\n---\nlast"))
    #expect(result.document.frontMatter["emptyObject"] == .object(FrontMatter()))
    #expect(result.document.frontMatter["emptyArray"] == .array([]))
    #expect(result.document.frontMatter["nested"] == .object(FrontMatter([
      "items": .array([.null, .boolean(false), .integer(1), .number(1.5)])
    ])))
    let repeated = try await MarkdownTemplateRenderer().render(
      template: "# {{ frontmatter.title }}\n", input: input)
    #expect(result.source == repeated.source)
  }

  @Test
  func `omitted and empty frontmatter remain distinct`() async throws {
    let renderer = MarkdownTemplateRenderer()
    let absent = try await renderer.render(template: "hello", input: .init(data: .null))
    let empty = try await renderer.render(template: "hello", input: .init(frontmatter: [:], data: .null))
    #expect(absent.source == "hello")
    #expect(absent.document.frontMatterFormat == nil)
    #expect(empty.document.frontMatterFormat == .yaml)
    #expect(empty.document.frontMatter.isEmpty)
    #expect(empty.document.body == "hello")
  }

  @Test
  func `loops conditions empty states and scalar roots use Stencil syntax`() async throws {
    let renderer = MarkdownTemplateRenderer()
    let template = "{% for item in data %}- {{ item }}\n{% empty %}No items.{% endfor %}"
    let populated = try await renderer.render(template: template,
      input: .init(data: .array([.string("A"), .string("B")])))
    #expect(populated.source == "- A\n- B\n")
    let empty = try await renderer.render(template: template, input: .init(data: .array([])))
    #expect(empty.source == "No items.")
    let scalar = try await renderer.render(template: "{% if data %}{{ data }}{% endif %}",
      input: .init(data: .string("hello")))
    #expect(scalar.source == "hello")
  }

  @Test
  func `schema rejects missing required values before template execution`() async throws {
    let schema = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"object","properties":{"data":{"type":"object","required":["title"]}}}"#.utf8))
    do {
      _ = try await MarkdownTemplateRenderer().render(template: "{% invalid %}",
        input: .init(data: .object([:])), schema: schema)
      Issue.record("Expected schema failure")
    } catch let error as MarkdownTemplateError {
      #expect(error.stage == .schema)
      #expect(error.message.contains("title"))
    }
  }

  @Test(arguments: ["---\ntitle: manual\n---\nbody", "+++\nx = 1\n+++\n", "---\n", "---", "\u{FEFF}---\n", "---\r\nx: y\r\n---\r\n"])
  func `templates cannot supply frontmatter`(template: String) async throws {
    await #expect(throws: MarkdownTemplateError.self) {
      try await MarkdownTemplateRenderer().render(template: template, input: .init(data: .null))
    }
  }

  @Test
  func `interpolated frontmatter blocks are rejected`() async throws {
    await #expect(throws: MarkdownTemplateError.self) {
      try await MarkdownTemplateRenderer().render(template: "{{ data }}",
        input: .init(data: .string("---\ninjected: true\n---\n")))
    }
  }

  @Test(arguments: ["{% include \"secret.stencil\" %}", "{% extends \"base.stencil\" %}", "{% unknown %}"])
  func `external templates and invalid syntax fail`(template: String) async throws {
    do {
      _ = try await MarkdownTemplateRenderer().render(template: template, input: .init(data: .null))
      Issue.record("Expected template failure")
    } catch let error as MarkdownTemplateError {
      #expect(error.stage == .template)
    }
  }

  @Test
  func `size guardrails cover template input and assembled output`() async throws {
    for limits in [
      MarkdownTemplateLimits(templateBytes: 1),
      MarkdownTemplateLimits(inputBytes: 1),
      MarkdownTemplateLimits(outputBytes: 1),
      MarkdownTemplateLimits(templateBytes: 0),
    ] {
      await #expect(throws: MarkdownTemplateError.self) {
        try await MarkdownTemplateRenderer(limits: limits).render(template: "hello",
          input: .init(frontmatter: ["title": .string("long title")], data: .null))
      }
    }
  }

  @Test
  func `missing null and empty values retain the documented prototype semantics`() async throws {
    let result = try await MarkdownTemplateRenderer().render(
      template: "{{ data.missing|default:'fallback' }}|{{ data.null }}|{{ data.empty }}|{% if data.null %}present{% endif %}",
      input: .init(data: .object(["null": .null, "empty": .string("")])))
    #expect(result.source == "fallback|||")
  }

  @Test
  func `null normalization preserves nested array positions schema values and YAML`() async throws {
    let schema = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"object","properties":{"frontmatter":{"type":"object","required":["value"],"properties":{"value":{"type":"null"}}}}}"#.utf8))
    let result = try await MarkdownTemplateRenderer().render(
      template: "{{ frontmatter.value }}{% if frontmatter.value %}wrong{% endif %}|{% for item in data %}[{{ item.value }}]{% endfor %}|{{ data.count }}",
      input: .init(frontmatter: ["value": .null], data: .array([
        .object(["value": .string("A")]), .null, .object(["value": .null]),
        .object(["value": .string("B")])
      ])), schema: schema)
    #expect(result.source.hasSuffix("|[A][][][B]|4"))
    #expect(result.document.frontMatter["value"] == .null)
    let root = try await MarkdownTemplateRenderer().render(
      template: "{{ data }}{% if data %}wrong{% endif %}", input: .init(data: .null))
    #expect(root.source.isEmpty)
  }

  @Test
  func `assembled frontmatter counts toward the output limit`() async throws {
    await #expect(throws: MarkdownTemplateError.self) {
      try await MarkdownTemplateRenderer(limits: .init(outputBytes: 5)).render(
        template: "hello", input: .init(frontmatter: ["title": .string("report")], data: .null))
    }
  }

  @Test
  func `frontmatter must be an object and library numbers must be finite`() async throws {
    for json in [#"{"frontmatter":null,"data":{}}"#, #"{"frontmatter":[],"data":{}}"#] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(MarkdownTemplateInput.self, from: Data(json.utf8))
      }
    }
    await #expect(throws: MarkdownTemplateError.self) {
      try await MarkdownTemplateRenderer().render(template: "body", input: .init(data: .number(.infinity)))
    }
  }
}
