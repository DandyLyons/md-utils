//
//  PhrasingContentTextExtractorTests.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownUtilities
import MarkdownSyntax
import Testing

@Suite("PhrasingContentTextExtractor Tests")
struct PhrasingContentTextExtractorTests {

  @Test
  func `Extract text from simple text node`() async throws {
    let markdown = "Hello World"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(text == "Hello World")
  }

  @Test
  func `Extract text from strong (bold) formatting`() async throws {
    let markdown = "This is **bold** text"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(text == "This is bold text")
  }

  @Test
  func `Extract text from emphasis (italic) formatting`() async throws {
    let markdown = "This is *italic* text"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(text == "This is italic text")
  }

  @Test
  func `Extract text from inline code`() async throws {
    let markdown = "Use `print()` to output"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(text == "Use print() to output")
  }

  @Test
  func `Extract text from links ignoring URL`() async throws {
    let markdown = "Visit [my website](https://example.com) today"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(text == "Visit my website today")
  }

  @Test
  func `Extract alt text from images by default`() async throws {
    let markdown = "See this ![beautiful sunset](sunset.jpg) photo"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(text == "See this beautiful sunset photo")
  }

  @Test
  func `Exclude images when extractImageAltText is false`() async throws {
    let markdown = "See this ![beautiful sunset](sunset.jpg) photo"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let options = PhrasingTextExtractionOptions(extractImageAltText: false)
    let text = PhrasingContentTextExtractor.extractText(
      from: paragraph.children,
      options: options
    )

    #expect(text == "See this  photo")
  }

  @Test
  func `Preserve line breaks as newlines by default`() async throws {
    let markdown = "Line 1  \nLine 2"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(text.contains("\n"))
  }

  @Test
  func `Convert line breaks to spaces when preserveLineBreaks is false`() async throws {
    let markdown = "Line 1  \nLine 2"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let options = PhrasingTextExtractionOptions(preserveLineBreaks: false)
    let text = PhrasingContentTextExtractor.extractText(
      from: paragraph.children,
      options: options
    )

    #expect(!text.contains("\n"))
    #expect(text.contains(" "))
  }

  @Test
  func `Extract text from nested formatting`() async throws {
    let markdown = "This is ***bold and italic*** text"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(text == "This is bold and italic text")
  }

  @Test
  func `Extract text from delete (strikethrough) formatting`() async throws {
    let markdown = "This is ~~deleted~~ text"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(text == "This is deleted text")
  }

  @Test
  func `Skip HTML content by default`() async throws {
    let markdown = "Text with <span>HTML</span> inside"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let text = PhrasingContentTextExtractor.extractText(from: paragraph.children)

    #expect(!text.contains("<span>"))
    #expect(!text.contains("</span>"))
  }

  @Test
  func `Include HTML when includeHTML is true`() async throws {
    let markdown = "Text with <span>HTML</span> inside"
    let doc = try MarkdownDocument(content: markdown)
    let root = try await doc.parseAST()

    let paragraph = try #require(root.children[0] as? Paragraph)
    let options = PhrasingTextExtractionOptions(includeHTML: true)
    let text = PhrasingContentTextExtractor.extractText(
      from: paragraph.children,
      options: options
    )

    #expect(text.contains("<span>"))
    #expect(text.contains("</span>"))
  }
}
