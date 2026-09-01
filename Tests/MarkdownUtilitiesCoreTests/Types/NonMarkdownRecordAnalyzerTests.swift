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

  @Test(arguments: [
    ("# ---\n# component: networking\n# $md-utils:\n#   typeHints: [Component]\n# ---\nenabled = true\n", FrontMatterFormat.yaml),
    ("# +++\n# component = \"networking\"\n# [\"$md-utils\"]\n# typeHints = [\"Component\"]\n# +++\nenabled = true\n", FrontMatterFormat.toml),
  ])
  func `line-comment analysis exposes metadata and removes the block from raw body`(
    source: String,
    format: FrontMatterFormat
  ) async {
    let analyzed = await MarkdownRecordAnalyzer.analyze(
      MarkdownRecord(content: source),
      contentKind: .lineComment
    )

    #expect(analyzed.hasFrontmatter)
    #expect(analyzed.userFrontmatter?["component"] == .string("networking"))
    #expect(analyzed.systemTypeHints == [MarkdownTypeHint(name: "Component")])
    #expect(analyzed.body.contains("enabled = true"))
    #expect(analyzed.body.contains(format.delimiter) == false)
    #expect(analyzed.supportsMarkdownStructure == false)
    #expect(analyzed.parseDiagnostics.isEmpty)
  }

  @Test(arguments: [
    (
      "# ---\n# valid: true\n#invalid\n# ---\nSECRET_STYLE_HOST_LINE=unchanged\n",
      "record.frontmatter.line-comment.invalid-prefix"
    ),
    (
      "# ---\n# valid: true\n# +++\nSECRET_STYLE_HOST_LINE=unchanged\n",
      "record.frontmatter.line-comment.mismatched-delimiter"
    ),
  ])
  func `recognized malformed blocks are excluded with stable structural diagnostics`(
    source: String,
    diagnosticCode: String
  ) async {
    let analyzed = await MarkdownRecordAnalyzer.analyze(
      MarkdownRecord(content: source),
      contentKind: .lineComment
    )

    #expect(analyzed.hasFrontmatter)
    #expect(analyzed.body == "\nSECRET_STYLE_HOST_LINE=unchanged\n")
    #expect(analyzed.parseDiagnostics.map(\.code) == [diagnosticCode])
    #expect(analyzed.parseDiagnostics.first?.message.contains("SECRET_STYLE_HOST_LINE") == false)
  }

  @Test
  func `rules kind resolver uses complete basename precedence`() {
    if case .lineComment = MarkdownRecordContentKind.rulesKind(
      forFileName: "requirements.txt"
    ) {
      #expect(Bool(true))
    } else {
      Issue.record("requirements.txt should use line-comment frontmatter")
    }
    if case .plainText = MarkdownRecordContentKind.rulesKind(forFileName: "notes.txt") {
      #expect(Bool(true))
    } else {
      Issue.record("ordinary .txt should remain plain text")
    }
    if case .wrapped(.pythonDocstring) = MarkdownRecordContentKind.rulesKind(
      forFileName: "script.py"
    ) {
      #expect(Bool(true))
    } else {
      Issue.record("wrapped mappings should remain authoritative")
    }
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
