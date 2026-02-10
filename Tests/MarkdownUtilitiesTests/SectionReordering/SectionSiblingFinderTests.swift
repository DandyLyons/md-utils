import Testing
@testable import MarkdownUtilities
import MarkdownSyntax

@Suite("SectionSiblingFinder Tests")
struct SectionSiblingFinderTests {

  @Test
  func `Top-level H1 siblings`() async throws {
    let content = """
      # First
      Content 1.
      # Second
      Content 2.
      # Third
      Content 3.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let info = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 1)

    #expect(info.targetIndex == 1)
    #expect(info.siblingIndices == [0, 1, 2])
    #expect(info.positionAmongSiblings == 1)
    #expect(info.canMoveUp == true)
    #expect(info.canMoveDown == true)
    #expect(info.previousSiblingIndex == 0)
    #expect(info.nextSiblingIndex == 2)
  }

  @Test
  func `Nested H2 siblings under same parent`() async throws {
    let content = """
      # Parent
      ## Child A
      Content A.
      ## Child B
      Content B.
      ## Child C
      Content C.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let info = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 1)

    #expect(info.siblingIndices == [1, 2, 3])
    #expect(info.positionAmongSiblings == 0)
    #expect(info.canMoveUp == false)
    #expect(info.canMoveDown == true)
  }

  @Test
  func `Single heading has no siblings`() async throws {
    let content = """
      # Only Heading
      Some content.
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let info = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 0)

    #expect(info.siblingIndices == [0])
    #expect(info.positionAmongSiblings == 0)
    #expect(info.canMoveUp == false)
    #expect(info.canMoveDown == false)
    #expect(info.previousSiblingIndex == nil)
    #expect(info.nextSiblingIndex == nil)
  }

  @Test
  func `First sibling cannot move up`() async throws {
    let content = """
      # First
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let info = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 0)

    #expect(info.canMoveUp == false)
    #expect(info.canMoveDown == true)
  }

  @Test
  func `Last sibling cannot move down`() async throws {
    let content = """
      # First
      # Second
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let info = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 1)

    #expect(info.canMoveUp == true)
    #expect(info.canMoveDown == false)
  }

  @Test
  func `H2 siblings are scoped to their H1 parent`() async throws {
    let content = """
      # Parent A
      ## Sub A1
      ## Sub A2
      # Parent B
      ## Sub B1
      ## Sub B2
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    // Sub A1 should only see Sub A2 as sibling, not Sub B1/B2
    let infoA = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 1)
    #expect(infoA.siblingIndices == [1, 2])

    // Sub B1 should only see Sub B2 as sibling, not Sub A1/A2
    let infoB = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 4)
    #expect(infoB.siblingIndices == [4, 5])
  }

  @Test
  func `Deep nesting with H3 siblings`() async throws {
    let content = """
      # Main
      ## Section
      ### Sub A
      ### Sub B
      ### Sub C
      ## Another Section
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let info = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 3)

    #expect(info.siblingIndices == [2, 3, 4])
    #expect(info.positionAmongSiblings == 1)
  }

  @Test
  func `H1 siblings with nested children`() async throws {
    let content = """
      # First
      ## Sub 1.1
      ### Sub 1.1.1
      # Second
      ## Sub 2.1
      # Third
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let info = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 3)

    #expect(info.siblingIndices == [0, 3, 5])
    #expect(info.positionAmongSiblings == 1)
  }

  @Test
  func `Single H2 under a parent has no siblings`() async throws {
    let content = """
      # Parent
      ## Only Child
      Content.
      # Another Parent
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    let info = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 1)

    #expect(info.siblingIndices == [1])
    #expect(info.canMoveUp == false)
    #expect(info.canMoveDown == false)
  }

  @Test
  func `Non-adjacent siblings with children between them`() async throws {
    let content = """
      # A
      ## A child
      # B
      ## B child 1
      ## B child 2
      # C
      """

    let doc = try MarkdownDocument(content: content)
    let root = try await doc.parseAST()
    let headings = root.children.compactMap { $0 as? Heading }

    // H1 siblings: A(0), B(2), C(5)
    let info = SectionSiblingFinder.findSiblings(headings: headings, targetIndex: 2)

    #expect(info.siblingIndices == [0, 2, 5])
    #expect(info.positionAmongSiblings == 1)
    #expect(info.previousSiblingIndex == 0)
    #expect(info.nextSiblingIndex == 5)
  }
}
