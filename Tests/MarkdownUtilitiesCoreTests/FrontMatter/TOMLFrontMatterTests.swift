import MarkdownUtilitiesCore
import Testing

@Suite("TOML frontmatter")
struct TOMLFrontMatterTests {
  @Test
  func `parses and renders TOML values with TOML delimiters`() throws {
    let content = """
      +++
      title = "TOML document"
      draft = false
      count = 3
      tags = ["swift", "toml"]
      published = 2026-08-16

      [author]
      name = "Daniel"
      +++
      # Body
      """

    let document = try MarkdownDocument(content: content)

    #expect(document.frontMatterFormat == .toml)
    #expect(document.frontMatter["title"]?.stringValue == "TOML document")
    #expect(document.frontMatter["draft"]?.bool == false)
    #expect(document.frontMatter["count"]?.int == 3)
    #expect(document.frontMatter["tags"]?.sequence?.compactMap(\.stringValue) == ["swift", "toml"])
    #expect(document.frontMatter["author"]?.mapping?["name"]?.stringValue == "Daniel")
    guard case .localDate = document.frontMatter["published"] else {
      Issue.record("Expected a TOML local date")
      return
    }

    let rendered = try document.render()
    #expect(rendered.hasPrefix("+++\n"))
    #expect(rendered.contains("published = 2026-08-16"))
    #expect(rendered.contains("\n+++\n# Body"))

    let reparsed = try MarkdownDocument(content: rendered)
    #expect(reparsed.frontMatterFormat == .toml)
    #expect(reparsed.frontMatter["author"]?.mapping?["name"]?.stringValue == "Daniel")
  }

  @Test
  func `supports TOML date time types and arrays of tables`() throws {
    let document = try MarkdownDocument(content: """
      +++
      offset = 1979-05-27T07:32:00Z
      local_datetime = 1979-05-27T07:32:00
      local_date = 1979-05-27
      local_time = 07:32:00

      [[products]]
      name = "Hammer"

      [[products]]
      name = "Nail"
      +++
      Body
      """)

    guard case .offsetDateTime = document.frontMatter["offset"] else {
      Issue.record("Expected an offset date-time")
      return
    }
    guard case .localDateTime = document.frontMatter["local_datetime"] else {
      Issue.record("Expected a local date-time")
      return
    }
    guard case .localDate = document.frontMatter["local_date"] else {
      Issue.record("Expected a local date")
      return
    }
    guard case .localTime = document.frontMatter["local_time"] else {
      Issue.record("Expected a local time")
      return
    }
    let products = try #require(document.frontMatter["products"]?.sequence)
    #expect(products.count == 2)
    #expect(products[0].mapping?["name"]?.stringValue == "Hammer")
    #expect(products[1].mapping?["name"]?.stringValue == "Nail")

    let reparsed = try MarkdownDocument(content: document.render())
    #expect(reparsed.frontMatter["products"]?.sequence?.count == 2)
  }

  @Test
  func `recognizes empty TOML and does not accept mismatched delimiters`() throws {
    let empty = try MarkdownDocument(content: "+++\n+++\nBody")
    #expect(empty.frontMatterFormat == .toml)
    #expect(empty.frontMatter.isEmpty)
    #expect(empty.body == "Body")

    let mismatchedSource = "+++\ntitle = \"Example\"\n---\nBody"
    let mismatched = try MarkdownDocument(content: mismatchedSource)
    #expect(mismatched.frontMatterFormat == nil)
    #expect(mismatched.body == mismatchedSource)
  }

  @Test
  func `TOML mutations preserve TOML and nested values`() throws {
    var document = try MarkdownDocument(content: """
      +++
      title = "Before"
      tags = ["one"]
      +++
      Body
      """)

    document.setValue("After", forKey: "title")
    document.frontMatter["tags"] = .array([.string("one"), .string("two")])

    let rendered = try document.render()
    #expect(rendered.hasPrefix("+++\n"))
    #expect(!rendered.contains("---"))
    #expect(try MarkdownDocument(content: rendered).frontMatter["title"]?.stringValue == "After")
  }

  @Test
  func `TOML rejects null values with their key path`() throws {
    let document = MarkdownDocument(
      frontMatter: FrontMatter(["draft": .null]),
      body: "Body",
      frontMatterFormat: .toml
    )

    #expect(throws: FrontMatterConversionError.unsupportedTOMLValue(path: "draft", value: "null")) {
      try document.render()
    }
  }

  @Test
  func `malformed TOML reports a TOML conversion error`() {
    #expect(throws: FrontMatterConversionError.self) {
      try MarkdownDocument(content: "+++\nvalue = [\n+++\nBody")
    }
  }
}
