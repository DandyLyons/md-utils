//
//  TOCRendererTests.swift
//  MarkdownUtilitiesTests
//

import Testing
@testable import MarkdownUtilities

@Suite("TOC Renderer Tests")
struct TOCRendererTests {

  // MARK: - Markdown Rendering Tests

  @Test
  func `Render markdown with unordered links`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction", slug: "introduction"),
      TOCEntry(level: 2, text: "Getting Started", slug: "getting-started"),
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(
      toc,
      as: .markdown(style: .unorderedLinks)
    )

    let expected = """
      - [Introduction](#introduction)
      - [Getting Started](#getting-started)
      """

    #expect(rendered == expected)
  }

  @Test
  func `Render markdown with ordered links`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction", slug: "introduction"),
      TOCEntry(level: 2, text: "Getting Started", slug: "getting-started"),
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(
      toc,
      as: .markdown(style: .orderedLinks)
    )

    let expected = """
      1. [Introduction](#introduction)
      1. [Getting Started](#getting-started)
      """

    #expect(rendered == expected)
  }

  @Test
  func `Render markdown with unordered plain`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction"),
      TOCEntry(level: 2, text: "Getting Started"),
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(
      toc,
      as: .markdown(style: .unorderedPlain)
    )

    let expected = """
      - Introduction
      - Getting Started
      """

    #expect(rendered == expected)
  }

  @Test
  func `Render markdown with ordered plain`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction"),
      TOCEntry(level: 2, text: "Getting Started"),
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(
      toc,
      as: .markdown(style: .orderedPlain)
    )

    let expected = """
      1. Introduction
      1. Getting Started
      """

    #expect(rendered == expected)
  }

  @Test
  func `Render markdown with hierarchical structure`() async throws {
    let child = TOCEntry(level: 2, text: "Subsection", slug: "subsection")
    let parent = TOCEntry(
      level: 1,
      text: "Section",
      slug: "section",
      children: [child]
    )

    let toc = TableOfContents(entries: [parent], minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(
      toc,
      as: .markdown(style: .unorderedLinks)
    )

    let expected = """
      - [Section](#section)
        - [Subsection](#subsection)
      """

    #expect(rendered == expected)
  }

  // MARK: - Plain Text Rendering Tests

  @Test
  func `Render plain text indented`() async throws {
    let child = TOCEntry(level: 2, text: "Subsection")
    let parent = TOCEntry(level: 1, text: "Section", children: [child])

    let toc = TableOfContents(entries: [parent], minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(
      toc,
      as: .plainText(style: .indented)
    )

    let expected = """
      Section
        Subsection
      """

    #expect(rendered == expected)
  }

  @Test
  func `Render plain text flat with levels`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction"),
      TOCEntry(level: 2, text: "Getting Started"),
      TOCEntry(level: 3, text: "Installation"),
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 3)

    let rendered = TOCRenderer.render(
      toc,
      as: .plainText(style: .flatWithLevels)
    )

    let expected = """
      [1] Introduction
      [2] Getting Started
      [3] Installation
      """

    #expect(rendered == expected)
  }

  // MARK: - JSON Rendering Tests

  @Test
  func `Render JSON compact`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction", slug: "introduction")
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .json(pretty: false))

    // Compact JSON - just verify it's valid JSON and contains expected data
    #expect(rendered.contains("\"text\":\"Introduction\""))
    #expect(rendered.contains("\"level\":1"))
    #expect(rendered.contains("\"slug\":\"introduction\""))
  }

  @Test
  func `Render JSON pretty`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction", slug: "introduction")
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .json(pretty: true))

    // Pretty JSON should have newlines and indentation
    #expect(rendered.contains("\n"))
    #expect(rendered.contains("  "))
    #expect(rendered.contains("\"text\" : \"Introduction\""))
  }

  @Test
  func `Render JSON with hierarchical structure`() async throws {
    let child = TOCEntry(level: 2, text: "Subsection", slug: "subsection")
    let parent = TOCEntry(
      level: 1,
      text: "Section",
      slug: "section",
      children: [child]
    )

    let toc = TableOfContents(entries: [parent], minLevel: 1, maxLevel: 2)

    let rendered = TOCRenderer.render(toc, as: .json(pretty: true))

    #expect(rendered.contains("\"text\" : \"Section\""))
    #expect(rendered.contains("\"text\" : \"Subsection\""))
    #expect(rendered.contains("\"children\""))
  }

  // MARK: - HTML Rendering Tests

  @Test
  func `Render HTML with simple list`() async throws {
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
  func `Render HTML with hierarchical structure`() async throws {
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
  func `Render HTML escapes special characters`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "A & B < C > D", slug: "a-b-c-d")
    ]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .html)

    #expect(rendered.contains("A &amp; B &lt; C &gt; D"))
  }

  @Test
  func `Render HTML without slugs`() async throws {
    let entries = [TOCEntry(level: 1, text: "Introduction", slug: nil)]
    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)

    let rendered = TOCRenderer.render(toc, as: .html)

    #expect(rendered.contains("<li>Introduction</li>"))
    #expect(!rendered.contains("<a href"))
  }

  // MARK: - Empty TOC Tests

  @Test
  func `Render empty TOC in markdown`() async throws {
    let toc = TableOfContents(entries: [], minLevel: 1, maxLevel: 6)

    let rendered = TOCRenderer.render(
      toc,
      as: .markdown(style: .unorderedLinks)
    )

    #expect(rendered == "")
  }

  @Test
  func `Render empty TOC in HTML`() async throws {
    let toc = TableOfContents(entries: [], minLevel: 1, maxLevel: 6)

    let rendered = TOCRenderer.render(toc, as: .html)

    #expect(rendered == "<ul>\n</ul>")
  }
}
