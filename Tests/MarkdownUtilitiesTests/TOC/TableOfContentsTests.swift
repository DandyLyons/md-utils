//
//  TableOfContentsTests.swift
//  MarkdownUtilitiesTests
//

import Testing
@testable import MarkdownUtilities

@Suite("TableOfContents Tests")
struct TableOfContentsTests {

  @Test
  func `Initialize empty TableOfContents`() async throws {
    let toc = TableOfContents(entries: [], minLevel: 1, maxLevel: 6)

    #expect(toc.isEmpty)
    #expect(toc.totalCount == 0)
    #expect(toc.flatEntries.isEmpty)
    #expect(toc.minLevel == 1)
    #expect(toc.maxLevel == 6)
  }

  @Test
  func `Initialize TableOfContents with flat entries`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Introduction"),
      TOCEntry(level: 2, text: "Getting Started"),
      TOCEntry(level: 2, text: "Configuration"),
    ]

    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 2)

    #expect(!toc.isEmpty)
    #expect(toc.totalCount == 3)
    #expect(toc.entries.count == 3)
    #expect(toc.flatEntries.count == 3)
  }

  @Test
  func `Initialize TableOfContents with hierarchical entries`() async throws {
    let child1 = TOCEntry(level: 3, text: "Step 1")
    let child2 = TOCEntry(level: 3, text: "Step 2")
    let parent = TOCEntry(
      level: 2,
      text: "Getting Started",
      children: [child1, child2]
    )

    let toc = TableOfContents(entries: [parent], minLevel: 2, maxLevel: 3)

    #expect(toc.entries.count == 1)
    #expect(toc.totalCount == 3)
    #expect(toc.flatEntries.count == 3)
    #expect(toc.flatEntries[0].text == "Getting Started")
    #expect(toc.flatEntries[1].text == "Step 1")
    #expect(toc.flatEntries[2].text == "Step 2")
  }

  @Test
  func `Filter TableOfContents by level range`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Title"),
      TOCEntry(level: 2, text: "Section"),
      TOCEntry(level: 3, text: "Subsection"),
      TOCEntry(level: 4, text: "Deep"),
    ]

    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 4)
    let filtered = toc.filtered(minLevel: 2, maxLevel: 3)

    #expect(filtered.totalCount == 2)
    #expect(filtered.flatEntries[0].text == "Section")
    #expect(filtered.flatEntries[1].text == "Subsection")
    #expect(filtered.minLevel == 2)
    #expect(filtered.maxLevel == 3)
  }

  @Test
  func `Filter TableOfContents to empty result`() async throws {
    let entries = [
      TOCEntry(level: 1, text: "Title"),
      TOCEntry(level: 2, text: "Section"),
    ]

    let toc = TableOfContents(entries: entries, minLevel: 1, maxLevel: 2)
    let filtered = toc.filtered(minLevel: 5, maxLevel: 6)

    #expect(filtered.isEmpty)
    #expect(filtered.totalCount == 0)
  }

  @Test
  func `TableOfContents equality`() async throws {
    let entries = [TOCEntry(level: 1, text: "Test")]
    let toc1 = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)
    let toc2 = TableOfContents(entries: entries, minLevel: 1, maxLevel: 1)
    let toc3 = TableOfContents(entries: [], minLevel: 1, maxLevel: 1)

    #expect(toc1 == toc2)
    #expect(toc1 != toc3)
  }
}
