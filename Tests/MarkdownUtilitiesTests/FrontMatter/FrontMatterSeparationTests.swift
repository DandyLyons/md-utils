//
//  FrontMatterSeparationTests.swift
//  MarkdownUtilitiesTests
//
//  Tests for frontmatter separation functionality
//

import Testing
@testable import MarkdownUtilities

@Suite("FrontMatter Separation Tests")
struct FrontMatterSeparationTests {

  @Test
  func `Parse document with frontmatter and body`() async throws {
    let content = """
    ---
    title: Test
    author: Jane
    ---
    Body content here
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(doc.rawFrontMatter == "title: Test\nauthor: Jane\n")
    #expect(doc.body == "Body content here")
  }

  @Test
  func `Parse document without frontmatter`() async throws {
    let content = "Just body content"
    let doc = try MarkdownDocument(parsing: content)

    #expect(doc.rawFrontMatter == "")
    #expect(doc.body == "Just body content")
  }

  @Test
  func `Parse document with empty frontmatter`() async throws {
    let content = """
    ---
    ---
    Body content
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(doc.rawFrontMatter == "")
    #expect(doc.body == "Body content")
  }

  @Test
  func `Body contains delimiter is handled correctly`() async throws {
    let content = """
    ---
    title: Test
    ---
    Some text
    ---
    More text
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(doc.rawFrontMatter == "title: Test\n")
    #expect(doc.body == "Some text\n---\nMore text")
  }

  @Test
  func `Single delimiter only treats entire content as body`() async throws {
    let content = """
    ---
    This should be treated as body text
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(doc.rawFrontMatter == "")
    #expect(doc.body == "---\nThis should be treated as body text")
  }

  @Test
  func `Delimiter not on first line treats entire content as body`() async throws {
    let content = """
    Some text
    ---
    title: Test
    ---
    More text
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(doc.rawFrontMatter == "")
    #expect(doc.body == "Some text\n---\ntitle: Test\n---\nMore text")
  }

  @Test
  func `Empty document works`() async throws {
    let content = ""
    let doc = try MarkdownDocument(parsing: content)

    #expect(doc.rawFrontMatter == "")
    #expect(doc.body == "")
  }

  @Test
  func `Frontmatter without body works`() async throws {
    let content = """
    ---
    title: Test
    author: John
    ---
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(doc.rawFrontMatter == "title: Test\nauthor: John\n")
    #expect(doc.body == "")
  }

  @Test
  func `Windows line endings are not supported`() async throws {
    // Windows line endings (\r\n) should not be recognized as frontmatter delimiters
    let content = "---\r\ntitle: Test\r\n---\r\nBody"
    let doc = try MarkdownDocument(parsing: content)

    // Should treat entire content as body since --- doesn't have Unix newline
    #expect(doc.rawFrontMatter == "")
    #expect(doc.body == "---\r\ntitle: Test\r\n---\r\nBody")
  }

  @Test
  func `Backward compatibility with init(content:)`() async throws {
    // Old initializer should still work
    let content = """
    ---
    title: Test
    ---
    Body
    """
    let doc = MarkdownDocument(content: content)

    // Should not parse frontmatter, treat entire content as body
    #expect(doc.content == content)
    #expect(doc.rawFrontMatter == "")
    #expect(doc.body == content)
  }
}
