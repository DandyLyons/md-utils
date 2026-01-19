import Testing
@testable import MarkdownUtilities

@Suite("MarkdownDocument Integration Tests")
struct MarkdownDocumentIntegrationTests {

  @Test
  func `promoteHeading convenience method`() async throws {
    let content = """
      # Main
      ## Section
      ### Subsection
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 2)  // 2nd heading

    let expected = """
      # Main
      # Section
      ## Subsection
      """
    #expect(promoted.body == expected)
  }

  @Test
  func `demoteHeading convenience method`() async throws {
    let content = """
      # Main
      ## Section
      ### Subsection
      """

    let doc = try MarkdownDocument(content: content)
    let demoted = try await doc.demoteHeading(at: 1)  // 1st heading

    let expected = """
      ## Main
      ### Section
      #### Subsection
      """
    #expect(demoted.body == expected)
  }

  @Test
  func `adjustHeading with negative amount promotes`() async throws {
    let content = """
      ### H3
      """

    let doc = try MarkdownDocument(content: content)
    let adjusted = try await doc.adjustHeading(at: 1, by: -2)  // 1st heading

    let expected = """
      # H3
      """
    #expect(adjusted.body == expected)
  }

  @Test
  func `adjustHeading with positive amount demotes`() async throws {
    let content = """
      # H1
      """

    let doc = try MarkdownDocument(content: content)
    let adjusted = try await doc.adjustHeading(at: 1, by: 3)  // 1st heading

    let expected = """
      #### H1
      """
    #expect(adjusted.body == expected)
  }

  @Test
  func `promoteHeading target only`() async throws {
    let content = """
      # Main
      ## Section
      ### Subsection
      """

    let doc = try MarkdownDocument(content: content)
    let promoted = try await doc.promoteHeading(at: 2, includeChildren: false)  // 2nd heading

    let expected = """
      # Main
      # Section
      ### Subsection
      """
    #expect(promoted.body == expected)
  }

  @Test
  func `demoteHeading target only`() async throws {
    let content = """
      # Main
      ## Section
      ### Subsection
      """

    let doc = try MarkdownDocument(content: content)
    let demoted = try await doc.demoteHeading(at: 1, includeChildren: false)  // 1st heading

    let expected = """
      ## Main
      ## Section
      ### Subsection
      """
    #expect(demoted.body == expected)
  }

  @Test
  func `Round-trip preserve content`() async throws {
    let content = """
      # Main

      Some text.

      ## Section

      - List
      """

    let doc = try MarkdownDocument(content: content)
    let adjusted = try await doc.demoteHeading(at: 1)  // 1st heading
    let backAgain = try await adjusted.promoteHeading(at: 1)  // 1st heading

    #expect(backAgain.body == content)
  }

  @Test
  func `Chained adjustments`() async throws {
    let content = """
      # H1
      ## H2
      ### H3
      """

    let doc = try MarkdownDocument(content: content)
    let step1 = try await doc.demoteHeading(at: 1)  // 1st heading: All become H2, H3, H4
    let step2 = try await step1.promoteHeading(at: 2)  // 2nd heading and child: H3→H2, H4→H3

    let expected = """
      ## H1
      ## H2
      ### H3
      """
    #expect(step2.body == expected)
  }
}
