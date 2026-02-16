//
//  RTFConverterTests.swift
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

@Suite("RTFConverter Tests")
struct RTFConverterTests {

  // MARK: - Helper

  /// Loads RTF data back into an NSAttributedString for inspection.
  private func loadRTF(_ data: Data) throws -> NSAttributedString {
    #if canImport(AppKit)
    guard let attrString = NSAttributedString(rtf: data, documentAttributes: nil) else {
      throw RTFConversionError.failedToParseRTF
    }
    return attrString
    #elseif canImport(UIKit)
    return try NSAttributedString(
      data: data,
      options: [.documentType: NSAttributedString.DocumentType.rtf],
      documentAttributes: nil
    )
    #endif
  }

  // MARK: - Basic Conversion

  @Test
  func `Convert simple paragraph to RTF`() async throws {
    let markdown = "Hello, world!"
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.contains("Hello, world!"))
  }

  @Test
  func `Convert heading to RTF with larger font`() async throws {
    let markdown = "# Main Title"
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.contains("Main Title"))

    // Check that the heading has a larger font size than the default
    let attrs = attrString.attributes(at: 0, effectiveRange: nil)
    let font = try #require(attrs[.font] as? PlatformFont)
    // h1 scale is 2.0 × 14 = 28
    #expect(font.pointSize > 20)
  }

  @Test
  func `Convert bold text to RTF`() async throws {
    let markdown = "This is **bold** text."
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.contains("bold"))

    // Find the "bold" text and check its font trait
    let boldRange = (attrString.string as NSString).range(of: "bold")
    let attrs = attrString.attributes(at: boldRange.location, effectiveRange: nil)
    let font = try #require(attrs[.font] as? PlatformFont)

    #if canImport(AppKit)
    let traits = NSFontManager.shared.traits(of: font)
    #expect(traits.contains(.boldFontMask))
    #elseif canImport(UIKit)
    let traits = font.fontDescriptor.symbolicTraits
    #expect(traits.contains(.traitBold))
    #endif
  }

  @Test
  func `Convert italic text to RTF`() async throws {
    let markdown = "This is *italic* text."
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)

    let italicRange = (attrString.string as NSString).range(of: "italic")
    let attrs = attrString.attributes(at: italicRange.location, effectiveRange: nil)
    let font = try #require(attrs[.font] as? PlatformFont)

    #if canImport(AppKit)
    let traits = NSFontManager.shared.traits(of: font)
    #expect(traits.contains(.italicFontMask))
    #elseif canImport(UIKit)
    let traits = font.fontDescriptor.symbolicTraits
    #expect(traits.contains(.traitItalic))
    #endif
  }

  @Test
  func `Convert inline code to RTF with monospace font`() async throws {
    let markdown = "Use `print()` to output."
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)

    let codeRange = (attrString.string as NSString).range(of: "print()")
    let attrs = attrString.attributes(at: codeRange.location, effectiveRange: nil)
    let font = try #require(attrs[.font] as? PlatformFont)

    // Check it uses the monospace font
    let fontName = font.fontName.lowercased()
    #expect(fontName.contains("menlo") || fontName.contains("courier") || fontName.contains("mono"))
  }

  @Test
  func `Convert fenced code block to RTF`() async throws {
    let markdown = """
      Example:

      ```swift
      let x = 42
      ```
      """
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.contains("let x = 42"))
  }

  @Test
  func `Convert link to RTF with link attribute`() async throws {
    let markdown = "Visit [Example](https://example.com) for more."
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.contains("Example"))
    #expect(!attrString.string.contains("https://example.com"))

    let linkRange = (attrString.string as NSString).range(of: "Example")
    let attrs = attrString.attributes(at: linkRange.location, effectiveRange: nil)
    #expect(attrs[.link] != nil)
  }

  @Test
  func `Convert link without link attribute when preserveLinks is false`() async throws {
    let markdown = "Visit [Example](https://example.com) for more."
    let doc = try MarkdownDocument(content: markdown)
    let options = RTFOptions(preserveLinks: false)
    let rtfData = try await doc.toRTF(options: options)

    let attrString = try loadRTF(rtfData)
    let linkRange = (attrString.string as NSString).range(of: "Example")
    let attrs = attrString.attributes(at: linkRange.location, effectiveRange: nil)
    #expect(attrs[.link] == nil)
  }

  @Test
  func `Convert strikethrough to RTF`() async throws {
    let markdown = "This is ~~deleted~~ text."
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.contains("deleted"))

    let deleteRange = (attrString.string as NSString).range(of: "deleted")
    let attrs = attrString.attributes(at: deleteRange.location, effectiveRange: nil)
    let strikethrough = attrs[.strikethroughStyle] as? Int
    #expect(strikethrough != nil && strikethrough != 0)
  }

  @Test
  func `Convert unordered list to RTF`() async throws {
    let markdown = """
      - First item
      - Second item
      - Third item
      """
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    // Bullet character should be present
    #expect(attrString.string.contains("\u{2022}"))
    #expect(attrString.string.contains("First item"))
    #expect(attrString.string.contains("Second item"))
    #expect(attrString.string.contains("Third item"))
  }

  @Test
  func `Convert ordered list to RTF`() async throws {
    let markdown = """
      1. First
      2. Second
      3. Third
      """
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.contains("1."))
    #expect(attrString.string.contains("First"))
    #expect(attrString.string.contains("2."))
    #expect(attrString.string.contains("Second"))
  }

  @Test
  func `Convert thematic break to RTF`() async throws {
    let markdown = """
      Above the break.

      ---

      Below the break.
      """
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.contains("\u{2500}"))
  }

  @Test
  func `Convert blockquote to RTF with indentation`() async throws {
    let markdown = """
      > This is a quote.
      """
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.contains("This is a quote."))

    // Check indentation
    let attrs = attrString.attributes(at: 0, effectiveRange: nil)
    if let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
      #expect(paragraphStyle.firstLineHeadIndent > 0 || paragraphStyle.headIndent > 0)
    }
  }

  @Test
  func `Convert empty document to RTF`() async throws {
    let markdown = ""
    let doc = try MarkdownDocument(content: markdown)
    let rtfData = try await doc.toRTF()

    let attrString = try loadRTF(rtfData)
    #expect(attrString.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  @Test
  func `Custom font options are applied`() async throws {
    let markdown = "Custom font text."
    let doc = try MarkdownDocument(content: markdown)
    let options = RTFOptions(baseFontName: "Georgia", baseFontSize: 18)
    let rtfData = try await doc.toRTF(options: options)

    let attrString = try loadRTF(rtfData)
    let attrs = attrString.attributes(at: 0, effectiveRange: nil)
    let font = try #require(attrs[.font] as? PlatformFont)
    #expect(font.pointSize == 18)
  }
}
