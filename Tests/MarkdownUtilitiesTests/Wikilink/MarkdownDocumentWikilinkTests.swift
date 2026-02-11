//
//  MarkdownDocumentWikilinkTests.swift
//  MarkdownUtilitiesTests
//

import Testing
@testable import MarkdownUtilities

@Suite("MarkdownDocument Wikilink Integration Tests")
struct MarkdownDocumentWikilinkTests {

  @Test
  func `Wikilinks in body are found`() throws {
    let content = """
    # My Document

    See [[Page A]] and [[Page B]].
    """
    let doc = try MarkdownDocument(content: content)
    let links = doc.wikilinks()

    #expect(links.count == 2)
    #expect(links[0].target == "Page A")
    #expect(links[1].target == "Page B")
  }

  @Test
  func `Frontmatter wikilinks are scanned`() throws {
    let content = """
    ---
    related: "[[FrontMatter Link]]"
    ---
    Body with [[Body Link]].
    """
    let doc = try MarkdownDocument(content: content)
    let links = doc.wikilinks()

    #expect(links.count == 2)
    #expect(links[0].target == "FrontMatter Link")
    #expect(links[1].target == "Body Link")
  }

  @Test
  func `bodyWikilinks excludes frontmatter`() throws {
    let content = """
    ---
    related: "[[FrontMatter Only]]"
    ---
    Body with [[Body Link]].
    """
    let doc = try MarkdownDocument(content: content)
    let links = doc.bodyWikilinks()

    #expect(links.count == 1)
    #expect(links[0].target == "Body Link")
  }

  @Test
  func `frontMatterWikilinks excludes body`() throws {
    let content = """
    ---
    related: "[[FrontMatter Only]]"
    ---
    Body with [[Body Link]].
    """
    let doc = try MarkdownDocument(content: content)
    let links = doc.frontMatterWikilinks()

    #expect(links.count == 1)
    #expect(links[0].target == "FrontMatter Only")
  }

  @Test
  func `hasWikilinks returns true when links exist`() throws {
    let content = "Some text with [[Link]]."
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasWikilinks == true)
  }

  @Test
  func `hasWikilinks returns true when links only in frontmatter`() throws {
    let content = """
    ---
    related: "[[Only In Frontmatter]]"
    ---
    Body without links.
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasWikilinks == true)
  }

  @Test
  func `hasWikilinks returns false for plain text`() throws {
    let content = "Plain text with no links."
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasWikilinks == false)
  }

  @Test
  func `Frontmatter wikilinks appear before body wikilinks`() throws {
    let content = """
    ---
    related: "[[FM Link]]"
    ---
    Body with [[Body Link]].
    """
    let doc = try MarkdownDocument(content: content)
    let links = doc.wikilinks()

    #expect(links.count == 2)
    #expect(links[0].target == "FM Link")
    #expect(links[1].target == "Body Link")
  }

  @Test
  func `Multiple wikilinks preserve order`() throws {
    let content = """
    First [[C]], then [[A]], finally [[B]].
    """
    let doc = try MarkdownDocument(content: content)
    let links = doc.wikilinks()

    #expect(links.count == 3)
    #expect(links[0].target == "C")
    #expect(links[1].target == "A")
    #expect(links[2].target == "B")
  }

  @Test
  func `Embed wikilinks are found in body`() throws {
    let content = """
    # Notes

    ![[Image.png|300]]
    """
    let doc = try MarkdownDocument(content: content)
    let links = doc.wikilinks()

    #expect(links.count == 1)
    #expect(links[0].target == "Image.png")
    #expect(links[0].isEmbed == true)
    #expect(links[0].displayText == "300")
  }

  @Test
  func `Wikilinks in frontmatter arrays are found`() throws {
    let content = """
    ---
    links:
      - "[[Page A]]"
      - "[[Page B]]"
    ---
    Body text.
    """
    let doc = try MarkdownDocument(content: content)
    let links = doc.frontMatterWikilinks()

    #expect(links.count == 2)
    #expect(links[0].target == "Page A")
    #expect(links[1].target == "Page B")
  }

  @Test
  func `Wikilinks in nested frontmatter mappings are found`() throws {
    let content = """
    ---
    metadata:
      see_also: "[[Nested Link]]"
    ---
    Body text.
    """
    let doc = try MarkdownDocument(content: content)
    let links = doc.frontMatterWikilinks()

    #expect(links.count == 1)
    #expect(links[0].target == "Nested Link")
  }
}
