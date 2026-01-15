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
    let doc = MarkdownDocument(content: content)

    #expect(doc.content == content)
  }

  @Test
  func `Initialize MarkdownDocument with empty content`() async throws {
    let doc = MarkdownDocument(content: "")

    #expect(doc.content.isEmpty)
  }
}
