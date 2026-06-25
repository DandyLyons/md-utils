//
//  YAMLCommentDetectionTests.swift
//  MarkdownUtilitiesTests
//
//  Tests for YAML comment detection in frontmatter.
//
//  These tests cover FrontMatterParser.containsYAMLComments(_:) (the raw-string
//  check) and MarkdownDocument.containsYAMLComments (the document-level property).
//

import Testing
@testable import MarkdownUtilities

// MARK: - FrontMatterParser.containsYAMLComments(_:)

@Suite("FrontMatterParser.containsYAMLComments")
struct FrontMatterParserCommentDetectionTests {

  // MARK: True cases

  @Test
  func `Standalone comment line is detected`() {
    let yaml = """
    # This is a comment
    title: Test
    """
    #expect(FrontMatterParser.containsYAMLComments(yaml) == true)
  }

  @Test
  func `Indented comment line is detected`() {
    let yaml = """
    title: Test
      # indented comment
    author: Jane
    """
    #expect(FrontMatterParser.containsYAMLComments(yaml) == true)
  }

  @Test
  func `Tab-indented comment line is detected`() {
    let yaml = "title: Test\n\t# tab-indented comment\nauthor: Jane"
    #expect(FrontMatterParser.containsYAMLComments(yaml) == true)
  }

  @Test
  func `Comment at start of string is detected`() {
    let yaml = "# first line is a comment\ntitle: Test"
    #expect(FrontMatterParser.containsYAMLComments(yaml) == true)
  }

  @Test
  func `Comment as the only content is detected`() {
    let yaml = "# just a comment"
    #expect(FrontMatterParser.containsYAMLComments(yaml) == true)
  }

  // MARK: False cases

  @Test
  func `Comment-free YAML returns false`() {
    let yaml = """
    title: Test
    author: Jane
    count: 42
    """
    #expect(FrontMatterParser.containsYAMLComments(yaml) == false)
  }

  @Test
  func `Empty string returns false`() {
    #expect(FrontMatterParser.containsYAMLComments("") == false)
  }

  @Test
  func `Hash inside a string value is not a comment`() {
    // These contain '#' but not as a standalone comment line
    let yaml = """
    color: "#FF5733"
    url: https://example.com/page#anchor
    tags:
      - hash#tag
    """
    #expect(FrontMatterParser.containsYAMLComments(yaml) == false)
  }

  @Test
  func `Inline comment is not detected by naive check`() {
    // Intentional limitation: inline comments are out of scope
    let yaml = "title: Test # inline comment"
    #expect(FrontMatterParser.containsYAMLComments(yaml) == false)
  }
}

// MARK: - MarkdownDocument.containsYAMLComments

@Suite("MarkdownDocument.containsYAMLComments")
struct MarkdownDocumentCommentDetectionTests {

  @Test
  func `Document with comment in frontmatter sets flag to true`() throws {
    let content = """
    ---
    # section header comment
    title: Test
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)
    #expect(doc.containsYAMLComments == true)
  }

  @Test
  func `Document without comments sets flag to false`() throws {
    let content = """
    ---
    title: Test
    author: Jane
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)
    #expect(doc.containsYAMLComments == false)
  }

  @Test
  func `Document with no frontmatter sets flag to false`() throws {
    let doc = try MarkdownDocument(content: "Just body content")
    #expect(doc.containsYAMLComments == false)
  }

  @Test
  func `Document with empty frontmatter sets flag to false`() throws {
    let content = """
    ---
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)
    #expect(doc.containsYAMLComments == false)
  }

  @Test
  func `Programmatic init always sets flag to false`() {
    let doc = MarkdownDocument(frontMatter: .init(), body: "Body")
    #expect(doc.containsYAMLComments == false)
  }

  @Test
  func `Hash in string value does not set flag`() throws {
    let content = """
    ---
    color: "#FF5733"
    url: https://example.com/#anchor
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)
    #expect(doc.containsYAMLComments == false)
  }

  @Test
  func `Comment in body does not affect flag`() throws {
    // HTML comments in the body should not influence the frontmatter flag
    let content = """
    ---
    title: Test
    ---
    <!-- HTML comment in body -->
    Body content
    """
    let doc = try MarkdownDocument(content: content)
    #expect(doc.containsYAMLComments == false)
  }
}
