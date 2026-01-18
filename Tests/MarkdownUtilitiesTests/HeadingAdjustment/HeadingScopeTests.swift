import Testing
import MarkdownSyntax
@testable import MarkdownUtilities

@Suite("HeadingScope Tests")
struct HeadingScopeTests {

  @Test
  func `Identify scope with nested children`() async throws {
    let content = """
      # H1
      ## H2
      ### H3
      ## H2
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()
    let headings = root.children.compactMap { $0 as? Heading }

    // Target the first H1 (index 0)
    let scope = HeadingScope.identify(headings: headings, targetIndex: 0)

    #expect(scope.targetIndex == 0)
    #expect(scope.targetDepth == 1)
    #expect(scope.childIndices == [1, 2, 3])  // All subsequent headings are children
  }

  @Test
  func `Identify scope for heading with no children`() async throws {
    let content = """
      # H1
      ## H2
      # H1
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()
    let headings = root.children.compactMap { $0 as? Heading }

    // Target the second H2 (index 1) - no children before next H1
    let scope = HeadingScope.identify(headings: headings, targetIndex: 1)

    #expect(scope.targetIndex == 1)
    #expect(scope.targetDepth == 2)
    #expect(scope.childIndices.isEmpty)  // No children
  }

  @Test
  func `Identify scope for last heading`() async throws {
    let content = """
      # H1
      ## H2
      ### H3
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()
    let headings = root.children.compactMap { $0 as? Heading }

    // Target the last heading (H3, index 2)
    let scope = HeadingScope.identify(headings: headings, targetIndex: 2)

    #expect(scope.targetIndex == 2)
    #expect(scope.targetDepth == 3)
    #expect(scope.childIndices.isEmpty)  // Last heading has no children
  }

  @Test
  func `Identify scope with non-contiguous levels`() async throws {
    let content = """
      # H1
      ### H3
      ##### H5
      ## H2
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()
    let headings = root.children.compactMap { $0 as? Heading }

    // Target the first heading (H1, index 0)
    let scope = HeadingScope.identify(headings: headings, targetIndex: 0)

    #expect(scope.targetIndex == 0)
    #expect(scope.targetDepth == 1)
    #expect(scope.childIndices == [1, 2, 3])  // All deeper headings until we hit H2
  }

  @Test
  func `Identify scope for middle section`() async throws {
    let content = """
      # First H1
      ## First H2
      # Second H1
      ## Second H2
      ### Second H3
      # Third H1
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()
    let headings = root.children.compactMap { $0 as? Heading }

    // Target the second H1 (index 2)
    let scope = HeadingScope.identify(headings: headings, targetIndex: 2)

    #expect(scope.targetIndex == 2)
    #expect(scope.targetDepth == 1)
    #expect(scope.childIndices == [3, 4])  // Only the H2 and H3 under "Second H1"
  }

  @Test
  func `Identify scope with same-level siblings`() async throws {
    let content = """
      ## H2
      ### H3
      ## H2
      ### H3
      """

    let markdown = try await Markdown(text: content)
    let root = await markdown.parse()
    let headings = root.children.compactMap { $0 as? Heading }

    // Target the first H2 (index 0)
    let scope = HeadingScope.identify(headings: headings, targetIndex: 0)

    #expect(scope.targetIndex == 0)
    #expect(scope.targetDepth == 2)
    #expect(scope.childIndices == [1])  // Only first H3, stops at second H2
  }
}
