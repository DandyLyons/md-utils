import Testing
import Foundation
@testable import MarkdownUtilities

@Suite("FrontMatter Mutation Tests")
struct FrontMatterMutationTests {

  // MARK: - getValue Tests

  @Test
  func `getValue returns node for existing key`() async throws {
    let content = """
    ---
    title: Test Document
    author: Jane Doe
    count: 42
    ---
    Body content
    """
    let doc = try MarkdownDocument(content: content)
    let value = doc.getValue(forKey: "title")

    let stringValue = try #require(value?.string)
    #expect(stringValue == "Test Document")
  }

  @Test
  func `getValue returns nil for missing key`() async throws {
    let content = """
    ---
    title: Test
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)
    let value = doc.getValue(forKey: "nonexistent")

    #expect(value == nil)
  }

  @Test
  func `getValue returns nil for empty frontmatter`() async throws {
    let content = "Just body content"
    let doc = try MarkdownDocument(content: content)
    let value = doc.getValue(forKey: "title")

    #expect(value == nil)
  }

  @Test
  func `getValue retrieves numeric value`() async throws {
    let content = """
    ---
    count: 42
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)
    let value = doc.getValue(forKey: "count")

    let intValue = try #require(value?.int)
    #expect(intValue == 42)
  }

  // MARK: - setValue Tests

  @Test
  func `setValue creates new key in empty frontmatter`() async throws {
    var doc = try MarkdownDocument(content: "Just body")
    doc.setValue("Test", forKey: "title")

    #expect(doc.frontMatter["title"]?.string == "Test")
  }

  @Test
  func `setValue creates new key in existing frontmatter`() async throws {
    let content = """
    ---
    title: Original
    ---
    Body
    """
    var doc = try MarkdownDocument(content: content)
    doc.setValue("New Value", forKey: "author")

    #expect(doc.frontMatter["author"]?.string == "New Value")
    #expect(doc.frontMatter["title"]?.string == "Original")
  }

  @Test
  func `setValue updates existing key`() async throws {
    let content = """
    ---
    title: Original
    author: Jane
    ---
    Body
    """
    var doc = try MarkdownDocument(content: content)
    doc.setValue("Updated", forKey: "title")

    #expect(doc.frontMatter["title"]?.string == "Updated")
    #expect(doc.frontMatter["author"]?.string == "Jane")
  }

  @Test
  func `setValue preserves body content`() async throws {
    let content = """
    ---
    title: Test
    ---
    # Heading

    Body content here.

    """
    var doc = try MarkdownDocument(content: content)
    doc.setValue("Updated", forKey: "title")

    #expect(doc.body == "# Heading\n\nBody content here.\n")
  }

  // MARK: - hasKey Tests

  @Test
  func `hasKey returns true for existing key`() async throws {
    let content = """
    ---
    title: Test
    author: Jane
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasKey("title") == true)
    #expect(doc.hasKey("author") == true)
  }

  @Test
  func `hasKey returns false for missing key`() async throws {
    let content = """
    ---
    title: Test
    ---
    Body
    """
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasKey("nonexistent") == false)
  }

  @Test
  func `hasKey returns false for empty frontmatter`() async throws {
    let content = "Just body"
    let doc = try MarkdownDocument(content: content)

    #expect(doc.hasKey("title") == false)
  }

  // MARK: - removeValue Tests

  @Test
  func `removeValue deletes existing key`() async throws {
    let content = """
    ---
    title: Test
    author: Jane
    count: 42
    ---
    Body
    """
    var doc = try MarkdownDocument(content: content)
    doc.removeValue(forKey: "author")

    #expect(doc.frontMatter["title"]?.string == "Test")
    #expect(doc.frontMatter["author"] == nil)
    #expect(doc.frontMatter["count"]?.int == 42)
  }

  @Test
  func `removeValue is idempotent for missing key`() async throws {
    let content = """
    ---
    title: Test
    ---
    Body
    """
    var doc = try MarkdownDocument(content: content)
    doc.removeValue(forKey: "nonexistent")

    #expect(doc.frontMatter["title"]?.string == "Test")
    #expect(doc.frontMatter.count == 1)
  }

  @Test
  func `removeValue handles empty frontmatter`() async throws {
    var doc = try MarkdownDocument(content: "Just body")
    doc.removeValue(forKey: "title")

    #expect(doc.frontMatter.isEmpty)
  }

  @Test
  func `removeValue can remove last key`() async throws {
    let content = """
    ---
    title: Test
    ---
    Body
    """
    var doc = try MarkdownDocument(content: content)
    doc.removeValue(forKey: "title")

    #expect(doc.frontMatter.isEmpty)
  }

  @Test
  func `removeValue preserves body content`() async throws {
    let content = """
    ---
    title: Test
    author: Jane
    ---
    # Important Content

    This should remain.

    """
    var doc = try MarkdownDocument(content: content)
    doc.removeValue(forKey: "author")

    #expect(doc.body == "# Important Content\n\nThis should remain.\n")
  }

  // MARK: - Integration Tests

  @Test
  func `Chained mutations work correctly`() async throws {
    var doc = try MarkdownDocument(content: "Body only")

    // Add multiple keys
    doc.setValue("Test Title", forKey: "title")
    doc.setValue("Jane Doe", forKey: "author")
    doc.setValue("draft", forKey: "status")

    #expect(doc.hasKey("title") == true)
    #expect(doc.hasKey("author") == true)
    #expect(doc.hasKey("status") == true)

    // Update one
    doc.setValue("published", forKey: "status")
    #expect(doc.getValue(forKey: "status")?.string == "published")

    // Remove one
    doc.removeValue(forKey: "author")
    #expect(doc.hasKey("author") == false)
    #expect(doc.hasKey("title") == true)
  }

  @Test
  func `Mutations roundtrip through render`() async throws {
    var doc = try MarkdownDocument(content: "Original body")

    doc.setValue("Test", forKey: "title")
    doc.setValue("Jane", forKey: "author")

    let rendered = try doc.render()
    let reparsed = try MarkdownDocument(content: rendered)

    #expect(reparsed.getValue(forKey: "title")?.string == "Test")
    #expect(reparsed.getValue(forKey: "author")?.string == "Jane")
    #expect(reparsed.body == "Original body")
  }
}
