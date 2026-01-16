//
//  MarkdownDocumentTests.swift
//  MarkdownUtilitiesTests
//

import Testing
@testable import MarkdownUtilities

@Suite("MarkdownDocument Tests")
struct MarkdownDocumentTests {

  @Test
  func `Initialize MarkdownDocument with content`() async throws {
    let content = "# Hello World\n\nThis is a test."
    let doc = try MarkdownDocument(content: content)

    #expect(doc.body == content)
    #expect(doc.frontMatter.isEmpty)
  }

  @Test
  func `Initialize MarkdownDocument with empty content`() async throws {
    let doc = try MarkdownDocument(content: "")

    #expect(doc.body.isEmpty)
    #expect(doc.frontMatter.isEmpty)
  }
}
