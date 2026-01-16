//
//  FrontMatterParsingTests.swift
//  MarkdownUtilitiesTests
//
//  Tests for lazy YAML parsing of frontmatter
//

import Testing
@testable import MarkdownUtilities
import Yams

@Suite("FrontMatter YAML Parsing Tests")
struct FrontMatterParsingTests {

  @Test
  func `Lazy YAML parsing works for valid frontmatter`() async throws {
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
    let doc = try MarkdownDocument(parsing: content)

    // Triggers lazy parsing
    let fm = try doc.frontMatter

    // Verify parsed values
    #expect(fm["title"]?.string == "Test Document")
    #expect(fm["count"]?.int == 42)
    #expect(fm["tags"]?.sequence?.count == 2)
  }

  @Test
  func `Empty frontmatter returns empty mapping`() async throws {
    let content = """
    ---
    ---
    Body
    """
    let doc = try MarkdownDocument(parsing: content)

    let fm = try doc.frontMatter
    #expect(fm.isEmpty)
    #expect(doc.hasFrontMatter == false)
  }

  @Test
  func `Whitespace-only frontmatter returns empty mapping`() async throws {
    let content = """
    ---

    ---
    Body
    """
    let doc = try MarkdownDocument(parsing: content)

    let fm = try doc.frontMatter
    #expect(fm.isEmpty)
    #expect(doc.hasFrontMatter == false)
  }

  @Test
  func `No frontmatter returns empty mapping`() async throws {
    let content = "Just body content"
    let doc = try MarkdownDocument(parsing: content)

    let fm = try doc.frontMatter
    #expect(fm.isEmpty)
    #expect(doc.hasFrontMatter == false)
  }

  @Test
  func `Invalid YAML throws on access but separation succeeds`() async throws {
    let content = """
    ---
    []
    ---
    Body
    """
    let doc = try MarkdownDocument(parsing: content)

    // Separation works - rawFrontMatter is extracted
    #expect(doc.rawFrontMatter == "[]\n")
    #expect(doc.body == "Body")

    // But lazy parsing fails because root is an array, not a mapping
    #expect(throws: YAMLConversionError.self) {
      _ = try doc.frontMatter
    }
  }

  @Test
  func `Invalid YAML syntax throws on access`() async throws {
    let content = """
    ---
    invalid: yaml: syntax:
    ---
    Body
    """
    let doc = try MarkdownDocument(parsing: content)

    // Separation works
    #expect(doc.rawFrontMatter == "invalid: yaml: syntax:\n")

    // But parsing fails
    #expect(throws: YAMLConversionError.self) {
      _ = try doc.frontMatter
    }
  }

  @Test
  func `Frontmatter is array throws error`() async throws {
    let content = """
    ---
    - item1
    - item2
    ---
    Body
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(throws: YAMLConversionError.notAMapping) {
      _ = try doc.frontMatter
    }
  }

  @Test
  func `Frontmatter is scalar string throws error`() async throws {
    let content = """
    ---
    "just a string"
    ---
    Body
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(throws: YAMLConversionError.notAMapping) {
      _ = try doc.frontMatter
    }
  }

  @Test
  func `Frontmatter is boolean throws error`() async throws {
    let content = """
    ---
    true
    ---
    Body
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(throws: YAMLConversionError.notAMapping) {
      _ = try doc.frontMatter
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
    let doc = try MarkdownDocument(parsing: content)

    let fm = try doc.frontMatter
    #expect(fm["nested"] != nil)
    #expect(fm["list"]?.sequence?.count == 3)
    #expect(fm["metadata"]?.mapping?["author"]?.string == "Jane")
  }

  @Test
  func `hasFrontMatter returns true for valid frontmatter`() async throws {
    let content = """
    ---
    title: Test
    ---
    Body
    """
    let doc = try MarkdownDocument(parsing: content)

    #expect(doc.hasFrontMatter == true)
  }

  @Test
  func `hasFrontMatter returns false for no frontmatter`() async throws {
    let content = "Just body"
    let doc = try MarkdownDocument(parsing: content)

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
    let doc = try MarkdownDocument(parsing: original)
    let rendered = doc.render()

    // Should match original (modulo potential whitespace normalization)
    #expect(rendered.contains("---"))
    #expect(rendered.contains("title: Test"))
    #expect(rendered.contains("Body content"))
  }

  @Test
  func `Render returns just body when no frontmatter`() async throws {
    let content = "Just body content"
    let doc = try MarkdownDocument(parsing: content)
    let rendered = doc.render()

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
    let doc = try MarkdownDocument(parsing: content)
    let rendered = doc.render()

    #expect(rendered == "Body content")
    #expect(!rendered.contains("---"))
  }
}
