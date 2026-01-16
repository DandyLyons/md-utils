//
//  FrontMatterParsingTests.swift
//  MarkdownUtilitiesTests
//
//  Tests for YAML parsing of frontmatter
//

import Testing
@testable import MarkdownUtilities
import Yams

@Suite("FrontMatter YAML Parsing Tests")
struct FrontMatterParsingTests {

  @Test
  func `YAML parsing works for valid frontmatter`() async throws {
    let content = """
    ---
    title: Test Document
    count: 42
    tags:
      - swift
      - parsing
    ---
    Body content
    """
    let doc = try MarkdownDocument(content: content)

    // Verify parsed values
    #expect(doc.frontMatter["title"]?.string == "Test Document")
    #expect(doc.frontMatter["count"]?.int == 42)
    #expect(doc.frontMatter["tags"]?.sequence?.count == 2)
  }

  @Test
  func `Empty frontmatter returns empty mapping`() async throws {
    let content = """
    ---
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter.isEmpty)
    #expect(doc.hasFrontMatter == false)
  }

  @Test
  func `Whitespace-only frontmatter returns empty mapping`() async throws {
    let content = """
    ---

    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter.isEmpty)
    #expect(doc.hasFrontMatter == false)
  }

  @Test
  func `No frontmatter returns empty mapping`() async throws {
    let content = "Just body content"
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter.isEmpty)
    #expect(doc.hasFrontMatter == false)
  }

  @Test
  func `Frontmatter is array throws error during initialization`() async throws {
    let content = """
    ---
    - item1
    - item2
    ---
    Body
    """

    #expect(throws: YAMLConversionError.notAMapping) {
      _ = try MarkdownDocument(content: content)
    }
  }

  @Test
  func `Invalid YAML syntax throws during initialization`() async throws {
    let content = """
    ---
    invalid: yaml: syntax:
    ---
    Body
    """

    #expect(throws: YAMLConversionError.self) {
      _ = try MarkdownDocument(content: content)
    }
  }

  @Test
  func `Frontmatter is scalar string throws error during initialization`() async throws {
    let content = """
    ---
    "just a string"
    ---
    Body
    """

    #expect(throws: YAMLConversionError.notAMapping) {
      _ = try MarkdownDocument(content: content)
    }
  }

  @Test
  func `Frontmatter is boolean throws error during initialization`() async throws {
    let content = """
    ---
    true
    ---
    Body
    """

    #expect(throws: YAMLConversionError.notAMapping) {
      _ = try MarkdownDocument(content: content)
    }
  }

  @Test
  func `Complex nested YAML parses correctly`() async throws {
    let content = """
    ---
    nested:
      deep:
        value: 42
    list: [1, 2, 3]
    metadata:
      author: Jane
      tags:
        - swift
        - yaml
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.frontMatter["nested"] != nil)
    #expect(doc.frontMatter["list"]?.sequence?.count == 3)
    #expect(doc.frontMatter["metadata"]?.mapping?["author"]?.string == "Jane")
  }

  @Test
  func `hasFrontMatter returns true for valid frontmatter`() async throws {
    let content = """
    ---
    title: Test
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasFrontMatter == true)
  }

  @Test
  func `hasFrontMatter returns false for no frontmatter`() async throws {
    let content = "Just body"
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasFrontMatter == false)
  }

  @Test
  func `Render reconstructs document with frontmatter`() async throws {
    let original = """
    ---
    title: Test
    author: Jane
    ---
    Body content
    """
    let doc = try MarkdownDocument(content: original)
    let rendered = try doc.render()

    // Should match original (modulo potential whitespace normalization)
    #expect(rendered.contains("---"))
    #expect(rendered.contains("title:"))
    #expect(rendered.contains("author:"))
    #expect(rendered.contains("Body content"))
  }

  @Test
  func `Render returns just body when no frontmatter`() async throws {
    let content = "Just body content"
    let doc = try MarkdownDocument(content: content)
    let rendered = try doc.render()

    #expect(rendered == "Just body content")
    #expect(!rendered.contains("---"))
  }

  @Test
  func `Render returns just body when frontmatter is whitespace-only`() async throws {
    let content = """
    ---

    ---
    Body content
    """
    let doc = try MarkdownDocument(content: content)
    let rendered = try doc.render()

    #expect(rendered == "Body content")
    #expect(!rendered.contains("---"))
  }
}
