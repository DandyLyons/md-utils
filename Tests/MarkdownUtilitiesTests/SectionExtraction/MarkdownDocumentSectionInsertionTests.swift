import Testing
@testable import MarkdownUtilities

@Suite("MarkdownDocument Section Insertion Tests")
struct MarkdownDocumentSectionInsertionTests {
  @Test
  func `insert body-only content after named section`() async throws {
    let doc = try MarkdownDocument(content: """
      ## Old Section
      Old body.
      ## Next Section
      Next body.
      """)

    let result = try await doc.insertSection(
      name: "New Section",
      content: "Body text.",
      placement: .after(.name("Old Section", caseSensitive: false))
    )

    #expect(result.body == """
      ## Old Section
      Old body.

      ## New Section

      Body text.

      ## Next Section
      Next body.
      """)
  }

  @Test
  func `insert matching headed content normalizes heading levels`() async throws {
    let doc = try MarkdownDocument(content: """
      ## Old Section
      Old body.
      ## Next Section
      Next body.
      """)

    let result = try await doc.insertSection(
      name: "New Section",
      content: """
        # New Section
        Intro.
        ## Detail
        Nested detail.
        """,
      placement: .after(.name("Old Section", caseSensitive: false))
    )

    #expect(result.body.contains("""
      ## New Section
      Intro.
      ### Detail
      Nested detail.
      """))
  }

  @Test
  func `insert body-only content shifts headings that would escape section`() async throws {
    let doc = try MarkdownDocument(content: """
      ## Old Section
      Old body.
      ## Next Section
      Next body.
      """)

    let result = try await doc.insertSection(
      name: "New Section",
      content: """
        Intro.
        # Detail
        Nested detail.
        """,
      placement: .after(.name("Old Section", caseSensitive: false))
    )

    #expect(result.body.contains("""
      ## New Section

      Intro.
      ### Detail
      Nested detail.
      """))
  }

  @Test
  func `insert matching headed content errors if shift exceeds h6`() async throws {
    let doc = try MarkdownDocument(content: """
      ###### Old Section
      Old body.
      """)

    await #expect(throws: SectionInsertionError.headingShiftOutOfRange(title: "Detail", requestedLevel: 7)) {
      try await doc.insertSection(
        name: "New Section",
        content: """
          # New Section
          ## Detail
          Nested detail.
          """,
        placement: .after(.name("Old Section", caseSensitive: false))
      )
    }
  }

  @Test
  func `insert headed content errors when heading name differs`() async throws {
    let doc = try MarkdownDocument(content: """
      ## Old Section
      Old body.
      """)

    await #expect(throws: SectionInsertionError.mismatchedInputHeading(actual: "Different", expected: "New Section")) {
      try await doc.insertSection(
        name: "New Section",
        content: "# Different\nBody.",
        placement: .after(.name("Old Section", caseSensitive: false))
      )
    }
  }

  @Test
  func `remove section removes descendants`() async throws {
    let doc = try MarkdownDocument(content: """
      # Keep
      Keep body.
      # Remove
      Remove body.
      ## Child
      Child body.
      # After
      After body.
      """)

    let result = try await doc.removeSection(byName: "Remove")

    #expect(result.body == """
      # Keep
      Keep body.
      # After
      After body.
      """)
  }
}
