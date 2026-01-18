import Testing
import MarkdownSyntax
@testable import MarkdownUtilities

@Suite("HeadingAdjuster Tests")
struct HeadingAdjusterTests {

  @Test
  func `Promote H2 to H1 with children`() async throws {
    let content = """
      # Main
      ## Section
      ### Subsection
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let options = HeadingAdjuster.Options(
      targetIndex: 1,  // "Section"
      adjustment: -1,  // Promote
      includeChildren: true
    )

    let result = try await HeadingAdjuster.adjust(
      root: root,
      originalContent: content,
      options: options
    )

    #expect(result.adjustedCount == 2)  // Section + Subsection
    #expect(result.hadClampedHeadings == false)

    // Verify the adjusted content
    let expected = """
      # Main
      # Section
      ## Subsection
      """
    #expect(result.content == expected)
  }

  @Test
  func `Demote H1 to H2 with children`() async throws {
    let content = """
      # Main
      ## Section
      ### Subsection
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let options = HeadingAdjuster.Options(
      targetIndex: 0,  // "Main"
      adjustment: 1,   // Demote
      includeChildren: true
    )

    let result = try await HeadingAdjuster.adjust(
      root: root,
      originalContent: content,
      options: options
    )

    #expect(result.adjustedCount == 3)  // All three headings
    #expect(result.hadClampedHeadings == false)

    let expected = """
      ## Main
      ### Section
      #### Subsection
      """
    #expect(result.content == expected)
  }

  @Test
  func `Adjust target only without children`() async throws {
    let content = """
      # Main
      ## Section
      ### Subsection
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let options = HeadingAdjuster.Options(
      targetIndex: 1,  // "Section"
      adjustment: -1,  // Promote
      includeChildren: false
    )

    let result = try await HeadingAdjuster.adjust(
      root: root,
      originalContent: content,
      options: options
    )

    #expect(result.adjustedCount == 1)  // Only Section
    #expect(result.hadClampedHeadings == false)

    let expected = """
      # Main
      # Section
      ### Subsection
      """
    #expect(result.content == expected)
  }

  @Test
  func `Promote H1 clamps at H1`() async throws {
    let content = """
      # Main
      ## Section
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let options = HeadingAdjuster.Options(
      targetIndex: 0,  // "Main"
      adjustment: -1,  // Try to promote H1
      includeChildren: true
    )

    let result = try await HeadingAdjuster.adjust(
      root: root,
      originalContent: content,
      options: options
    )

    #expect(result.adjustedCount == 2)
    #expect(result.hadClampedHeadings == true)  // H1 was clamped

    let expected = """
      # Main
      # Section
      """
    #expect(result.content == expected)
  }

  @Test
  func `Demote H6 clamps at H6`() async throws {
    let content = """
      ###### H6
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let options = HeadingAdjuster.Options(
      targetIndex: 0,
      adjustment: 1,  // Try to demote H6
      includeChildren: true
    )

    let result = try await HeadingAdjuster.adjust(
      root: root,
      originalContent: content,
      options: options
    )

    #expect(result.adjustedCount == 1)
    #expect(result.hadClampedHeadings == true)  // H6 was clamped

    let expected = """
      ###### H6
      """
    #expect(result.content == expected)
  }

  @Test
  func `Error on invalid target index`() async throws {
    let content = """
      # Main
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let options = HeadingAdjuster.Options(
      targetIndex: 5,  // Invalid index
      adjustment: -1,
      includeChildren: true
    )

    await #expect(throws: HeadingAdjusterError.self) {
      try await HeadingAdjuster.adjust(
        root: root,
        originalContent: content,
        options: options
      )
    }
  }

  @Test
  func `Error on no headings in document`() async throws {
    let content = """
      Just some text with no headings.

      Another paragraph.
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let options = HeadingAdjuster.Options(
      targetIndex: 0,
      adjustment: -1,
      includeChildren: true
    )

    await #expect(throws: HeadingAdjusterError.self) {
      try await HeadingAdjuster.adjust(
        root: root,
        originalContent: content,
        options: options
      )
    }
  }

  @Test
  func `Adjust multiple levels at once`() async throws {
    let content = """
      ### H3
      #### H4
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()

    let options = HeadingAdjuster.Options(
      targetIndex: 0,
      adjustment: -2,  // Promote by 2 levels
      includeChildren: true
    )

    let result = try await HeadingAdjuster.adjust(
      root: root,
      originalContent: content,
      options: options
    )

    #expect(result.adjustedCount == 2)
    #expect(result.hadClampedHeadings == false)

    let expected = """
      # H3
      ## H4
      """
    #expect(result.content == expected)
  }
}
