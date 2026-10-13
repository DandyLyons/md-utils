import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("Wikilink occurrence provenance")
struct WikilinkOccurrenceTests {
  @Test
  func `Nested paths distinguish literal punctuation and preserve duplicates`() throws {
    let document = MarkdownDocument(
      frontMatter: FrontMatter([
        ("related", .array([
          .string("[[A]] [[A]]"),
          .array([.object(FrontMatter([("x.y[0]", .string("![[B#part|label]]"))]))]),
        ])),
        ("related[0]", .string("[[C]]")),
        ("spouse", .string("[[A]]")),
        ("ignored", .boolean(true)),
      ]),
      body: "[[Body]]",
    )
    let occurrences = document.wikilinkOccurrences()
    #expect(occurrences.map(\.link) == document.wikilinks())
    #expect(occurrences.map(\.origin) == [
      .frontMatter(path: [.key("related"), .index(0)]),
      .frontMatter(path: [.key("related"), .index(0)]),
      .frontMatter(path: [.key("related"), .index(1), .index(0), .key("x.y[0]")]),
      .frontMatter(path: [.key("related[0]")]),
      .frontMatter(path: [.key("spouse")]),
      .body,
    ])
    #expect(occurrences[0].utf8Range == 0..<5)
    #expect(occurrences[1].utf8Range == 6..<11)
    #expect(occurrences[2].link.anchor == .heading("part"))
    #expect(occurrences[2].link.displayText == "label")
    #expect(occurrences[2].link.isEmbed)
    #expect(occurrences.allSatisfy { $0.source == nil && $0.sourceUTF8Range == nil })
  }

  @Test(arguments: [
    "---\nspouse: \"\\u005B\\u005BA#part|label]]\"\nrelated: >-\n  é [[B]]\n  [[B]]\n---\n👋 ![[Body]]",
    "+++\nspouse = \"\\u005B\\u005BA#part|label]]\"\nrelated = \"\"\"é [[B]]\n[[B]]\"\"\"\n+++\n👋 ![[Body]]",
  ])
  func `Decoded coordinates never masquerade as source bytes`(content: String) throws {
    let record = MarkdownRecord(
      identity: .init(rawValue: "source"), content: content,
      context: .init(path: try MarkdownRecordPath("notes/source.md")),
      revision: .init(rawValue: "revision-1"),
    )
    let occurrences = try record.wikilinkOccurrences(context: .standard)
    #expect(occurrences.count == 4)
    for occurrence in occurrences {
      #expect(occurrence.source == record)
      #expect(occurrence.context == .standard)
      let matched = String(decoding: Array(occurrence.text.utf8)[occurrence.utf8Range], as: UTF8.self)
      #expect(matched == occurrence.link.rawValue)
      switch occurrence.origin {
      case .frontMatter:
        #expect(occurrence.sourceUTF8Range == nil)
      case .body:
        let range = try #require(occurrence.sourceUTF8Range)
        #expect(String(decoding: Array(content.utf8)[range], as: UTF8.self) == "![[Body]]")
      }
    }
    let encoded = try JSONEncoder().encode(occurrences)
    #expect(try JSONDecoder().decode([WikilinkOccurrence].self, from: encoded) == occurrences)
  }

  @Test(arguments: WikilinkParsingContext.allCases)
  func `Scanner ranges survive failed candidates unicode and adjacent matches`(context: WikilinkParsingContext) {
    let text = "é 👋 [[broken [[A]]![[B#part|label]][[A]]"
    let matches = WikilinkScanner.scanOccurrences(text, context: context)
    #expect(matches.map(\.link.target) == ["A", "B", "A"])
    for match in matches {
      #expect(String(decoding: Array(text.utf8)[match.utf8Range], as: UTF8.self) == match.link.rawValue)
    }
    #expect(WikilinkScanner.scanOccurrences("[[unfinished", context: context).isEmpty)
    #expect(WikilinkScanner.scanOccurrences("", context: context).isEmpty)
  }

  @Test
  func `Body only record ranges start at zero and invalid frontmatter throws`() throws {
    let occurrences = try MarkdownRecord(content: "[[A]]").wikilinkOccurrences()
    let occurrence = try #require(occurrences.first)
    #expect(occurrence.sourceUTF8Range == 0..<5)
    #expect(throws: YAMLConversionError.notAMapping) {
      try MarkdownRecord(content: "---\n- item\n---\n[[Body]]").wikilinkOccurrences()
    }
  }
}
