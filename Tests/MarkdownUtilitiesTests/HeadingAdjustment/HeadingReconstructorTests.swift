import Testing
import MarkdownSyntax
@testable import MarkdownUtilities

@Suite("HeadingReconstructor Tests")
struct HeadingReconstructorTests {

  @Test
  func `Reconstruct with no adjustments returns original`() async throws {
    let content = """
      # Main
      ## Section
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let result = try await HeadingReconstructor.reconstruct(
      root: root,
      originalContent: content,
      adjustments: [:]
    )

    #expect(result == content)
  }

  @Test
  func `Reconstruct with single heading adjustment`() async throws {
    let content = """
      # Main
      ## Section
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let adjustments: [Int: Heading.Depth] = [
      0: .h2  // Change "Main" from H1 to H2
    ]

    let result = try await HeadingReconstructor.reconstruct(
      root: root,
      originalContent: content,
      adjustments: adjustments
    )

    let expected = """
      ## Main
      ## Section
      """
    #expect(result == expected)
  }

  @Test
  func `Reconstruct with multiple heading adjustments`() async throws {
    let content = """
      # Main
      ## Section
      ### Subsection
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let adjustments: [Int: Heading.Depth] = [
      1: .h3,  // Section: H2 -> H3
      2: .h4   // Subsection: H3 -> H4
    ]

    let result = try await HeadingReconstructor.reconstruct(
      root: root,
      originalContent: content,
      adjustments: adjustments
    )

    let expected = """
      # Main
      ### Section
      #### Subsection
      """
    #expect(result == expected)
  }

  @Test
  func `Reconstruct preserves heading text content`() async throws {
    let content = """
      # Heading with **bold** and *italic*
      ## Another heading with [link](url)
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let adjustments: [Int: Heading.Depth] = [
      0: .h2
    ]

    let result = try await HeadingReconstructor.reconstruct(
      root: root,
      originalContent: content,
      adjustments: adjustments
    )

    let expected = """
      ## Heading with **bold** and *italic*
      ## Another heading with [link](url)
      """
    #expect(result == expected)
  }

  @Test
  func `Reconstruct preserves non-heading content`() async throws {
    let content = """
      # Main

      Some paragraph text.

      ## Section

      - List item 1
      - List item 2

      ```swift
      let code = "block"
      ```
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let adjustments: [Int: Heading.Depth] = [
      0: .h2
    ]

    let result = try await HeadingReconstructor.reconstruct(
      root: root,
      originalContent: content,
      adjustments: adjustments
    )

    let expected = """
      ## Main

      Some paragraph text.

      ## Section

      - List item 1
      - List item 2

      ```swift
      let code = "block"
      ```
      """
    #expect(result == expected)
  }

  @Test
  func `Reconstruct handles headings with leading whitespace`() async throws {
    let content = """
        # Indented heading
      ## Less indented
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let adjustments: [Int: Heading.Depth] = [
      0: .h2
    ]

    let result = try await HeadingReconstructor.reconstruct(
      root: root,
      originalContent: content,
      adjustments: adjustments
    )

    let expected = """
        ## Indented heading
      ## Less indented
      """
    #expect(result == expected)
  }

  @Test
  func `Reconstruct all heading levels`() async throws {
    let content = """
      # H1
      ## H2
      ### H3
      #### H4
      ##### H5
      ###### H6
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    // Demote all headings by 1
    let adjustments: [Int: Heading.Depth] = [
      0: .h2,
      1: .h3,
      2: .h4,
      3: .h5,
      4: .h6,
      5: .h6  // Clamped at H6
    ]

    let result = try await HeadingReconstructor.reconstruct(
      root: root,
      originalContent: content,
      adjustments: adjustments
    )

    let expected = """
      ## H1
      ### H2
      #### H3
      ##### H4
      ###### H5
      ###### H6
      """
    #expect(result == expected)
  }
}
