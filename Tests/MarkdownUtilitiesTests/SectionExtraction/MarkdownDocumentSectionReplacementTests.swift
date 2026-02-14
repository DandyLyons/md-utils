import Testing
@testable import MarkdownUtilities

@Suite("MarkdownDocument Section Replacement Tests")
struct MarkdownDocumentSectionReplacementTests {

  @Test
  func `Replace section body by index`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      # Third
      Content 3.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(at: 2, with: "New content.")

    let expected = """
      # First
      Content 1.
      # Second
      New content.
      # Third
      Content 3.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace section body by name`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      # Third
      Content 3.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(byName: "second", with: "New content.")

    let expected = """
      # First
      Content 1.
      # Second
      New content.
      # Third
      Content 3.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace preserves heading text`() async throws {
    let content = """
      # My Heading
      Old body.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(at: 1, with: "New body.")

    let expected = """
      # My Heading
      New body.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace section by name case sensitive`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)

    await #expect(throws: SectionExtractorError.self) {
      _ = try await doc.replaceSection(byName: "second", caseSensitive: true, with: "X")
    }
  }

  @Test
  func `Replace first section`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(at: 1, with: "New content.")

    let expected = """
      # First
      New content.
      # Second
      Content 2.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace last section`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(at: 2, with: "New content.")

    let expected = """
      # First
      Content 1.
      # Second
      New content.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace with longer content`() async throws {
    let content = """
      # First
      Short.
      # Second
      Also short.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(
      at: 1,
      with: "Line 1.\nLine 2.\nLine 3.\nLine 4."
    )

    let expected = """
      # First
      Line 1.
      Line 2.
      Line 3.
      Line 4.
      # Second
      Also short.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace with shorter content`() async throws {
    let content = """
      # First
      Line 1.
      Line 2.
      Line 3.
      # Second
      Content.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(at: 1, with: "Short.")

    let expected = """
      # First
      Short.
      # Second
      Content.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace section with nested headings`() async throws {
    let content = """
      # First
      Content 1.
      ## Subsection
      Nested content.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(at: 1, with: "Simple.")

    let expected = """
      # First
      Simple.
      # Second
      Content 2.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace preserves frontmatter`() async throws {
    let content = """
      ---
      title: Test
      ---
      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(at: 1, with: "New.")

    #expect(!result.frontMatter.isEmpty)
    #expect(result.body.contains("# First"))
    #expect(result.body.contains("New."))
    #expect(result.body.contains("# Second"))
  }

  @Test
  func `Replace with empty content removes body`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(at: 1, with: "")

    let expected = """
      # First
      # Second
      Content 2.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace heading-only section inserts body`() async throws {
    let content = """
      # First
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let result = try await doc.replaceSection(at: 1, with: "New body.")

    let expected = """
      # First
      New body.
      # Second
      Content 2.
      """
    #expect(result.body == expected)
  }

  @Test
  func `Replace section invalid index throws`() async throws {
    let content = """
      # First
      Content.
      """

    let doc = try MarkdownDocument(content: content)

    await #expect(throws: SectionExtractorError.self) {
      _ = try await doc.replaceSection(at: 5, with: "Y")
    }
  }

  @Test
  func `Replace section name not found throws`() async throws {
    let content = """
      # First
      Content.
      """

    let doc = try MarkdownDocument(content: content)

    await #expect(throws: SectionExtractorError.self) {
      _ = try await doc.replaceSection(byName: "Nonexistent", with: "Y")
    }
  }
}
