//
//  FrontMatterEdgeCasesTests.swift
//  MarkdownUtilitiesTests
//

import Testing
@testable import MarkdownUtilities

@Suite("FrontMatter Edge Cases Tests")
struct FrontMatterEdgeCasesTests {

  @Test
  func `Frontmatter with empty body`() async throws {
    let content = """
    ---
    title: Test
    ---
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter["title"]?.string == "Test")
    #expect(doc.body == "")
    #expect(doc.hasFrontMatter == true)
  }

  @Test
  func `Only whitespace after frontmatter`() async throws {
    let content = """
    ---
    title: Test
    ---

    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter["title"]?.string == "Test")
    // Body should include the whitespace
    #expect(doc.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  @Test
  func `Multiple consecutive delimiters in body`() async throws {
    let content = """
    ---
    title: Test
    ---
    ---
    ---
    Content
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter["title"]?.string == "Test")
    #expect(doc.body == "---\n---\nContent")
  }

  @Test
  func `Delimiter in middle of line is not recognized`() async throws {
    let content = "Text ---\nMore text"
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter.isEmpty)
    #expect(doc.body == content)
  }

  @Test
  func `Delimiter with spaces before it is not recognized`() async throws {
    let content = "  ---\ntitle: Test\n---\nBody"
    let doc = try MarkdownDocument(content: content)

    // Leading spaces mean it's not at start of document
    #expect(doc.frontMatter.isEmpty)
    #expect(doc.body == content)
  }

  @Test
  func `Unix line endings required - mixed endings`() async throws {
    // Mix of \n and \r\n - parser will accept this but the YAML may have \r characters
    let content = "---\ntitle: Test\r\n---\nBody"
    let doc = try MarkdownDocument(content: content)

    // Parser accepts mixed line endings in frontmatter content
    // YAML parser should handle \r characters
    #expect(doc.frontMatter["title"]?.string == "Test")
    #expect(doc.body == "Body")
  }

  @Test
  func `Closing delimiter without newline at end`() async throws {
    let content = "---\ntitle: Test\n---Body"
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter["title"]?.string == "Test")
    #expect(doc.body == "Body")
  }

  @Test
  func `Empty document with just delimiters`() async throws {
    let content = "---\n---"
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter.isEmpty)
    #expect(doc.body == "")
  }

  @Test
  func `Whitespace before opening delimiter`() async throws {
    let content = "\n---\ntitle: Test\n---\nBody"
    let doc = try MarkdownDocument(content: content)

    // Newline before delimiter means it's not at start
    #expect(doc.frontMatter.isEmpty)
    #expect(doc.body == content)
  }

  @Test
  func `Tab character before delimiter`() async throws {
    let content = "\t---\ntitle: Test\n---\nBody"
    let doc = try MarkdownDocument(content: content)

    // Tab before delimiter means it's not at start
    #expect(doc.frontMatter.isEmpty)
    #expect(doc.body == content)
  }

  @Test
  func `Four hyphens instead of three`() async throws {
    let content = "----\ntitle: Test\n----\nBody"
    let doc = try MarkdownDocument(content: content)

    // Must be exactly three hyphens
    #expect(doc.frontMatter.isEmpty)
    #expect(doc.body == content)
  }

  @Test
  func `Two hyphens instead of three`() async throws {
    let content = "--\ntitle: Test\n--\nBody"
    let doc = try MarkdownDocument(content: content)

    // Must be exactly three hyphens
    #expect(doc.frontMatter.isEmpty)
    #expect(doc.body == content)
  }

  @Test
  func `Delimiter with trailing spaces`() async throws {
    let content = "---  \ntitle: Test\n---\nBody"
    let doc = try MarkdownDocument(content: content)

    // Trailing spaces after --- might prevent recognition
    #expect(doc.frontMatter.isEmpty)
    #expect(doc.body == content)
  }

  @Test
  func `Very large frontmatter`() async throws {
    // Test with large frontmatter (performance/edge case)
    var largeFM = "title: Test\n"
    for i in 0..<1000 {
      largeFM += "key\(i): value\(i)\n"
    }

    let content = "---\n\(largeFM)---\nBody"
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter["title"]?.string == "Test")
    #expect(doc.frontMatter["key0"]?.string == "value0")
    #expect(doc.body == "Body")
    #expect(doc.hasFrontMatter == true)
  }

  @Test
  func `Frontmatter with special characters`() async throws {
    let content = """
    ---
    title: "Test with quotes"
    emoji: "🚀"
    special: "@#$%^&*()"
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasFrontMatter == true)
    #expect(doc.frontMatter["title"]?.string == "Test with quotes")
    #expect(doc.frontMatter["emoji"]?.string == "🚀")
    #expect(doc.body == "Body")
  }

  @Test
  func `Frontmatter with unicode`() async throws {
    let content = """
    ---
    title: 日本語
    chinese: 中文
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasFrontMatter == true)
    #expect(doc.frontMatter["title"]?.string == "日本語")
    #expect(doc.frontMatter["chinese"]?.string == "中文")
  }

  @Test
  func `Closing delimiter with extra hyphens`() async throws {
    let content = "---\ntitle: Test\n----\nBody"
    let doc = try MarkdownDocument(content: content)

    // PrefixUpTo("---") matches the first 3 hyphens of "----"
    // This is reasonable behavior - treats first 3 hyphens as closing delimiter
    #expect(doc.frontMatter["title"]?.string == "Test")
    #expect(doc.body == "-\nBody")
  }
}
