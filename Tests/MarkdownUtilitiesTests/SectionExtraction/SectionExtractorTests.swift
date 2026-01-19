import Testing
@testable import MarkdownUtilities
import MarkdownSyntax

@Suite("SectionExtractor Tests")
struct SectionExtractorTests {

  @Test
  func `Extract first section without removal`() async throws {
    let content = """
      # First
      Content for first.
      # Second
      Content for second.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 0, removeFromOriginal: false)
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # First
      Content for first.
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.lineRange == 1...2)
    #expect(result.section.childHeadingCount == 0)
    #expect(result.remainingContent == nil)
  }

  @Test
  func `Extract section with children`() async throws {
    let content = """
      # Main
      ## Subsection
      ### Deep
      Content.
      # Next
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 0, removeFromOriginal: false)
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # Main
      ## Subsection
      ### Deep
      Content.
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.lineRange == 1...4)
    #expect(result.section.childHeadingCount == 2)
  }

  @Test
  func `Extract section with removal`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      # Third
      Content 3.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 1, removeFromOriginal: true)
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # Second
      Content 2.
      """
    #expect(result.section.text == expectedSection)

    let expectedRemaining = """
      # First
      Content 1.
      # Third
      Content 3.
      """
    #expect(result.remainingContent == expectedRemaining)
  }

  @Test
  func `Extract last section extends to end`() async throws {
    let content = """
      # First
      # Second
      ## Subsection
      Final content.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 1, removeFromOriginal: false)
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # Second
      ## Subsection
      Final content.
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.lineRange == 2...4)
    #expect(result.section.childHeadingCount == 1)
  }

  @Test
  func `Extract middle subsection`() async throws {
    let content = """
      # Main
      ## First Sub
      Content A.
      ## Second Sub
      Content B.
      ## Third Sub
      Content C.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 2, removeFromOriginal: false)
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      ## Second Sub
      Content B.
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.lineRange == 4...5)
    #expect(result.section.childHeadingCount == 0)
  }

  @Test
  func `Extract single heading document`() async throws {
    let content = """
      # Only
      Some text.
      More text.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 0, removeFromOriginal: false)
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    #expect(result.section.text == content)
    #expect(result.section.lineRange == 1...3)
  }

  @Test
  func `Error on empty document`() async throws {
    let content = ""

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 0, removeFromOriginal: false)

    await #expect(throws: SectionExtractorError.emptyDocument) {
      try await SectionExtractor.extract(root: root, originalContent: content, options: options)
    }
  }

  @Test
  func `Error on no headings`() async throws {
    let content = """
      Just a paragraph.
      No headings here.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 0, removeFromOriginal: false)

    await #expect(throws: SectionExtractorError.noHeadingsInDocument) {
      try await SectionExtractor.extract(root: root, originalContent: content, options: options)
    }
  }

  @Test
  func `Error on invalid index too large`() async throws {
    let content = """
      # First
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 5, removeFromOriginal: false)

    await #expect(throws: SectionExtractorError.self) {
      try await SectionExtractor.extract(root: root, originalContent: content, options: options)
    }
  }

  @Test
  func `Error on invalid index negative`() async throws {
    let content = """
      # First
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: -1, removeFromOriginal: false)

    await #expect(throws: SectionExtractorError.self) {
      try await SectionExtractor.extract(root: root, originalContent: content, options: options)
    }
  }

  @Test
  func `Extract with multiple nesting levels`() async throws {
    let content = """
      # H1
      ## H2
      ### H3
      #### H4
      Content.
      ## Another H2
      # Next H1
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(targetIndex: 0, removeFromOriginal: false)
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # H1
      ## H2
      ### H3
      #### H4
      Content.
      ## Another H2
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.childHeadingCount == 4)
  }

  // MARK: - Name-Based Extraction Tests

  @Test
  func `Extract by exact name match (case-insensitive)`() async throws {
    let content = """
      # Introduction
      Intro content.
      # Contributing
      How to contribute.
      # License
      MIT License.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(
      matchCriteria: .name("contributing", caseSensitive: false),
      removeFromOriginal: false
    )
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # Contributing
      How to contribute.
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.lineRange == 3...4)
  }

  @Test
  func `Extract by exact name match (case-sensitive)`() async throws {
    let content = """
      # Introduction
      # API Reference
      # license
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(
      matchCriteria: .name("license", caseSensitive: true),
      removeFromOriginal: false
    )
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # license
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.lineRange == 3...3)
  }

  @Test
  func `Error when heading not found (case-insensitive)`() async throws {
    let content = """
      # Introduction
      # Contributing
      # License
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(
      matchCriteria: .name("Nonexistent", caseSensitive: false),
      removeFromOriginal: false
    )

    do {
      _ = try await SectionExtractor.extract(
        root: root,
        originalContent: content,
        options: options
      )
      Issue.record("Expected headingNotFound error")
    } catch let error as SectionExtractorError {
      guard case .headingNotFound(let name, let caseSensitive, let available) = error else {
        Issue.record("Expected headingNotFound error, got: \(error)")
        return
      }
      #expect(name == "Nonexistent")
      #expect(caseSensitive == false)
      #expect(available == ["Introduction", "Contributing", "License"])
    }
  }

  @Test
  func `Error when heading not found (case-sensitive)`() async throws {
    let content = """
      # Introduction
      # Contributing
      # License
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(
      matchCriteria: .name("INTRODUCTION", caseSensitive: true),
      removeFromOriginal: false
    )

    do {
      _ = try await SectionExtractor.extract(
        root: root,
        originalContent: content,
        options: options
      )
      Issue.record("Expected headingNotFound error")
    } catch let error as SectionExtractorError {
      guard case .headingNotFound(let name, let caseSensitive, let available) = error else {
        Issue.record("Expected headingNotFound error, got: \(error)")
        return
      }
      #expect(name == "INTRODUCTION")
      #expect(caseSensitive == true)
      #expect(available == ["Introduction", "Contributing", "License"])
    }
  }

  @Test
  func `Extract first match when multiple headings have same text`() async throws {
    let content = """
      # Section
      First occurrence.
      # Section
      Second occurrence.
      # Different
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(
      matchCriteria: .name("Section", caseSensitive: false),
      removeFromOriginal: false
    )
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # Section
      First occurrence.
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.lineRange == 1...2)
  }

  @Test
  func `Match heading with special characters`() async throws {
    let content = """
      # Getting Started
      # API & SDK
      # Q&A (FAQ)
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(
      matchCriteria: .name("API & SDK", caseSensitive: false),
      removeFromOriginal: false
    )
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # API & SDK
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.lineRange == 2...2)
  }

  @Test
  func `Match heading with formatting (bold, italic, code)`() async throws {
    let content = """
      # Introduction
      # **Bold** _Italic_ `Code`
      Content here.
      # Next
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    // HeadingTextExtractor strips formatting, so we match "Bold Italic Code"
    let options = SectionExtractor.Options(
      matchCriteria: .name("Bold Italic Code", caseSensitive: false),
      removeFromOriginal: false
    )
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # **Bold** _Italic_ `Code`
      Content here.
      """
    #expect(result.section.text == expectedSection)
    #expect(result.section.lineRange == 2...3)
  }

  @Test
  func `Extract by name with removal`() async throws {
    let content = """
      # First
      Content 1.
      # Target
      Target content.
      # Third
      Content 3.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionExtractor.Options(
      matchCriteria: .name("Target", caseSensitive: false),
      removeFromOriginal: true
    )
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: content,
      options: options
    )

    let expectedSection = """
      # Target
      Target content.
      """
    #expect(result.section.text == expectedSection)

    let expectedRemaining = """
      # First
      Content 1.
      # Third
      Content 3.
      """
    #expect(result.remainingContent == expectedRemaining)
  }
}
