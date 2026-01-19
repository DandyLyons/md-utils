//
//  PlainTextConverterTests.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownUtilities
import MarkdownSyntax
import Testing

@Suite("PlainTextConverter Tests")
struct PlainTextConverterTests {

  @Test
  func `Convert simple markdown to plain text`() async throws {
    let markdown = "# Hello\n\nThis is **bold** text."
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText()

    #expect(plainText.contains("Hello"))
    #expect(plainText.contains("This is bold text."))
    #expect(!plainText.contains("**"))
    #expect(!plainText.contains("#"))
  }

  @Test
  func `Exclude frontmatter by default`() async throws {
    let markdown = """
      ---
      title: Test Document
      author: John Doe
      ---

      # Content

      Body text here.
      """
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText()

    #expect(!plainText.contains("title"))
    #expect(!plainText.contains("author"))
    #expect(plainText.contains("Content"))
    #expect(plainText.contains("Body text here."))
  }

  @Test
  func `Include frontmatter when option is true`() async throws {
    let markdown = """
      ---
      title: Test Document
      author: John Doe
      ---

      # Content

      Body text.
      """
    let doc = try MarkdownDocument(content: markdown)
    let options = PlainTextOptions(includeFrontmatter: true)
    let plainText = try await doc.toPlainText(options: options)

    #expect(plainText.contains("title"))
    #expect(plainText.contains("author"))
    #expect(plainText.contains("---"))
    #expect(plainText.contains("Content"))
  }

  @Test
  func `Use default double spacing between blocks`() async throws {
    let markdown = """
      # Heading

      Paragraph one.

      Paragraph two.
      """
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText()

    // Should have double newlines between blocks
    #expect(plainText.contains("\n\n"))
  }

  @Test
  func `Use single spacing when blockSeparator is 1`() async throws {
    let markdown = """
      # Heading

      Paragraph one.

      Paragraph two.
      """
    let doc = try MarkdownDocument(content: markdown)
    let options = PlainTextOptions(blockSeparator: 1)
    let plainText = try await doc.toPlainText(options: options)

    // Should not have double newlines between all blocks
    let doubleNewlineCount = plainText.components(separatedBy: "\n\n").count - 1
    let singleNewlineCount = plainText.components(separatedBy: "\n").count - 1

    // More single newlines than double
    #expect(singleNewlineCount > doubleNewlineCount)
  }

  @Test
  func `Use compact preset for minimal output`() async throws {
    let markdown = """
      # Heading

      ```swift
      code here
      ```

      - List item
        - Nested item
      """
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText(options: .compact)

    // Compact mode: single spacing, no code blocks, no list indentation
    #expect(!plainText.contains("code here"))
    #expect(plainText.contains("Heading"))
    #expect(plainText.contains("List item"))
  }

  @Test
  func `Extract links as text only`() async throws {
    let markdown = "Visit [my website](https://example.com) for more info."
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText()

    #expect(plainText.contains("Visit my website for more info."))
    #expect(!plainText.contains("https://"))
    #expect(!plainText.contains("["))
    #expect(!plainText.contains("]"))
  }

  @Test
  func `Extract image alt text by default`() async throws {
    let markdown = "Check out this ![sunset photo](sunset.jpg) from vacation."
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText()

    #expect(plainText.contains("sunset photo"))
    #expect(!plainText.contains("sunset.jpg"))
    #expect(!plainText.contains("!["))
  }

  @Test
  func `Preserve code blocks by default`() async throws {
    let markdown = """
      Example:

      ```python
      def hello():
          print("Hello")
      ```
      """
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText()

    #expect(plainText.contains("def hello()"))
    #expect(plainText.contains("print(\"Hello\")"))
  }

  @Test
  func `Exclude code blocks when preserveCodeBlocks is false`() async throws {
    let markdown = """
      Example:

      ```python
      def hello():
          print("Hello")
      ```

      End of example.
      """
    let doc = try MarkdownDocument(content: markdown)
    let options = PlainTextOptions(preserveCodeBlocks: false)
    let plainText = try await doc.toPlainText(options: options)

    #expect(!plainText.contains("def hello()"))
    #expect(plainText.contains("Example:"))
    #expect(plainText.contains("End of example."))
  }

  @Test
  func `Indent nested lists by default`() async throws {
    let markdown = """
      - Top level
        - Nested level
          - Deep nested
      """
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText()

    #expect(plainText.contains("Top level"))
    #expect(plainText.contains("Nested level"))
    #expect(plainText.contains("Deep nested"))

    // Nested items should have some indentation
    #expect(plainText.contains("  ") || plainText.contains("    "))
  }

  @Test
  func `No list indentation when indentLists is false`() async throws {
    let markdown = """
      - Top level
        - Nested level
      """
    let doc = try MarkdownDocument(content: markdown)
    let options = PlainTextOptions(indentLists: false)
    let plainText = try await doc.toPlainText(options: options)

    let lines = plainText.split(separator: "\n")
    for line in lines where line.contains("level") {
      // Lines should not start with spaces
      #expect(!line.hasPrefix(" "))
    }
  }

  @Test
  func `Handle complex markdown document`() async throws {
    let markdown = """
      # Main Title

      Introduction paragraph with **bold** and *italic* text.

      ## Subsection

      - First item
      - Second item with `inline code`
      - Third item

      > A blockquote with important information

      ```swift
      let code = "example"
      ```

      Final paragraph with a [link](https://example.com).
      """
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText()

    // Verify content is present
    #expect(plainText.contains("Main Title"))
    #expect(plainText.contains("Introduction paragraph with bold and italic text."))
    #expect(plainText.contains("Subsection"))
    #expect(plainText.contains("First item"))
    #expect(plainText.contains("inline code"))
    #expect(plainText.contains("blockquote with important information"))
    #expect(plainText.contains("let code = \"example\""))
    #expect(plainText.contains("Final paragraph with a link."))

    // Verify formatting is stripped
    #expect(!plainText.contains("**"))
    #expect(!plainText.contains("*"))
    #expect(!plainText.contains("#"))
    #expect(!plainText.contains(">"))
    #expect(!plainText.contains("```"))
  }

  @Test
  func `Handle empty document`() async throws {
    let markdown = ""
    let doc = try MarkdownDocument(content: markdown)
    let plainText = try await doc.toPlainText()

    #expect(plainText.isEmpty)
  }

  @Test
  func `Handle document with only frontmatter`() async throws {
    let markdown = """
      ---
      title: Only Frontmatter
      ---
      """
    let doc = try MarkdownDocument(content: markdown)

    // Without frontmatter
    let plainText = try await doc.toPlainText()
    #expect(plainText.isEmpty || plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

    // With frontmatter
    let options = PlainTextOptions(includeFrontmatter: true)
    let plainTextWithFM = try await doc.toPlainText(options: options)
    #expect(plainTextWithFM.contains("title"))
  }
}
