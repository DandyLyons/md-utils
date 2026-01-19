import Testing
@testable import MarkdownUtilities
import MarkdownSyntax

@Suite("SectionBoundaryDetector Tests")
struct SectionBoundaryDetectorTests {

  @Test
  func `Detect first section with no children`() async throws {
    let content = """
      # First
      Some content.
      # Second
      More content.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: 0,
      documentLineCount: 4
    )

    #expect(boundary.lineRange == 1...2)
    #expect(boundary.childIndices.isEmpty)
  }

  @Test
  func `Detect middle section with children`() async throws {
    let content = """
      # First
      ## Subsection 1.1
      ### Subsection 1.1.1
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: 0,
      documentLineCount: 4
    )

    #expect(boundary.lineRange == 1...3)
    #expect(boundary.childIndices == [1, 2])
  }

  @Test
  func `Detect last section extends to end of document`() async throws {
    let content = """
      # First
      Content for first.
      # Second
      Content for second.
      ## Subsection
      More content.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: 1,  // "Second" heading
      documentLineCount: 6
    )

    #expect(boundary.lineRange == 3...6)
    #expect(boundary.childIndices == [2])  // "Subsection"
  }

  @Test
  func `Detect section with multiple nesting levels`() async throws {
    let content = """
      # Main
      ## Level 2
      ### Level 3
      #### Level 4
      ## Another Level 2
      # Next Main
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: 0,
      documentLineCount: 6
    )

    #expect(boundary.lineRange == 1...5)
    #expect(boundary.childIndices == [1, 2, 3, 4])
  }

  @Test
  func `Detect subsection boundary`() async throws {
    let content = """
      # Main
      ## Subsection A
      Content A.
      ## Subsection B
      Content B.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    // Detect boundary for "Subsection A"
    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: 1,
      documentLineCount: 5
    )

    #expect(boundary.lineRange == 2...3)
    #expect(boundary.childIndices.isEmpty)
  }

  @Test
  func `Detect section with content between headings`() async throws {
    let content = """
      # First
      Paragraph 1.
      Paragraph 2.
      ## Subsection
      Subsection content.
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: 0,
      documentLineCount: 6
    )

    #expect(boundary.lineRange == 1...5)
    #expect(boundary.childIndices == [1])
  }

  @Test
  func `Detect single heading document`() async throws {
    let content = """
      # Only Heading
      Some content.
      More content.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: 0,
      documentLineCount: 3
    )

    #expect(boundary.lineRange == 1...3)
    #expect(boundary.childIndices.isEmpty)
  }

  @Test
  func `Detect section with adjacent headings no content`() async throws {
    let content = """
      # First
      ## Sub1
      ## Sub2
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    // Detect "Sub1" section
    let boundary = SectionBoundaryDetector.detect(
      headings: headings,
      targetIndex: 1,
      documentLineCount: 4
    )

    #expect(boundary.lineRange == 2...2)
    #expect(boundary.childIndices.isEmpty)
  }
}
