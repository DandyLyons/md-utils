import Testing
@testable import MarkdownUtilitiesCore

@Suite("Non-Markdown record analysis")
struct NonMarkdownRecordAnalyzerTests {
  @Test
  func `wrapped analysis exposes YAML and removes the wrapper from raw body`() async throws {
    let source = """
      /*
      ---
      component: networking
      $md-utils:
        typeHints: [Component]
      wrapperOnly: hidden
      ---
      */

      @MainActor
      struct APIClient {}
      """

    let analyzed = await MarkdownRecordAnalyzer.analyze(
      MarkdownRecord(content: source),
      contentKind: .wrapped(.cBlock)
    )

    #expect(analyzed.hasFrontmatter)
    #expect(analyzed.userFrontmatter?["component"] == .string("networking"))
    #expect(analyzed.systemTypeHints == [MarkdownTypeHint(name: "Component")])
    #expect(analyzed.body.contains("@MainActor"))
    #expect(analyzed.body.contains("wrapperOnly") == false)
    #expect(analyzed.supportsMarkdownStructure == false)
  }

  @Test
  func `wrapped analysis reports the second complete block`() async {
    let source = "/*\n---\ntitle: First\n---\n*/\n\n/*\n---\ntitle: Second\n---\n*/\n"

    let analyzed = await MarkdownRecordAnalyzer.analyze(
      MarkdownRecord(content: source),
      contentKind: .wrapped(.cBlock)
    )

    #expect(analyzed.parseDiagnostics.map(\.code) == ["record.frontmatter.multiple-blocks"])
    #expect(analyzed.parseDiagnostics.first?.message.contains("line 7") == true)
  }

  @Test
  func `plain text supports leading frontmatter without Markdown structure`() async {
    let analyzed = await MarkdownRecordAnalyzer.analyze(
      MarkdownRecord(content: "---\nkind: notes\n---\n# Text heading\n"),
      contentKind: .plainText
    )

    #expect(analyzed.hasFrontmatter)
    #expect(analyzed.userFrontmatter?["kind"] == .string("notes"))
    #expect(analyzed.headings.isEmpty)
    #expect(analyzed.supportsMarkdownStructure == false)
  }

  @Test
  func `unmapped analysis keeps raw body and records unavailable frontmatter extension`() async {
    let analyzed = await MarkdownRecordAnalyzer.analyze(
      MarkdownRecord(content: "enabled = true\n"),
      contentKind: .unmapped(fileExtension: "toml")
    )

    #expect(analyzed.body == "enabled = true\n")
    #expect(analyzed.hasFrontmatter == false)
    #expect(analyzed.unavailableFrontmatterExtension == "toml")
  }
}
