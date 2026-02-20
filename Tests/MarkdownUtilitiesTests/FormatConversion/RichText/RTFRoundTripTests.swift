//
//  RTFRoundTripTests.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownUtilities
import Testing

@Suite("RTF Round-Trip Tests")
struct RTFRoundTripTests {

  @Test
  func `Round-trip preserves headings`() async throws {
    let markdown = "# Title\n\nBody text."
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()
    let result = try await MarkdownDocument.fromRTF(data: rtfData)

    #expect(result.contains("# Title") || result.contains("## Title"))
    #expect(result.contains("Body text."))
  }

  @Test
  func `Round-trip preserves bold and italic`() async throws {
    let markdown = "This has **bold** and *italic* text."
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()
    let result = try await MarkdownDocument.fromRTF(data: rtfData)

    #expect(result.contains("**bold**"))
    #expect(result.contains("*italic*"))
  }

  @Test
  func `Round-trip preserves inline code`() async throws {
    let markdown = "Use `print()` for output."
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()
    let result = try await MarkdownDocument.fromRTF(data: rtfData)

    #expect(result.contains("`print()`"))
  }

  @Test
  func `Round-trip preserves links`() async throws {
    let markdown = "Visit [Example](https://example.com) now."
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()
    let result = try await MarkdownDocument.fromRTF(data: rtfData)

    #expect(result.contains("[Example](https://example.com)"))
  }

  @Test
  func `Round-trip preserves multiple paragraphs`() async throws {
    let markdown = """
      First paragraph.

      Second paragraph.

      Third paragraph.
      """
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()
    let result = try await MarkdownDocument.fromRTF(data: rtfData)

    #expect(result.contains("First paragraph."))
    #expect(result.contains("Second paragraph."))
    #expect(result.contains("Third paragraph."))
  }
}
