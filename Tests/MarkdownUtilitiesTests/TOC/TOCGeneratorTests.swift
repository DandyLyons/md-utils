//
//  TOCGeneratorTests.swift
//  MarkdownUtilitiesTests
//

import Testing
import MarkdownSyntax
@testable import MarkdownUtilities

@Suite("TOC Generation Tests")
struct TOCGeneratorTests {

  @Test
  func `Generate TOC from simple headings`() async throws {
    let content = "# H1\n## H2\n### H3"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let toc = try TOCGenerator.generate(from: root)

    #expect(toc.totalCount == 3)
    let entries = toc.flatEntries
    #expect(entries[0].level == 1)
    #expect(entries[0].text == "H1")
    #expect(entries[1].level == 2)
    #expect(entries[1].text == "H2")
    #expect(entries[2].level == 3)
    #expect(entries[2].text == "H3")
  }

  @Test
  func `Generate TOC with slug generation`() async throws {
    let content = "# Hello World\n## Getting Started"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let toc = try TOCGenerator.generate(from: root)

    let entries = toc.flatEntries
    #expect(entries[0].slug == "hello-world")
    #expect(entries[1].slug == "getting-started")
  }

  @Test
  func `Generate TOC without slugs`() async throws {
    let content = "# Hello World\n## Getting Started"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = TOCGenerator.Options(generateSlugs: false)
    let toc = try TOCGenerator.generate(from: root, options: options)

    let entries = toc.flatEntries
    #expect(entries[0].slug == nil)
    #expect(entries[1].slug == nil)
  }

  @Test
  func `Generate TOC with duplicate heading text`() async throws {
    let content = "# Section\n## Section\n### Section"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let toc = try TOCGenerator.generate(from: root)

    let entries = toc.flatEntries
    #expect(entries[0].slug == "section")
    #expect(entries[1].slug == "section-1")
    #expect(entries[2].slug == "section-2")
  }

  @Test
  func `Generate flat TOC structure`() async throws {
    let content = "# H1\n## H2\n### H3\n## H2-2"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = TOCGenerator.Options(hierarchical: false)
    let toc = try TOCGenerator.generate(from: root, options: options)

    #expect(toc.entries.count == 4)
    #expect(!toc.entries[0].hasChildren)
    #expect(!toc.entries[1].hasChildren)
  }

  @Test
  func `Generate hierarchical TOC structure`() async throws {
    let content = "# H1\n## H2\n### H3\n## H2-2"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = TOCGenerator.Options(hierarchical: true)
    let toc = try TOCGenerator.generate(from: root, options: options)

    // Should have 1 top-level entry (H1)
    #expect(toc.entries.count == 1)

    let h1 = toc.entries[0]
    #expect(h1.level == 1)
    #expect(h1.hasChildren)
    #expect(h1.children.count == 2)  // Two H2s

    let h2First = h1.children[0]
    #expect(h2First.level == 2)
    #expect(h2First.hasChildren)
    #expect(h2First.children.count == 1)  // One H3

    let h3 = h2First.children[0]
    #expect(h3.level == 3)

    let h2Second = h1.children[1]
    #expect(h2Second.level == 2)
    #expect(!h2Second.hasChildren)
  }

  @Test
  func `Filter TOC by level range`() async throws {
    let content = "# H1\n## H2\n### H3\n#### H4"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = TOCGenerator.Options(minLevel: 2, maxLevel: 3)
    let toc = try TOCGenerator.generate(from: root, options: options)

    #expect(toc.totalCount == 2)
    let entries = toc.flatEntries
    #expect(entries[0].level == 2)
    #expect(entries[1].level == 3)
    #expect(toc.minLevel == 2)
    #expect(toc.maxLevel == 3)
  }

  @Test
  func `Generate empty TOC from document with no headings`() async throws {
    let content = "This is just a paragraph."
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let toc = try TOCGenerator.generate(from: root)

    #expect(toc.isEmpty)
    #expect(toc.totalCount == 0)
  }

  @Test
  func `Generate empty TOC when level filter excludes all headings`() async throws {
    let content = "# H1\n## H2"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = TOCGenerator.Options(minLevel: 5, maxLevel: 6)
    let toc = try TOCGenerator.generate(from: root, options: options)

    #expect(toc.isEmpty)
  }

  @Test
  func `Include positions when requested`() async throws {
    let content = "# H1\n## H2"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = TOCGenerator.Options(includePositions: true)
    let toc = try TOCGenerator.generate(from: root, options: options)

    let entries = toc.flatEntries
    #expect(entries[0].position != nil)
    #expect(entries[1].position != nil)
  }

  @Test
  func `Exclude positions by default`() async throws {
    let content = "# H1\n## H2"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let toc = try TOCGenerator.generate(from: root)

    let entries = toc.flatEntries
    #expect(entries[0].position == nil)
    #expect(entries[1].position == nil)
  }

  @Test
  func `Invalid minLevel throws error`() async throws {
    let content = "# H1"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = TOCGenerator.Options(minLevel: 0)

    #expect(throws: TOCGeneratorError.self) {
      try TOCGenerator.generate(from: root, options: options)
    }
  }

  @Test
  func `Invalid maxLevel throws error`() async throws {
    let content = "# H1"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = TOCGenerator.Options(maxLevel: 7)

    #expect(throws: TOCGeneratorError.self) {
      try TOCGenerator.generate(from: root, options: options)
    }
  }

  @Test
  func `minLevel greater than maxLevel throws error`() async throws {
    let content = "# H1"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = TOCGenerator.Options(minLevel: 4, maxLevel: 2)

    #expect(throws: TOCGeneratorError.self) {
      try TOCGenerator.generate(from: root, options: options)
    }
  }

  @Test
  func `Non-contiguous heading levels are handled correctly`() async throws {
    let content = "# H1\n### H3\n##### H5"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let toc = try TOCGenerator.generate(from: root)

    #expect(toc.totalCount == 3)
    let entries = toc.flatEntries
    #expect(entries[0].level == 1)
    #expect(entries[1].level == 3)
    #expect(entries[2].level == 5)
  }

  @Test
  func `Complex document with mixed content`() async throws {
    let content = """
      # Main Title

      Some paragraph text.

      ## Section 1

      - List item 1
      - List item 2

      ### Subsection 1.1

      More text.

      ## Section 2

      ```
      code block
      ```

      ### Subsection 2.1
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let toc = try TOCGenerator.generate(from: root)

    #expect(toc.totalCount == 5)
    let entries = toc.flatEntries
    #expect(entries[0].text == "Main Title")
    #expect(entries[1].text == "Section 1")
    #expect(entries[2].text == "Subsection 1.1")
    #expect(entries[3].text == "Section 2")
    #expect(entries[4].text == "Subsection 2.1")
  }
}
