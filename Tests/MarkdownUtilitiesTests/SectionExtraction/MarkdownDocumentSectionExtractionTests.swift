import Testing
@testable import MarkdownUtilities

@Suite("MarkdownDocument Section Extraction Tests")
struct MarkdownDocumentSectionExtractionTests {

  @Test
  func `Extract section using 1-based indexing`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, updated) = try await doc.extractSection(at: 1, removeFromOriginal: false)

    let expectedExtracted = """
      # First
      Content 1.
      """
    #expect(extracted.body == expectedExtracted)
    #expect(extracted.frontMatter.isEmpty)
    #expect(updated == nil)
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
    let (extracted, updated) = try await doc.extractSection(at: 2, removeFromOriginal: true)

    let expectedExtracted = """
      # Second
      Content 2.
      """
    #expect(extracted.body == expectedExtracted)

    let updatedDoc = try #require(updated)
    let expectedRemaining = """
      # First
      Content 1.
      # Third
      Content 3.
      """
    #expect(updatedDoc.body == expectedRemaining)
  }

  @Test
  func `Extract preserves frontmatter in updated document`() async throws {
    let content = """
      ---
      title: Test Document
      author: Test Author
      ---
      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, updated) = try await doc.extractSection(at: 1, removeFromOriginal: true)

    // Extracted section has no frontmatter
    #expect(extracted.frontMatter.isEmpty)

    // Updated document preserves frontmatter
    let updatedDoc = try #require(updated)
    #expect(!updatedDoc.frontMatter.isEmpty)

    // Verify frontmatter values
    let titleNode = updatedDoc.getValue(forKey: "title")
    #expect(titleNode != nil)

    let expectedBody = """
      # Second
      Content 2.
      """
    #expect(updatedDoc.body == expectedBody)
  }

  @Test
  func `Extract section with nested children`() async throws {
    let content = """
      # Main
      ## Subsection
      ### Deep
      Content here.
      # Next
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, _) = try await doc.extractSection(at: 1, removeFromOriginal: false)

    let expectedExtracted = """
      # Main
      ## Subsection
      ### Deep
      Content here.
      """
    #expect(extracted.body == expectedExtracted)
  }

  @Test
  func `Extract last section`() async throws {
    let content = """
      # First
      # Second
      ## Sub
      Final content.
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, _) = try await doc.extractSection(at: 2, removeFromOriginal: false)

    let expectedExtracted = """
      # Second
      ## Sub
      Final content.
      """
    #expect(extracted.body == expectedExtracted)
  }

  @Test
  func `Extract with frontmatter but no removal`() async throws {
    let content = """
      ---
      title: My Doc
      ---
      # Section
      Content.
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, updated) = try await doc.extractSection(at: 1, removeFromOriginal: false)

    // Extracted section has no frontmatter
    #expect(extracted.frontMatter.isEmpty)
    let expectedExtracted = """
      # Section
      Content.
      """
    #expect(extracted.body == expectedExtracted)

    // No updated document when not removing
    #expect(updated == nil)
  }

  @Test
  func `Error on index 0 with 1-based indexing`() async throws {
    let content = """
      # First
      """

    let doc = try MarkdownDocument(content: content)

    await #expect(throws: SectionExtractorError.self) {
      _ = try await doc.extractSection(at: 0)
    }
  }

  @Test
  func `Error on index too large`() async throws {
    let content = """
      # First
      # Second
      """

    let doc = try MarkdownDocument(content: content)

    await #expect(throws: SectionExtractorError.self) {
      _ = try await doc.extractSection(at: 10)
    }
  }

  @Test
  func `Extract multiple sections in sequence`() async throws {
    let content = """
      # A
      Content A.
      # B
      Content B.
      # C
      Content C.
      """

    let doc = try MarkdownDocument(content: content)

    // Extract first section
    let (section1, doc2) = try await doc.extractSection(at: 1, removeFromOriginal: true)
    #expect(section1.body == "# A\nContent A.")

    let doc2Required = try #require(doc2)

    // Extract first section from remaining (which was originally second)
    let (section2, doc3) = try await doc2Required.extractSection(at: 1, removeFromOriginal: true)
    #expect(section2.body == "# B\nContent B.")

    let doc3Required = try #require(doc3)
    #expect(doc3Required.body == "# C\nContent C.")
  }

  @Test
  func `Extract subsection by index`() async throws {
    let content = """
      # Main
      ## Sub 1
      Content 1.
      ## Sub 2
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)

    // Extract the second heading (Sub 1)
    let (extracted, _) = try await doc.extractSection(at: 2, removeFromOriginal: false)

    let expectedExtracted = """
      ## Sub 1
      Content 1.
      """
    #expect(extracted.body == expectedExtracted)
  }
}
