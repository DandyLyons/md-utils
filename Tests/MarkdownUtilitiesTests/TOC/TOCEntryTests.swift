//
//  TOCEntryTests.swift
//  MarkdownUtilitiesTests
//

import Testing
import MarkdownSyntax
@testable import MarkdownUtilities

@Suite("TOCEntry Tests")
struct TOCEntryTests {

  @Test
  func `Initialize TOCEntry with minimal parameters`() async throws {
    let entry = TOCEntry(level: 1, text: "Introduction")

    #expect(entry.level == 1)
    #expect(entry.text == "Introduction")
    #expect(entry.slug == nil)
    #expect(entry.position == nil)
    #expect(entry.children.isEmpty)
    #expect(!entry.hasChildren)
  }

  @Test
  func `Initialize TOCEntry with all parameters`() async throws {
    let position = Position(
      start: Point(line: 1, column: 1, offset: nil),
      end: Point(line: 1, column: 15, offset: nil),
      indent: nil
    )

    let entry = TOCEntry(
      level: 2,
      text: "Getting Started",
      slug: "getting-started",
      position: position,
      children: []
    )

    #expect(entry.level == 2)
    #expect(entry.text == "Getting Started")
    #expect(entry.slug == "getting-started")
    #expect(entry.position == position)
    #expect(entry.children.isEmpty)
  }

  @Test
  func `TOCEntry with nested children`() async throws {
    let child1 = TOCEntry(level: 3, text: "Subsection A")
    let child2 = TOCEntry(level: 3, text: "Subsection B")

    let parent = TOCEntry(
      level: 2,
      text: "Main Section",
      children: [child1, child2]
    )

    #expect(parent.hasChildren)
    #expect(parent.children.count == 2)
    #expect(parent.children[0].text == "Subsection A")
    #expect(parent.children[1].text == "Subsection B")
  }

  @Test
  func `Flattened entries with no children`() async throws {
    let entry = TOCEntry(level: 1, text: "Single Entry")

    let flattened = entry.flattenedEntries

    #expect(flattened.count == 1)
    #expect(flattened[0] == entry)
  }

  @Test
  func `Flattened entries with nested children`() async throws {
    let grandchild = TOCEntry(level: 4, text: "Deep Section")
    let child1 = TOCEntry(
      level: 3,
      text: "Subsection A",
      children: [grandchild]
    )
    let child2 = TOCEntry(level: 3, text: "Subsection B")
    let parent = TOCEntry(
      level: 2,
      text: "Main Section",
      children: [child1, child2]
    )

    let flattened = parent.flattenedEntries

    #expect(flattened.count == 4)
    #expect(flattened[0].text == "Main Section")
    #expect(flattened[1].text == "Subsection A")
    #expect(flattened[2].text == "Deep Section")
    #expect(flattened[3].text == "Subsection B")
  }

  @Test
  func `TOCEntry equality`() async throws {
    let entry1 = TOCEntry(
      level: 2,
      text: "Section",
      slug: "section"
    )
    let entry2 = TOCEntry(
      level: 2,
      text: "Section",
      slug: "section"
    )
    let entry3 = TOCEntry(
      level: 3,
      text: "Section",
      slug: "section"
    )

    #expect(entry1 == entry2)
    #expect(entry1 != entry3)
  }
}
