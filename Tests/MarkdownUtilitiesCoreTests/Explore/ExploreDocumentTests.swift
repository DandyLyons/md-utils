import Testing
@testable import MarkdownUtilitiesCore

@Suite("ExploreDocument Tests")
struct ExploreDocumentTests {
  @Test
  func `build preserves frontmatter metadata and source range`() async throws {
    let content = """
      ---
      title: Test
      tags:
        - swift
      ---
      # Intro
      Body.
      """

    let document = try await ExploreDocument.build(from: content)
    let frontmatter = try #require(document.frontmatter)

    #expect(frontmatter.lineRange == 1...5)
    #expect(frontmatter.fieldCount == 2)
    #expect(document.sourceText(in: frontmatter.lineRange).contains("title: Test"))
  }

  @Test
  func `build uses source line numbers after frontmatter`() async throws {
    let content = """
      ---
      title: Test
      ---

      # Intro
      Body.
      ## Child
      More body.
      """

    let document = try await ExploreDocument.build(from: content)
    let intro = try #require(document.sections.first)

    #expect(intro.headingLine == 5)
    #expect(intro.fullLineRange == 5...8)
    #expect(intro.bodyLineRange == 6...6)
    #expect(intro.children.first?.headingLine == 7)
  }

  @Test
  func `build records heading paths and top heading level`() async throws {
    let content = """
      ### Root
      body
      #### Child
      child body
      ### Sibling
      """

    let document = try await ExploreDocument.build(from: content)
    let root = try #require(document.sections.first)
    let child = try #require(root.children.first)

    #expect(document.topHeadingLevel == 3)
    #expect(root.path == ["Root"])
    #expect(child.path == ["Root", "Child"])
  }

  @Test
  func `build detects preamble after frontmatter`() async throws {
    let content = """
      ---
      title: Test
      ---
      Opening paragraph.

      # Intro
      """

    let document = try await ExploreDocument.build(from: content)
    let preamble = try #require(document.preamble)

    #expect(preamble.lineRange == 4...5)
    #expect(preamble.wordCount == 2)
  }
}
