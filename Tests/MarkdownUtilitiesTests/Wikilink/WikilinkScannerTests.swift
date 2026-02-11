//
//  WikilinkScannerTests.swift
//  MarkdownUtilitiesTests
//

import Testing
@testable import MarkdownUtilities

@Suite("WikilinkScanner Tests")
struct WikilinkScannerTests {

  // MARK: - Empty / no-wikilink strings

  @Test
  func `Empty string returns empty array`() {
    let results = WikilinkScanner.scan("")
    #expect(results.isEmpty)
  }

  @Test
  func `Plain text returns empty array`() {
    let results = WikilinkScanner.scan("Just some plain text with no links.")
    #expect(results.isEmpty)
  }

  @Test
  func `Standard markdown link is not a wikilink`() {
    let results = WikilinkScanner.scan("[display](url)")
    #expect(results.isEmpty)
  }

  // MARK: - Single wikilinks

  @Test
  func `Single wikilink in prose`() {
    let results = WikilinkScanner.scan("See [[Target]] for details.")
    #expect(results.count == 1)
    #expect(results[0].target == "Target")
  }

  @Test
  func `Single embed in prose`() {
    let results = WikilinkScanner.scan("Here is ![[Image.png]] inline.")
    #expect(results.count == 1)
    #expect(results[0].target == "Image.png")
    #expect(results[0].isEmbed == true)
  }

  // MARK: - Multiple wikilinks

  @Test
  func `Multiple wikilinks in prose`() {
    let text = "Link to [[Page A]] and [[Page B]] and [[Page C]]."
    let results = WikilinkScanner.scan(text)

    #expect(results.count == 3)
    #expect(results[0].target == "Page A")
    #expect(results[1].target == "Page B")
    #expect(results[2].target == "Page C")
  }

  @Test
  func `Adjacent wikilinks`() {
    let results = WikilinkScanner.scan("[[A]][[B]]")

    #expect(results.count == 2)
    #expect(results[0].target == "A")
    #expect(results[1].target == "B")
  }

  // MARK: - Malformed brackets

  @Test
  func `Unclosed brackets do not crash`() {
    let results = WikilinkScanner.scan("[[unclosed and more text")
    #expect(results.isEmpty)
  }

  @Test
  func `Unclosed brackets followed by valid wikilink`() {
    let results = WikilinkScanner.scan("[[unclosed and [[Valid]]")

    #expect(results.count == 1)
    #expect(results[0].target == "Valid")
  }

  @Test
  func `Empty brackets are skipped`() {
    let results = WikilinkScanner.scan("[[]] and [[Valid]]")

    #expect(results.count == 1)
    #expect(results[0].target == "Valid")
  }

  // MARK: - Mixed embeds and standard links

  @Test
  func `Mixed embeds and standard links`() {
    let text = "See [[Page]] and ![[Image.png|300]] for details."
    let results = WikilinkScanner.scan(text)

    #expect(results.count == 2)
    #expect(results[0].target == "Page")
    #expect(results[0].isEmbed == false)
    #expect(results[1].target == "Image.png")
    #expect(results[1].isEmbed == true)
    #expect(results[1].displayText == "300")
  }

  // MARK: - Complex scenarios

  @Test
  func `Wikilinks with anchors and aliases`() {
    let text = "Read [[Page#Intro|Introduction]] and [[Other#^abc]]."
    let results = WikilinkScanner.scan(text)

    #expect(results.count == 2)
    #expect(results[0].target == "Page")
    #expect(results[0].anchor == .heading("Intro"))
    #expect(results[0].displayText == "Introduction")
    #expect(results[1].target == "Other")
    #expect(results[1].anchor == .blockID("abc"))
  }

  @Test
  func `Preserves order of appearance`() {
    let text = "[[C]] then [[A]] then [[B]]"
    let results = WikilinkScanner.scan(text)

    #expect(results.count == 3)
    #expect(results[0].target == "C")
    #expect(results[1].target == "A")
    #expect(results[2].target == "B")
  }

  @Test
  func `Multiline text with wikilinks`() {
    let text = """
    # Heading

    See [[Page A]] for more info.

    Also check [[Page B#Section|Details]].
    """
    let results = WikilinkScanner.scan(text)

    #expect(results.count == 2)
    #expect(results[0].target == "Page A")
    #expect(results[1].target == "Page B")
    #expect(results[1].anchor == .heading("Section"))
    #expect(results[1].displayText == "Details")
  }
}
