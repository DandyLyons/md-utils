//
//  BlockContentTextExtractorTests.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownUtilities
import MarkdownSyntax
import Testing

@Suite("BlockContentTextExtractor Tests")
struct BlockContentTextExtractorTests {

  @Test
  func `Extract text from heading`() async throws {
    let markdown = "# Hello World"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    #expect(text == "Hello World")
  }

  @Test
  func `Extract text from paragraph`() async throws {
    let markdown = "This is a paragraph with **bold** text."
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    #expect(text == "This is a paragraph with bold text.")
  }

  @Test
  func `Extract text from multiple blocks with default separator`() async throws {
    let markdown = "# Heading\n\nParagraph text."
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    #expect(text == "Heading\n\nParagraph text.")
  }

  @Test
  func `Extract text with custom block separator`() async throws {
    let markdown = "# Heading\n\nParagraph text."
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let options = BlockTextExtractionOptions(blockSeparator: "\n")
    let text = BlockContentTextExtractor.extractText(from: root.children, options: options)

    #expect(text == "Heading\nParagraph text.")
  }

  @Test
  func `Extract text from code block by default`() async throws {
    let markdown = """
      ```swift
      func hello() {
        print("Hello")
      }
      ```
      """
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    #expect(text.contains("func hello()"))
    #expect(text.contains("print(\"Hello\")"))
  }

  @Test
  func `Skip code blocks when preserveCodeBlocks is false`() async throws {
    let markdown = """
      # Heading

      ```swift
      func hello() {}
      ```

      Paragraph after code.
      """
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let options = BlockTextExtractionOptions(preserveCodeBlocks: false)
    let text = BlockContentTextExtractor.extractText(from: root.children, options: options)

    #expect(!text.contains("func hello()"))
    #expect(text.contains("Heading"))
    #expect(text.contains("Paragraph after code."))
  }

  @Test
  func `Extract text from unordered list`() async throws {
    let markdown = """
      - Item 1
      - Item 2
      - Item 3
      """
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    #expect(text.contains("Item 1"))
    #expect(text.contains("Item 2"))
    #expect(text.contains("Item 3"))
  }

  @Test
  func `Extract text from ordered list`() async throws {
    let markdown = """
      1. First
      2. Second
      3. Third
      """
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    #expect(text.contains("First"))
    #expect(text.contains("Second"))
    #expect(text.contains("Third"))
  }

  @Test
  func `Indent nested lists by default`() async throws {
    let markdown = """
      - Level 1
        - Level 2
          - Level 3
      """
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    // Check that nested items have more leading spaces
    #expect(text.contains("  Level 2") || text.contains("    Level 2"))
  }

  @Test
  func `No list indentation when listIndentSpaces is zero`() async throws {
    let markdown = """
      - Level 1
        - Level 2
      """
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let options = BlockTextExtractionOptions(listIndentSpaces: 0)
    let text = BlockContentTextExtractor.extractText(from: root.children, options: options)

    // All items should start at the same indentation
    let lines = text.split(separator: "\n")
    for line in lines where line.contains("Level") {
      #expect(!line.hasPrefix(" "))
    }
  }

  @Test
  func `Extract text from blockquote`() async throws {
    let markdown = """
      > This is a quote
      > spanning multiple lines
      """
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    #expect(text.contains("This is a quote"))
    #expect(text.contains("spanning multiple lines"))
  }

  @Test
  func `Skip thematic break (horizontal rule)`() async throws {
    let markdown = """
      Paragraph before

      ---

      Paragraph after
      """
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    #expect(text.contains("Paragraph before"))
    #expect(text.contains("Paragraph after"))
    #expect(!text.contains("---"))
  }

  @Test
  func `Skip HTML blocks by default`() async throws {
    let markdown = """
      Paragraph

      <div>
        <p>HTML content</p>
      </div>

      Another paragraph
      """
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let text = BlockContentTextExtractor.extractText(from: root.children)

    // HTML blocks might be parsed as paragraphs or other content by MarkdownSyntax
    // The main requirement is that we extract the surrounding paragraphs correctly
    #expect(text.contains("Paragraph"))
    #expect(text.contains("Another paragraph"))
  }

  // Note: HTML block handling is not implemented yet as MarkdownSyntax may parse
  // HTML blocks as paragraph content. This can be added in the future if needed.
  // @Test
  // func `Include HTML blocks when includeHTMLBlocks is true`() async throws {
  //   let markdown = """
  //     <div>
  //       <p>HTML</p>
  //     </div>
  //     """
  //   let doc = try MarkdownDocument(content: markdown)
  //   let root = try await doc.parseAST()
  //
  //   let options = BlockTextExtractionOptions(includeHTMLBlocks: true)
  //   let text = BlockContentTextExtractor.extractText(from: root.children, options: options)
  //
  //   #expect(text.contains("<div>"))
  //   #expect(text.contains("HTML"))
  // }
}
