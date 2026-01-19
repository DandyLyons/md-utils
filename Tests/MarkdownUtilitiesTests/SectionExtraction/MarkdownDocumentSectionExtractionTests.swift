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

  // MARK: - Name-Based Extraction Tests

  @Test
  func `Extract section by name (case-insensitive)`() async throws {
    let content = """
      # Introduction
      Intro text.
      # Contributing
      How to contribute.
      # License
      MIT License.
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, updated) = try await doc.extractSection(
      byName: "contributing",
      caseSensitive: false,
      removeFromOriginal: false
    )

    let expectedExtracted = """
      # Contributing
      How to contribute.
      """
    #expect(extracted.body == expectedExtracted)
    #expect(extracted.frontMatter.isEmpty)
    #expect(updated == nil)
  }

  @Test
  func `Extract section by name (case-sensitive)`() async throws {
    let content = """
      # Introduction
      # API Reference
      # license
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, _) = try await doc.extractSection(
      byName: "license",
      caseSensitive: true,
      removeFromOriginal: false
    )

    let expectedExtracted = """
      # license
      """
    #expect(extracted.body == expectedExtracted)
  }

  @Test
  func `Extract and remove by name preserves frontmatter`() async throws {
    let content = """
      ---
      title: Test Document
      version: 1.0
      ---
      # Section A
      Content A.
      # Section B
      Content B.
      # Section C
      Content C.
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, updated) = try await doc.extractSection(
      byName: "Section B",
      caseSensitive: false,
      removeFromOriginal: true
    )

    // Extracted section has no frontmatter
    #expect(extracted.frontMatter.isEmpty)
    let expectedExtracted = """
      # Section B
      Content B.
      """
    #expect(extracted.body == expectedExtracted)

    // Updated document preserves frontmatter
    let updatedDoc = try #require(updated)
    #expect(!updatedDoc.frontMatter.isEmpty)

    let expectedRemaining = """
      # Section A
      Content A.
      # Section C
      Content C.
      """
    #expect(updatedDoc.body == expectedRemaining)
  }

  @Test
  func `Error message lists available headings`() async throws {
    let content = """
      # Introduction
      # Installation
      # Usage
      # Contributing
      # License
      """

    let doc = try MarkdownDocument(content: content)

    do {
      _ = try await doc.extractSection(byName: "Nonexistent", caseSensitive: false)
      Issue.record("Expected headingNotFound error")
    } catch let error as SectionExtractorError {
      let description = error.description
      #expect(description.contains("Nonexistent"))
      #expect(description.contains("case-insensitive"))
      #expect(description.contains("Available headings:"))
      #expect(description.contains("Introduction"))
      #expect(description.contains("License"))
    }
  }

  @Test
  func `Extract by name with nested content`() async throws {
    let content = """
      # Overview
      # Getting Started
      ## Installation
      ### Via Package Manager
      Instructions here.
      ## Configuration
      Config details.
      # Advanced
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, _) = try await doc.extractSection(
      byName: "Getting Started",
      caseSensitive: false,
      removeFromOriginal: false
    )

    let expectedExtracted = """
      # Getting Started
      ## Installation
      ### Via Package Manager
      Instructions here.
      ## Configuration
      Config details.
      """
    #expect(extracted.body == expectedExtracted)
  }

  @Test
  func `Extract matches first occurrence when duplicates exist`() async throws {
    let content = """
      # Examples
      First example section.
      # Usage
      Usage details.
      # Examples
      More examples here.
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, _) = try await doc.extractSection(
      byName: "Examples",
      caseSensitive: false,
      removeFromOriginal: false
    )

    let expectedExtracted = """
      # Examples
      First example section.
      """
    #expect(extracted.body == expectedExtracted)
  }

  @Test
  func `Case-sensitive match fails when case differs`() async throws {
    let content = """
      # Introduction
      # CONTRIBUTING
      # License
      """

    let doc = try MarkdownDocument(content: content)

    await #expect(throws: SectionExtractorError.self) {
      _ = try await doc.extractSection(
        byName: "contributing",
        caseSensitive: true,
        removeFromOriginal: false
      )
    }
  }

  @Test
  func `Case-insensitive match succeeds when case differs`() async throws {
    let content = """
      # Introduction
      # CONTRIBUTING
      # License
      """

    let doc = try MarkdownDocument(content: content)
    let (extracted, _) = try await doc.extractSection(
      byName: "contributing",
      caseSensitive: false,
      removeFromOriginal: false
    )

    let expectedExtracted = """
      # CONTRIBUTING
      """
    #expect(extracted.body == expectedExtracted)
  }
}
