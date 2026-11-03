import Testing
@testable import MarkdownUtilitiesCore

struct MarkdownBodySourceTests {
  @Test(arguments: [
    "---\ndate: 2026-10-01 # café\ntext: e\u{301}\n---\n",
    "+++\ninvalid = [\n+++\n",
    "---\n---\n",
    "",
  ])
  func preservesExactPrefix(prefix: String) throws {
    let source = try MarkdownBodySource(content: prefix + "# Heading\n")
    #expect(source.document.body == "# Heading\n")
    #expect(source.document.frontMatter.isEmpty)
    #expect(source.render(body: "new\n").utf8.elementsEqual((prefix + "new\n").utf8))
  }

  @Test(arguments: ["---\r\nx: 1\r\n---\r\nbody", "---\nx: 1\n"])
  func retainsExistingDelimiterRecognition(content: String) throws {
    let source = try MarkdownBodySource(content: content)
    #expect(source.document.body.utf8.elementsEqual(content.utf8))
    #expect(source.render(body: content).utf8.elementsEqual(content.utf8))
  }
}
