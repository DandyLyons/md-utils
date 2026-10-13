import Testing
@testable import MarkdownUtilitiesCore

@Suite("Wikilink parsing contexts")
struct WikilinkParsingContextTests {
  @Test(arguments: WikilinkParsingContext.allCases)
  func discoveryAgreesWithWholeValue(context: WikilinkParsingContext) throws {
    let sources = [
      "[[Note\\|Alias]]", "![[Note#Heading\\|Alias]]", "[[#Heading]]",
      "![[Note#^abc-1|Alias]]",
      "[[Note|]]", "[[Note|Alias|More]]", "[[Note\\\\|Alias]]",
    ]
    for source in sources {
      let discovered = try #require(WikilinkScanner.scan("See \(source) now", context: context).first)
      #expect(try Wikilink.parse(source, context: context) == discovered)
      #expect(discovered.rawValue == source)
      #expect(throws: (any Error).self) {
        try Wikilink.parse("See \(source)", context: context)
      }
      #expect(throws: (any Error).self) {
        try Wikilink.parse("\(source) trailing", context: context)
      }
    }
    let escaped = try Wikilink.parse("[[Note\\|Alias]]", context: context)
    #expect(escaped.target == (context == .markdownTable ? "Note" : "Note|Alias"))
    #expect(escaped.displayText == (context == .markdownTable ? "Alias" : nil))
  }

  @Test(arguments: ["[[ ]]", "[[#]]", "[[Bob#^]]", "[[Bob#^bad_id]]", "[[Bob\nAlice]]", "[[Bob\0Alice]]"])
  func strictValidityIsShared(source: String) throws {
    for context in [WikilinkParsingContext.standard, .markdownTable] {
      #expect(throws: (any Error).self) { try Wikilink.parse(source, context: context) }
      #expect(WikilinkScanner.scan(source, context: context).isEmpty)
      #expect(WikilinkScanner.scan("\(source) [[Valid]]", context: context).map(\.target) == ["Valid"])
      var input = source[...]
      #expect(throws: (any Error).self) { try WikilinkParser(context: context).parse(&input) }
      #expect(input == source[...])
    }
    let legacy = try Wikilink.parse(source, context: .legacy)
    #expect(WikilinkScanner.scan(source, context: .legacy) == [legacy])
  }

  @Test
  func tableEscapingChangesBlockValidityConsistently() throws {
    let source = "![[Note#^abc-1\\|Alias]]"
    #expect(throws: (any Error).self) { try Wikilink.parse(source, context: .standard) }
    #expect(WikilinkScanner.scan(source, context: .standard).isEmpty)
    let table = try Wikilink.parse(source, context: .markdownTable)
    #expect(table.anchor == .blockID("abc-1"))
    #expect(table.displayText == "Alias")
    #expect(table.isEmbed)
    #expect(WikilinkScanner.scan(source, context: .markdownTable) == [table])
  }

  @Test
  func scalarAndDefaultDiscoveryUseStandardText() throws {
    let source = "[[Note\\|Alias]]"
    let parsed = try Wikilink.parse(source)
    #expect(WikilinkScanner.scan(source) == [parsed])
    let scalar = try MarkdownSemanticScalar.parse(source, format: "Wikilink")
    guard case .wikilink(let scalarLink) = scalar.value else {
      Issue.record("Expected a Wikilink typed value")
      return
    }
    #expect(scalarLink == parsed)
    #expect(parsed.target == "Note|Alias")
    #expect(parsed.displayText == nil)
  }

  @Test
  func documentForwardsContextAndPreservesLegacyDefault() throws {
    let document = try MarkdownDocument(content: """
    ---
    nested:
      links:
        - 'See [[Note\\|Alias]] and [[#]]'
    ---
    See [[Note\\|Alias]] and [[#]]
    """)
    #expect(document.wikilinks().count == 4)
    #expect(document.wikilinks(context: .standard).map(\.target) == ["Note|Alias", "Note|Alias"])
    for context in WikilinkParsingContext.allCases {
      #expect(document.frontMatterWikilinks(context: context) == document.bodyWikilinks(context: context))
      for occurrence in document.wikilinks(context: context) {
        #expect(try Wikilink.parse(occurrence.rawValue, context: context) == occurrence)
      }
    }
    #expect(document.wikilinks(context: .markdownTable).map(\.displayText) == ["Alias", "Alias"])
  }
}
