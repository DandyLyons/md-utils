import Testing
@testable import MarkdownUtilities

@Suite("MarkdownDocument Section Reordering Tests")
struct MarkdownDocumentSectionReorderingTests {

  @Test
  func `Move section up with 1-based index`() async throws {
    let doc = try MarkdownDocument(content: """
      # First
      Content 1.
      # Second
      Content 2.
      """)

    let result = try await doc.moveSectionUp(at: 2)

    #expect(result.body.hasPrefix("# Second"))
    #expect(result.body.contains("# First"))
  }

  @Test
  func `Move section down with 1-based index`() async throws {
    let doc = try MarkdownDocument(content: """
      # First
      Content 1.
      # Second
      Content 2.
      """)

    let result = try await doc.moveSectionDown(at: 1)

    #expect(result.body.hasPrefix("# Second"))
  }

  @Test
  func `Move section up by name`() async throws {
    let doc = try MarkdownDocument(content: """
      # Introduction
      Intro text.
      # Contributing
      Contrib text.
      """)

    let result = try await doc.moveSectionUp(byName: "contributing")

    #expect(result.body.hasPrefix("# Contributing"))
  }

  @Test
  func `Move section down by name`() async throws {
    let doc = try MarkdownDocument(content: """
      # Introduction
      Intro text.
      # Contributing
      Contrib text.
      """)

    let result = try await doc.moveSectionDown(byName: "Introduction")

    #expect(result.body.hasPrefix("# Contributing"))
  }

  @Test
  func `Move section to position`() async throws {
    let doc = try MarkdownDocument(content: """
      # A
      # B
      # C
      """)

    let result = try await doc.moveSection(at: 3, toPosition: 1)

    #expect(result.body.hasPrefix("# C"))
  }

  @Test
  func `Move section to position by name`() async throws {
    let doc = try MarkdownDocument(content: """
      # Alpha
      # Beta
      # Gamma
      """)

    let result = try await doc.moveSection(byName: "gamma", toPosition: 1)

    #expect(result.body.hasPrefix("# Gamma"))
  }

  @Test
  func `Frontmatter is preserved after move`() async throws {
    let doc = try MarkdownDocument(content: """
      ---
      title: Test
      ---
      # First
      Content 1.
      # Second
      Content 2.
      """)

    let result = try await doc.moveSectionUp(at: 2)

    #expect(!result.frontMatter.isEmpty)
    #expect(result.body.hasPrefix("# Second"))
  }

  @Test
  func `Move section up by count of 2`() async throws {
    let doc = try MarkdownDocument(content: """
      # A
      Content A.
      # B
      Content B.
      # C
      Content C.
      """)

    let result = try await doc.moveSectionUp(at: 3, count: 2)

    #expect(result.body.hasPrefix("# C"))
  }

  @Test
  func `Move section down by count of 2`() async throws {
    let doc = try MarkdownDocument(content: """
      # A
      Content A.
      # B
      Content B.
      # C
      Content C.
      """)

    let result = try await doc.moveSectionDown(at: 1, count: 2)

    #expect(result.body.hasPrefix("# B"))
    #expect(result.body.hasSuffix("Content A."))
  }

  @Test
  func `Sequential moves produce correct result`() async throws {
    let doc = try MarkdownDocument(content: """
      # A
      Content A.
      # B
      Content B.
      # C
      Content C.
      """)

    // Move A down, then down again (A goes from position 1 to 3)
    let step1 = try await doc.moveSectionDown(at: 1)
    // After step1: B, A, C — A is now at heading index 1 (still 0-based)
    let step2 = try await step1.moveSectionDown(byName: "A")

    // After step2: B, C, A
    #expect(step2.body.hasPrefix("# B"))
    #expect(step2.body.contains("# C"))
    #expect(step2.body.hasSuffix("Content A."))
  }
}
