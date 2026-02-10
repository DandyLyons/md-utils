import Testing
@testable import MarkdownUtilities
import MarkdownSyntax

@Suite("SectionReorderer Tests")
struct SectionReordererTests {

  // MARK: - Move Up Tests

  @Test
  func `Move second H1 up swaps with first`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(1),
      direction: .up
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Second
      Content 2.
      # First
      Content 1.
      """

    #expect(result == expected)
  }

  @Test
  func `Move H2 up among siblings`() async throws {
    let content = """
      # Parent
      ## Child A
      Content A.
      ## Child B
      Content B.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(2),
      direction: .up
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Parent
      ## Child B
      Content B.
      ## Child A
      Content A.
      """

    #expect(result == expected)
  }

  @Test
  func `Move section up with children preserves children`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      ## Sub 2.1
      Sub content.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(1),
      direction: .up
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Second
      Content 2.
      ## Sub 2.1
      Sub content.
      # First
      Content 1.
      """

    #expect(result == expected)
  }

  @Test
  func `Move first section up throws cannotMoveUp`() async throws {
    let content = """
      # First
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(0),
      direction: .up
    )

    #expect(throws: SectionReordererError.cannotMoveUp) {
      try SectionReorderer.reorder(root: root, originalContent: doc.body, options: options)
    }
  }

  // MARK: - Move Down Tests

  @Test
  func `Move first H1 down swaps with second`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(0),
      direction: .down
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Second
      Content 2.
      # First
      Content 1.
      """

    #expect(result == expected)
  }

  @Test
  func `Move last section down throws cannotMoveDown`() async throws {
    let content = """
      # First
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(1),
      direction: .down
    )

    #expect(throws: SectionReordererError.cannotMoveDown) {
      try SectionReorderer.reorder(root: root, originalContent: doc.body, options: options)
    }
  }

  @Test
  func `Move section down with children`() async throws {
    let content = """
      # First
      Content 1.
      ## Sub 1.1
      Sub content.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(0),
      direction: .down
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Second
      Content 2.
      # First
      Content 1.
      ## Sub 1.1
      Sub content.
      """

    #expect(result == expected)
  }

  // MARK: - Name-Based Tests

  @Test
  func `Move section up by name`() async throws {
    let content = """
      # Introduction
      Intro.
      # Contributing
      How to contribute.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .name("Contributing", caseSensitive: false),
      direction: .up
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Contributing
      How to contribute.
      # Introduction
      Intro.
      """

    #expect(result == expected)
  }

  @Test
  func `Move section by name case-insensitive`() async throws {
    let content = """
      # First
      # SECOND
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .name("second", caseSensitive: false),
      direction: .up
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    #expect(result.hasPrefix("# SECOND"))
  }

  // MARK: - Error Cases

  @Test
  func `Empty document throws emptyDocument`() async throws {
    let content = "Some text without headings."
    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(0),
      direction: .up
    )

    #expect(throws: SectionReordererError.noHeadingsInDocument) {
      try SectionReorderer.reorder(root: root, originalContent: doc.body, options: options)
    }
  }

  @Test
  func `Single heading throws noSiblings`() async throws {
    let content = """
      # Only
      Content.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(0),
      direction: .up
    )

    #expect(throws: SectionReordererError.noSiblings) {
      try SectionReorderer.reorder(root: root, originalContent: doc.body, options: options)
    }
  }

  @Test
  func `Invalid index throws invalidTargetIndex`() async throws {
    let content = """
      # First
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(5),
      direction: .up
    )

    #expect(throws: SectionReordererError.self) {
      try SectionReorderer.reorder(root: root, originalContent: doc.body, options: options)
    }
  }

  @Test
  func `Heading not found throws headingNotFound`() async throws {
    let content = """
      # First
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .name("Nonexistent", caseSensitive: false),
      direction: .up
    )

    #expect(throws: SectionReordererError.self) {
      try SectionReorderer.reorder(root: root, originalContent: doc.body, options: options)
    }
  }

  // MARK: - MoveTo Tests

  @Test
  func `Move section to position 1 from position 3`() async throws {
    let content = """
      # Alpha
      Content A.
      # Beta
      Content B.
      # Gamma
      Content G.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.MoveToOptions(
      matchCriteria: .index(2),
      targetPosition: 1
    )

    let result = try SectionReorderer.moveTo(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Gamma
      Content G.
      # Alpha
      Content A.
      # Beta
      Content B.
      """

    #expect(result == expected)
  }

  @Test
  func `Move section to same position returns unchanged`() async throws {
    let content = """
      # Alpha
      # Beta
      # Gamma
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.MoveToOptions(
      matchCriteria: .index(1),
      targetPosition: 2
    )

    let result = try SectionReorderer.moveTo(
      root: root,
      originalContent: doc.body,
      options: options
    )

    #expect(result == doc.body)
  }

  @Test
  func `Move section to last position`() async throws {
    let content = """
      # Alpha
      Content A.
      # Beta
      Content B.
      # Gamma
      Content G.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.MoveToOptions(
      matchCriteria: .index(0),
      targetPosition: 3
    )

    let result = try SectionReorderer.moveTo(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Beta
      Content B.
      # Gamma
      Content G.
      # Alpha
      Content A.
      """

    #expect(result == expected)
  }

  @Test
  func `MoveTo with invalid position throws invalidTargetPosition`() async throws {
    let content = """
      # Alpha
      # Beta
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.MoveToOptions(
      matchCriteria: .index(0),
      targetPosition: 5
    )

    #expect(throws: SectionReordererError.self) {
      try SectionReorderer.moveTo(root: root, originalContent: doc.body, options: options)
    }
  }

  // MARK: - Multi-Position Move Tests

  @Test
  func `Move up by count of 2`() async throws {
    let content = """
      # Alpha
      Content A.
      # Beta
      Content B.
      # Gamma
      Content G.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(2),
      direction: .up,
      count: 2
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Gamma
      Content G.
      # Alpha
      Content A.
      # Beta
      Content B.
      """

    #expect(result == expected)
  }

  @Test
  func `Move down by count of 2`() async throws {
    let content = """
      # Alpha
      Content A.
      # Beta
      Content B.
      # Gamma
      Content G.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(0),
      direction: .down,
      count: 2
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Beta
      Content B.
      # Gamma
      Content G.
      # Alpha
      Content A.
      """

    #expect(result == expected)
  }

  @Test
  func `Count exceeding available positions clamps to boundary`() async throws {
    let content = """
      # Alpha
      Content A.
      # Beta
      Content B.
      # Gamma
      Content G.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    // Gamma is at position 2 (0-based), moving up by 10 should clamp to position 0
    let options = SectionReorderer.Options(
      matchCriteria: .index(2),
      direction: .up,
      count: 10
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Gamma
      Content G.
      # Alpha
      Content A.
      # Beta
      Content B.
      """

    #expect(result == expected)
  }

  @Test
  func `Move up by count with sections that have children`() async throws {
    let content = """
      # Alpha
      Content A.
      ## Sub A
      # Beta
      Content B.
      # Gamma
      Content G.
      ## Sub G
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .name("Gamma", caseSensitive: false),
      direction: .up,
      count: 2
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    #expect(result.hasPrefix("# Gamma"))
    #expect(result.contains("## Sub G"))
    #expect(result.contains("# Alpha"))
    #expect(result.contains("## Sub A"))
    #expect(result.contains("# Beta"))
  }

  // MARK: - Edge Cases

  @Test
  func `Heading-only sections swap correctly`() async throws {
    let content = """
      # First
      # Second
      # Third
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(1),
      direction: .up
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # Second
      # First
      # Third
      """

    #expect(result == expected)
  }

  @Test
  func `Swap preserves content before first heading`() async throws {
    let content = """
      Some intro text.

      # First
      Content 1.
      # Second
      Content 2.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(1),
      direction: .up
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    #expect(result.hasPrefix("Some intro text."))
    #expect(result.contains("# Second"))
    #expect(result.contains("# First"))
  }

  @Test
  func `Swap three-section document middle to top`() async throws {
    let content = """
      # A
      Content A.
      # B
      Content B.
      # C
      Content C.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()

    let options = SectionReorderer.Options(
      matchCriteria: .index(1),
      direction: .up
    )

    let result = try SectionReorderer.reorder(
      root: root,
      originalContent: doc.body,
      options: options
    )

    let expected = """
      # B
      Content B.
      # A
      Content A.
      # C
      Content C.
      """

    #expect(result == expected)
  }
}
