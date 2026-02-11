//
//  WikilinkParserTests.swift
//  MarkdownUtilitiesTests
//

import Testing
@testable import MarkdownUtilities

@Suite("WikilinkParser Tests")
struct WikilinkParserTests {

  let parser = WikilinkParser()

  // MARK: - Standard wikilinks

  @Test
  func `Standard wikilink`() throws {
    var input: Substring = "[[Target]]"
    let result = try parser.parse(&input)

    #expect(result.target == "Target")
    #expect(result.displayText == nil)
    #expect(result.anchor == nil)
    #expect(result.isEmbed == false)
    #expect(result.rawValue == "[[Target]]")
    #expect(input.isEmpty)
  }

  @Test
  func `Wikilink with spaces in target`() throws {
    var input: Substring = "[[My Page Name]]"
    let result = try parser.parse(&input)

    #expect(result.target == "My Page Name")
    #expect(result.displayText == nil)
    #expect(result.rawValue == "[[My Page Name]]")
  }

  // MARK: - Aliased wikilinks

  @Test
  func `Aliased wikilink`() throws {
    var input: Substring = "[[Target|Display Text]]"
    let result = try parser.parse(&input)

    #expect(result.target == "Target")
    #expect(result.displayText == "Display Text")
    #expect(result.anchor == nil)
    #expect(result.isEmbed == false)
    #expect(result.rawValue == "[[Target|Display Text]]")
  }

  // MARK: - Embeds

  @Test
  func `Embed wikilink`() throws {
    var input: Substring = "![[Target]]"
    let result = try parser.parse(&input)

    #expect(result.target == "Target")
    #expect(result.isEmbed == true)
    #expect(result.rawValue == "![[Target]]")
  }

  @Test
  func `Embed with alias`() throws {
    var input: Substring = "![[Image.png|400]]"
    let result = try parser.parse(&input)

    #expect(result.target == "Image.png")
    #expect(result.displayText == "400")
    #expect(result.isEmbed == true)
    #expect(result.rawValue == "![[Image.png|400]]")
  }

  // MARK: - Heading anchors

  @Test
  func `Heading anchor`() throws {
    var input: Substring = "[[Page#Introduction]]"
    let result = try parser.parse(&input)

    #expect(result.target == "Page")
    #expect(result.anchor == .heading("Introduction"))
    #expect(result.displayText == nil)
    #expect(result.rawValue == "[[Page#Introduction]]")
  }

  @Test
  func `Self-referencing heading anchor`() throws {
    var input: Substring = "[[#Introduction]]"
    let result = try parser.parse(&input)

    #expect(result.target == "")
    #expect(result.anchor == .heading("Introduction"))
    #expect(result.rawValue == "[[#Introduction]]")
  }

  // MARK: - Block anchors

  @Test
  func `Block ID anchor`() throws {
    var input: Substring = "[[Page#^abc123]]"
    let result = try parser.parse(&input)

    #expect(result.target == "Page")
    #expect(result.anchor == .blockID("abc123"))
    #expect(result.rawValue == "[[Page#^abc123]]")
  }

  @Test
  func `Self-referencing block anchor`() throws {
    var input: Substring = "[[#^abc]]"
    let result = try parser.parse(&input)

    #expect(result.target == "")
    #expect(result.anchor == .blockID("abc"))
    #expect(result.rawValue == "[[#^abc]]")
  }

  // MARK: - Anchor + alias combinations

  @Test
  func `Heading anchor with alias`() throws {
    var input: Substring = "[[Page#Intro|See Intro]]"
    let result = try parser.parse(&input)

    #expect(result.target == "Page")
    #expect(result.anchor == .heading("Intro"))
    #expect(result.displayText == "See Intro")
    #expect(result.rawValue == "[[Page#Intro|See Intro]]")
  }

  @Test
  func `Block anchor with alias`() throws {
    var input: Substring = "[[Page#^abc|See Block]]"
    let result = try parser.parse(&input)

    #expect(result.target == "Page")
    #expect(result.anchor == .blockID("abc"))
    #expect(result.displayText == "See Block")
    #expect(result.rawValue == "[[Page#^abc|See Block]]")
  }

  // MARK: - Escaped pipes

  @Test
  func `Escaped pipe in target`() throws {
    var input: Substring = "[[File \\| Name]]"
    let result = try parser.parse(&input)

    #expect(result.target == "File | Name")
    #expect(result.displayText == nil)
    #expect(result.rawValue == "[[File \\| Name]]")
  }

  @Test
  func `Escaped pipe in target with display text`() throws {
    var input: Substring = "[[File \\| Name|Display]]"
    let result = try parser.parse(&input)

    #expect(result.target == "File | Name")
    #expect(result.displayText == "Display")
    #expect(result.rawValue == "[[File \\| Name|Display]]")
  }

  @Test
  func `Multiple escaped pipes`() throws {
    var input: Substring = "[[A \\| B \\| C]]"
    let result = try parser.parse(&input)

    #expect(result.target == "A | B | C")
    #expect(result.displayText == nil)
    #expect(result.rawValue == "[[A \\| B \\| C]]")
  }

  // MARK: - rawValue preservation

  @Test
  func `rawValue preserved for embed with anchor and alias`() throws {
    var input: Substring = "![[Page#Heading|Alias]]"
    let result = try parser.parse(&input)

    #expect(result.rawValue == "![[Page#Heading|Alias]]")
    #expect(result.target == "Page")
    #expect(result.anchor == .heading("Heading"))
    #expect(result.displayText == "Alias")
    #expect(result.isEmbed == true)
  }

  // MARK: - Remaining input

  @Test
  func `Parser leaves remaining input unconsumed`() throws {
    var input: Substring = "[[Target]] and more text"
    let result = try parser.parse(&input)

    #expect(result.target == "Target")
    #expect(input == " and more text")
  }

  // MARK: - Error cases

  @Test
  func `Missing closing brackets throws`() {
    var input: Substring = "[[unclosed"
    #expect(throws: (any Error).self) {
      _ = try parser.parse(&input)
    }
  }

  @Test
  func `Non-wikilink input throws`() {
    var input: Substring = "just text"
    #expect(throws: (any Error).self) {
      _ = try parser.parse(&input)
    }
  }

  @Test
  func `Empty brackets throws`() {
    var input: Substring = "[[]]"
    #expect(throws: (any Error).self) {
      _ = try parser.parse(&input)
    }
  }

  @Test
  func `Single bracket throws`() {
    var input: Substring = "[Target]]"
    #expect(throws: (any Error).self) {
      _ = try parser.parse(&input)
    }
  }
}
