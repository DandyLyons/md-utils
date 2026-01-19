import Testing
@testable import MarkdownUtilities

@Suite("Edge Case Tests")
struct EdgeCaseTests {

  @Test
  func `Preserve frontmatter when adjusting headings`() async throws {
    let content = """
      ---
      title: Test Document
      author: John Doe
      tags:
        - markdown
        - test
      ---
      # Main Heading
      ## Subsection
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 2)  // 2nd heading

    // Check frontmatter is preserved
    #expect(!promoted.frontMatter.isEmpty)

    // Check body is adjusted
    let expectedBody = """
      # Main Heading
      # Subsection
      """
    #expect(promoted.body == expectedBody)

    // Verify we can access frontmatter fields
    let titleNode = promoted.frontMatter["title"]
    #expect(titleNode != nil)
  }

  @Test
  func `Handle document with no frontmatter`() async throws {
    let content = """
      # Main Heading
      ## Subsection
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 1)  // 1st heading

    #expect(promoted.frontMatter.isEmpty)

    let expectedBody = """
      # Main Heading
      # Subsection
      """
    #expect(promoted.body == expectedBody)
  }

  @Test
  func `Handle headings with inline formatting`() async throws {
    let content = """
      # Main **bold** heading
      ## Section with *italic* text
      ### Sub with `code` and [link](url)
      """

    let doc = try MarkdownDocument(content: content)
    let demoted = try await doc.demoteHeading(at: 1)  // 1st heading

    let expected = """
      ## Main **bold** heading
      ### Section with *italic* text
      #### Sub with `code` and [link](url)
      """
    #expect(demoted.body == expected)
  }

  @Test
  func `Handle headings followed by complex content`() async throws {
    let content = """
      # Main

      Paragraph with **formatting**.

      ## Section

      - List item 1
      - List item 2

      ```swift
      func example() {
        print("code")
      }
      ```

      > Blockquote

      ### Subsection

      | Table | Header |
      |-------|--------|
      | Cell  | Data   |
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 2)  // 2nd heading

    // Verify headings adjusted but content preserved
    #expect(promoted.body.contains("# Section"))
    #expect(promoted.body.contains("## Subsection"))
    #expect(promoted.body.contains("- List item 1"))
    #expect(promoted.body.contains("func example()"))
    #expect(promoted.body.contains("> Blockquote"))
    #expect(promoted.body.contains("| Table | Header |"))
  }

  @Test
  func `Handle single heading document`() async throws {
    let content = """
      ## Only Heading
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 1)  // 1st heading

    let expected = """
      # Only Heading
      """
    #expect(promoted.body == expected)
  }

  @Test
  func `Handle heading with trailing whitespace`() async throws {
    let content = """
      # Main  \t
      ## Section
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 2)  // 2nd heading

    // Should preserve essential structure even if whitespace varies slightly
    #expect(promoted.body.contains("# Main"))
    #expect(promoted.body.contains("# Section"))
  }

  @Test
  func `Handle ATX headings with closing hashes`() async throws {
    let content = """
      # Main #
      ## Section ##
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 2)  // 2nd heading

    #expect(promoted.body.contains("# Section"))
  }

  @Test
  func `Handle very long heading text`() async throws {
    let longText = String(repeating: "word ", count: 100)
    let content = """
      # \(longText)
      ## Short
      """

    let doc = try MarkdownDocument(content: content)
    let demoted = try await doc.demoteHeading(at: 1)  // 1st heading

    #expect(demoted.body.hasPrefix("## "))
    #expect(demoted.body.contains(longText))
  }

  @Test
  func `Handle consecutive headings with no content between`() async throws {
    let content = """
      # H1
      ## H2
      ### H3
      #### H4
      ##### H5
      ###### H6
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 1)  // 1st heading

    let expected = """
      # H1
      # H2
      ## H3
      ### H4
      #### H5
      ##### H6
      """
    #expect(promoted.body == expected)
  }

  @Test
  func `Preserve Unicode characters in headings`() async throws {
    let content = """
      # 你好世界 🌍
      ## Émojis and 日本語
      ### Ñoño с кириллицей
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 2)  // 2nd heading

    #expect(promoted.body.contains("# Émojis and 日本語"))
    #expect(promoted.body.contains("## Ñoño с кириллицей"))
    #expect(promoted.body.contains("你好世界 🌍"))
  }

  @Test
  func `Handle headings in nested blockquotes`() async throws {
    // Note: Markdown parsers may handle this differently
    let content = """
      # Main

      > ## Quoted heading
      > ### Nested quoted heading

      ## Normal heading
      """

    let doc = try MarkdownDocument(content: content)

    // The behavior here depends on how MarkdownSyntax handles blockquote headings
    // We just verify it doesn't crash and produces valid output
    let demoted = try await doc.demoteHeading(at: 1)  // 1st heading
    #expect(demoted.body.contains("## Main"))
  }

  @Test
  func `Error handling for invalid index`() async throws {
    let content = """
      # Main
      ## Section
      """

    let doc = try MarkdownDocument(content: content)

    await #expect(throws: HeadingAdjusterError.self) {
      try await doc.promoteHeading(at: 10)
    }

    await #expect(throws: HeadingAdjusterError.self) {
      try await doc.promoteHeading(at: -1)
    }
  }

  @Test
  func `Error handling for document with no headings`() async throws {
    let content = """
      Just some text with no headings at all.

      Multiple paragraphs.

      - Even lists
      - But no headings
      """

    let doc = try MarkdownDocument(content: content)

    await #expect(throws: HeadingAdjusterError.self) {
      try await doc.promoteHeading(at: 1)  // 1st heading, but there are no headings
    }
  }

  @Test
  func `Clamping behavior at boundaries`() async throws {
    let content = """
      # H1
      ###### H6
      """

    let doc = try MarkdownDocument(content: content)

    // Try to promote H1 (should clamp)
    let promoted = try await doc.promoteHeading(at: 1, includeChildren: false)  // 1st heading
    #expect(promoted.body.hasPrefix("# H1"))

    // Try to demote H6 (should clamp)
    let demoted = try await doc.demoteHeading(at: 2, includeChildren: false)  // 2nd heading
    #expect(demoted.body.contains("###### H6"))
  }

  @Test
  func `Handle empty document with frontmatter only`() async throws {
    let content = """
      ---
      title: Test
      ---
      """

    let doc = try MarkdownDocument(content: content)

    await #expect(throws: HeadingAdjusterError.self) {
      try await doc.promoteHeading(at: 1)  // 1st heading, but there are no headings
    }
  }
}
