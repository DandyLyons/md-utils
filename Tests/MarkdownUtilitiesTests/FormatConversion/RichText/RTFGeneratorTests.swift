//
//  RTFGeneratorTests.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownUtilities
import Testing

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("RTFGenerator Tests")
struct RTFGeneratorTests {

  // MARK: - Helpers

  /// Creates RTF data from an NSAttributedString.
  private func makeRTF(from attrString: NSAttributedString) throws -> Data {
    let range = NSRange(location: 0, length: attrString.length)
    guard let data = attrString.rtf(from: range, documentAttributes: [
      .documentType: NSAttributedString.DocumentType.rtf,
    ]) else {
      throw RTFConversionError.failedToGenerateRTF
    }
    return data
  }

  private func baseFont(size: CGFloat = 14) -> PlatformFont {
    PlatformFont(name: "Helvetica", size: size) ?? PlatformFont.systemFont(ofSize: size)
  }

  private func boldFont(size: CGFloat = 14) -> PlatformFont {
    #if canImport(AppKit)
    let font = baseFont(size: size)
    return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    #elseif canImport(UIKit)
    return PlatformFont.boldSystemFont(ofSize: size)
    #endif
  }

  private func italicFont(size: CGFloat = 14) -> PlatformFont {
    #if canImport(AppKit)
    let font = baseFont(size: size)
    return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    #elseif canImport(UIKit)
    return PlatformFont.italicSystemFont(ofSize: size)
    #endif
  }

  private func monoFont(size: CGFloat = 14) -> PlatformFont {
    PlatformFont(name: "Menlo", size: size) ?? PlatformFont.systemFont(ofSize: size)
  }

  // MARK: - Tests

  @Test
  func `Generate markdown from plain text RTF`() async throws {
    let attrString = NSAttributedString(string: "Hello, world!", attributes: [
      .font: baseFont(),
    ])
    let data = try makeRTF(from: attrString)

    let markdown = try await MarkdownDocument.fromRTF(data: data)
    #expect(markdown.contains("Hello, world!"))
  }

  @Test
  func `Generate markdown with bold detection`() async throws {
    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "This is ", attributes: [.font: baseFont()]))
    result.append(NSAttributedString(string: "bold", attributes: [.font: boldFont()]))
    result.append(NSAttributedString(string: " text.", attributes: [.font: baseFont()]))

    let data = try makeRTF(from: result)
    let markdown = try await MarkdownDocument.fromRTF(data: data)
    #expect(markdown.contains("**bold**"))
  }

  @Test
  func `Generate markdown with italic detection`() async throws {
    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "This is ", attributes: [.font: baseFont()]))
    result.append(NSAttributedString(string: "italic", attributes: [.font: italicFont()]))
    result.append(NSAttributedString(string: " text.", attributes: [.font: baseFont()]))

    let data = try makeRTF(from: result)
    let markdown = try await MarkdownDocument.fromRTF(data: data)
    #expect(markdown.contains("*italic*"))
  }

  @Test
  func `Generate markdown with inline code detection`() async throws {
    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "Use ", attributes: [.font: baseFont()]))
    result.append(NSAttributedString(string: "print()", attributes: [.font: monoFont()]))
    result.append(NSAttributedString(string: " to output.", attributes: [.font: baseFont()]))

    let data = try makeRTF(from: result)
    let markdown = try await MarkdownDocument.fromRTF(data: data)
    #expect(markdown.contains("`print()`"))
  }

  @Test
  func `Generate markdown with link detection`() async throws {
    let url = URL(string: "https://example.com")
    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "Visit ", attributes: [.font: baseFont()]))
    result.append(NSAttributedString(string: "Example", attributes: [
      .font: baseFont(),
      .link: url as Any,
    ]))
    result.append(NSAttributedString(string: " for info.", attributes: [.font: baseFont()]))

    let data = try makeRTF(from: result)
    let markdown = try await MarkdownDocument.fromRTF(data: data)
    #expect(markdown.contains("[Example](https://example.com)"))
  }

  @Test
  func `Generate markdown with strikethrough detection`() async throws {
    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "This is ", attributes: [.font: baseFont()]))
    result.append(NSAttributedString(string: "deleted", attributes: [
      .font: baseFont(),
      .strikethroughStyle: NSUnderlineStyle.single.rawValue,
    ]))
    result.append(NSAttributedString(string: " text.", attributes: [.font: baseFont()]))

    let data = try makeRTF(from: result)
    let markdown = try await MarkdownDocument.fromRTF(data: data)
    #expect(markdown.contains("~~deleted~~"))
  }

  @Test
  func `Generate markdown with heading detection`() async throws {
    let result = NSMutableAttributedString()
    // Large bold text simulates a heading
    result.append(NSAttributedString(string: "Main Title", attributes: [
      .font: boldFont(size: 28),
    ]))
    result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont()]))
    result.append(NSAttributedString(string: "Body text.", attributes: [.font: baseFont()]))

    let data = try makeRTF(from: result)
    let markdown = try await MarkdownDocument.fromRTF(data: data)
    #expect(markdown.contains("# Main Title"))
    #expect(markdown.contains("Body text."))
  }

  @Test
  func `Generate markdown with code block detection`() async throws {
    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "Example:\n", attributes: [.font: baseFont()]))
    result.append(NSAttributedString(string: "let x = 42\n", attributes: [.font: monoFont()]))
    result.append(NSAttributedString(string: "let y = 43\n", attributes: [.font: monoFont()]))
    result.append(NSAttributedString(string: "End.", attributes: [.font: baseFont()]))

    let data = try makeRTF(from: result)
    let markdown = try await MarkdownDocument.fromRTF(data: data)
    #expect(markdown.contains("```"))
    #expect(markdown.contains("let x = 42"))
    #expect(markdown.contains("let y = 43"))
  }

  @Test
  func `Generate markdown without heading detection when disabled`() async throws {
    let result = NSMutableAttributedString()
    result.append(NSAttributedString(string: "Large Text", attributes: [
      .font: boldFont(size: 28),
    ]))

    let data = try makeRTF(from: result)
    let options = RTFGeneratorOptions(detectHeadings: false)
    let markdown = try await MarkdownDocument.fromRTF(data: data, options: options)
    #expect(!markdown.contains("#"))
    #expect(markdown.contains("Large Text"))
  }

  @Test
  func `Generate markdown from empty RTF`() async throws {
    let attrString = NSAttributedString(string: "", attributes: [.font: baseFont()])
    let data = try makeRTF(from: attrString)
    let markdown = try await MarkdownDocument.fromRTF(data: data)
    #expect(markdown.isEmpty)
  }

  @Test
  func `Invalid RTF data throws error`() async throws {
    let badData = "not rtf data".data(using: .utf8) ?? Data()
    await #expect(throws: RTFConversionError.self) {
      try await MarkdownDocument.fromRTF(data: badData)
    }
  }
}
