//
//  TOCRendererTests.swift
//  MarkdownUtilitiesTests
//

import Testing
@testable import MarkdownUtilities

@Suite("TOC Renderer Tests")
struct TOCRendererTests {

  // MARK: - Markdown Bullet Links Tests

  @Test
  func `Render md-bullet-links format`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction", slug: "introduction"),
      TOCEntry(level: 2, text: "Getting Started", slug: "getting-started"),
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(toc, as: .mdBulletLinks)

    let expected = """
      - [Introduction](#introduction)
      - [Getting Started](#getting-started)
      """

    #expect(rendered == expected)
  }

  @Test
  func `Render md-bullet-links with hierarchical structure`() async throws {
    let child = TOCEntry(level: 2, text: "Subsection", slug: "subsection")
    let parent = TOCEntry(
      level: 1,
      text: "Section",
      slug: "section",
      children: [child]
    )

    let toc = TableOfContents(entries: [parent], minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(toc, as: .mdBulletLinks)

    let expected = """
      - [Section](#section)
        - [Subsection](#subsection)
      """

    #expect(rendered == expected)
  }

  // MARK: - Markdown Only Headings Tests

  @Test
  func `Render md-only-headings format`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Main Title"),
      TOCEntry(level: 2, text: "Section One"),
      TOCEntry(level: 3, text: "Subsection"),
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 3)

    let rendered = TOCRenderer.render(toc, as: .mdOnlyHeadings)

    let expected = """
      # Main Title
      ## Section One
      ### Subsection
      """

    #expect(rendered == expected)
  }

  @Test
  func `Render md-only-headings with hierarchical structure`() async throws {
    let child = TOCEntry(level: 3, text: "Deep Section")
    let parent = TOCEntry(
      level: 2,
      text: "Parent Section",
      children: [child]
    )

    let toc = TableOfContents(entries: [parent], minLevel: 2, maxLevel: 3)

    let rendered = TOCRenderer.render(toc, as: .mdOnlyHeadings)

    let expected = """
      ## Parent Section
      ### Deep Section
      """

    #expect(rendered == expected)
  }

  // MARK: - Tree Format Tests

  @Test
  func `Render tree format with single level`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "First"),
      TOCEntry(level: 1, text: "Second"),
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .tree)

    let expected = """
      ├── First
      └── Second
      """

    #expect(rendered == expected)
  }

  @Test
  func `Render tree format with hierarchical structure`() async throws {
    let child1 = TOCEntry(level: 2, text: "Child 1")
    let child2 = TOCEntry(level: 2, text: "Child 2")
    let parent = TOCEntry(
      level: 1,
      text: "Parent",
      children: [child1, child2]
    )

    let toc = TableOfContents(entries: [parent], minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(toc, as: .tree)

    let expected = """
      └── Parent
          ├── Child 1
          └── Child 2
      """

    #expect(rendered == expected)
  }

  @Test
  func `Render tree format with deep hierarchy`() async throws {
    let grandchild = TOCEntry(level: 3, text: "Grandchild")
    let child = TOCEntry(level: 2, text: "Child", children: [grandchild])
    let parent = TOCEntry(level: 1, text: "Parent", children: [child])

    let toc = TableOfContents(entries: [parent], minLevel: 1, maxLevel: 3)

    let rendered = TOCRenderer.render(toc, as: .tree)

    let expected = """
      └── Parent
          └── Child
              └── Grandchild
      """

    #expect(rendered == expected)
  }

  // MARK: - Plain Text Tests

  @Test
  func `Render plain format with indentation`() async throws {
    let child = TOCEntry(level: 2, text: "Subsection")
    let parent = TOCEntry(level: 1, text: "Section", children: [child])

    let toc = TableOfContents(entries: [parent], minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(toc, as: .plain)

    let expected = """
      Section
        Subsection
      """

    #expect(rendered == expected)
  }

  // MARK: - JSON Tests

  @Test
  func `Render json format compact`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction", slug: "introduction")
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .json)

    // Compact JSON - just verify it's valid JSON and contains expected data
    #expect(rendered.contains("\"text\":\"Introduction\""))
    #expect(rendered.contains("\"level\":1"))
    #expect(rendered.contains("\"slug\":\"introduction\""))
  }

  @Test
  func `Render json-pretty format`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction", slug: "introduction")
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .jsonPretty)

    // Pretty JSON should have newlines and indentation
    #expect(rendered.contains("\n"))
    #expect(rendered.contains("  "))
    #expect(rendered.contains("\"text\" : \"Introduction\""))
  }

  @Test
  func `Render json with hierarchical structure`() async throws {
    let child = TOCEntry(level: 2, text: "Subsection", slug: "subsection")
    let parent = TOCEntry(
      level: 1,
      text: "Section",
      slug: "section",
      children: [child]
    )

    let toc = TableOfContents(entries: [parent], minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(toc, as: .jsonPretty)

    #expect(rendered.contains("\"text\" : \"Section\""))
    #expect(rendered.contains("\"text\" : \"Subsection\""))
    #expect(rendered.contains("\"children\""))
  }

  // MARK: - HTML Tests

  @Test
  func `Render html format with simple list`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction", slug: "introduction"),
      TOCEntry(level: 1, text: "Getting Started", slug: "getting-started"),
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .html)

    #expect(rendered.contains("<ul>"))
    #expect(rendered.contains("</ul>"))
    #expect(rendered.contains("<li><a href=\"#introduction\">Introduction</a></li>"))
    #expect(
      rendered.contains("<li><a href=\"#getting-started\">Getting Started</a></li>"
      ))
  }

  @Test
  func `Render html with hierarchical structure`() async throws {
    let child = TOCEntry(level: 2, text: "Subsection", slug: "subsection")
    let parent = TOCEntry(
      level: 1,
      text: "Section",
      slug: "section",
      children: [child]
    )

    let toc = TableOfContents(entries: [parent], minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(toc, as: .html)

    // Should have nested <ul> tags
    #expect(rendered.contains("<ul>"))
    #expect(rendered.contains("</ul>"))
    #expect(rendered.contains("<li><a href=\"#section\">Section</a>"))
    #expect(rendered.contains("<li><a href=\"#subsection\">Subsection</a></li>"))
  }

  @Test
  func `Render html escapes special characters`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "A & B < C > D", slug: "a-b-c-d")
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .html)

    #expect(rendered.contains("A &amp; B &lt; C &gt; D"))
  }

  @Test
  func `Render html without slugs`() async throws {
    let entries = [TOCEntry(level: 1, text: "Introduction", slug: nil)]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .html)

    #expect(rendered.contains("<li>Introduction</li>"))
    #expect(!rendered.contains("<a href"))
  }

  // MARK: - Empty TOC Tests

  @Test
  func `Render empty TOC in md-bullet-links`() async throws {
    let toc = TableOfContents(entries: [], minLevel: 1, maxLevel: 6)

    let rendered = TOCRenderer.render(toc, as: .mdBulletLinks)

    #expect(rendered == "")
  }

  @Test
  func `Render empty TOC in html`() async throws {
    let toc = TableOfContents(entries: [], minLevel: 1, maxLevel: 6)

    let rendered = TOCRenderer.render(toc, as: .html)

    #expect(rendered == "<ul>\n</ul>")
  }
}
