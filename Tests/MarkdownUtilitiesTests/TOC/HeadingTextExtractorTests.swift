//
//  HeadingTextExtractorTests.swift
//  MarkdownUtilitiesTests
//

import Testing
import MarkdownSyntax
@testable import MarkdownUtilities

@Suite("HeadingTextExtractor Tests")
struct HeadingTextExtractorTests {

  // MARK: - Text Extraction Tests

  @Test
  func `Extract text from simple heading`() async throws {
    let content = "# Hello World"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let heading = try #require(root.children[0] as? Heading)
    let text = HeadingTextExtractor.extractText(from: heading)

    #expect(text == "Hello World")
  }

  @Test
  func `Extract text from heading with strong formatting`() async throws {
    let content = "# **Bold** Text"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let heading = try #require(root.children[0] as? Heading)
    let text = HeadingTextExtractor.extractText(from: heading)

    #expect(text == "Bold Text")
  }

  @Test
  func `Extract text from heading with emphasis formatting`() async throws {
    let content = "# *Italic* Text"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let heading = try #require(root.children[0] as? Heading)
    let text = HeadingTextExtractor.extractText(from: heading)

    #expect(text == "Italic Text")
  }

  @Test
  func `Extract text from heading with inline code`() async throws {
    let content = "# Using `code` in Heading"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let heading = try #require(root.children[0] as? Heading)
    let text = HeadingTextExtractor.extractText(from: heading)

    #expect(text == "Using code in Heading")
  }

  @Test
  func `Extract text from heading with link`() async throws {
    let content = "# [Link Text](https://example.com)"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let heading = try #require(root.children[0] as? Heading)
    let text = HeadingTextExtractor.extractText(from: heading)

    // Should extract link text, not URL
    #expect(text == "Link Text")
  }

  @Test
  func `Extract text from heading with nested formatting`() async throws {
    let content = "# **Bold *and Italic* Text**"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let heading = try #require(root.children[0] as? Heading)
    let text = HeadingTextExtractor.extractText(from: heading)

    #expect(text == "Bold and Italic Text")
  }

  @Test
  func `Extract text from heading with multiple elements`() async throws {
    let content = "# **Bold** and *Italic* with `code`"
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let heading = try #require(root.children[0] as? Heading)
    let text = HeadingTextExtractor.extractText(from: heading)

    #expect(text == "Bold and Italic with code")
  }

  // MARK: - Slug Generation Tests

  @Test
  func `Generate simple slug`() async throws {
    let slug = HeadingTextExtractor.generateSlug(from: "Hello World")
    #expect(slug == "hello-world")
  }

  @Test
  func `Generate slug with special characters`() async throws {
    let slug = HeadingTextExtractor.generateSlug(from: "Hello, World!")
    #expect(slug == "hello-world")
  }

  @Test
  func `Generate slug with numbers`() async throws {
    let slug = HeadingTextExtractor.generateSlug(from: "Section 123")
    #expect(slug == "section-123")
  }

  @Test
  func `Generate slug with underscores`() async throws {
    let slug = HeadingTextExtractor.generateSlug(from: "hello_world_test")
    #expect(slug == "hello_world_test")
  }

  @Test
  func `Generate slug with mixed case`() async throws {
    let slug = HeadingTextExtractor.generateSlug(from: "CamelCase Title")
    #expect(slug == "camelcase-title")
  }

  @Test
  func `Generate slug removes leading and trailing hyphens`() async throws {
    let slug = HeadingTextExtractor.generateSlug(from: "---Hello---")
    #expect(slug == "hello")
  }

  @Test
  func `Generate slug for empty text uses default`() async throws {
    let slug = HeadingTextExtractor.generateSlug(from: "")
    #expect(slug == "section")
  }

  @Test
  func `Generate slug for text with only special characters`() async throws {
    let slug = HeadingTextExtractor.generateSlug(from: "!@#$%^&*()")
    #expect(slug == "section")
  }

  @Test
  func `Generate unique slug with existing slugs`() async throws {
    let existingSlugs: Set<String> = ["hello-world"]

    let slug = HeadingTextExtractor.generateSlug(
      from: "Hello World",
      existingSlugs: existingSlugs
    )

    #expect(slug == "hello-world-1")
  }

  @Test
  func `Generate unique slug with multiple duplicates`() async throws {
    let existingSlugs: Set<String> = [
      "hello-world",
      "hello-world-1",
      "hello-world-2",
    ]

    let slug = HeadingTextExtractor.generateSlug(
      from: "Hello World",
      existingSlugs: existingSlugs
    )

    #expect(slug == "hello-world-3")
  }

  @Test
  func `Generate slug with unicode characters`() async throws {
    let slug = HeadingTextExtractor.generateSlug(from: "Café Résumé")
    // Unicode letters should be preserved
    #expect(slug == "café-résumé")
  }
}
