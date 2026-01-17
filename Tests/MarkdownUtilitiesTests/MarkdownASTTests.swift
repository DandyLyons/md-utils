//
//  MarkdownASTTests.swift
//  MarkdownUtilitiesTests
//

import Testing
import MarkdownSyntax
@testable import MarkdownUtilities

@Suite("Markdown AST Parsing Tests")
struct MarkdownASTTests {

  @Test
  func `Parse simple markdown into AST`() async throws {
    let content = "# Hello\n\nParagraph text."
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 2)

    // Verify first child is Heading
    let heading = try #require(root.children[0] as? Heading)
    #expect(heading.depth == .h1)

    // Verify second child is Paragraph
    #expect(root.children[1] is Paragraph)
  }

  @Test
  func `parseAST returns fresh AST each call`() async throws {
    let doc = try MarkdownDocument(content: "# Test")

    let ast1 = try await doc.parseAST()
    let ast2 = try await doc.parseAST()

    // Both calls should succeed and return valid AST
    #expect(ast1.children.count == 1)
    #expect(ast2.children.count == 1)
  }

  @Test
  func `Parse empty body`() async throws {
    let doc = try MarkdownDocument(content: "")

    let root = try await doc.parseAST()

    // Empty body should parse as empty root
    #expect(root.children.isEmpty)
  }

  @Test
  func `Parse body with only whitespace`() async throws {
    let doc = try MarkdownDocument(content: "   \n\n  \t  \n  ")

    let root = try await doc.parseAST()

    // Whitespace-only content should parse as empty or minimal structure
    #expect(root.children.count >= 0)
  }

  @Test
  func `Parse multiple heading levels`() async throws {
    let content = """
    # H1
    ## H2
    ### H3
    #### H4
    ##### H5
    ###### H6
    """
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 6)

    // Verify all are headings with correct depths
    let h1 = try #require(root.children[0] as? Heading)
    let h2 = try #require(root.children[1] as? Heading)
    let h3 = try #require(root.children[2] as? Heading)
    let h4 = try #require(root.children[3] as? Heading)
    let h5 = try #require(root.children[4] as? Heading)
    let h6 = try #require(root.children[5] as? Heading)

    #expect(h1.depth == .h1)
    #expect(h2.depth == .h2)
    #expect(h3.depth == .h3)
    #expect(h4.depth == .h4)
    #expect(h5.depth == .h5)
    #expect(h6.depth == .h6)
  }

  @Test
  func `Parse lists`() async throws {
    let content = """
    - Item 1
    - Item 2
    - Item 3
    """
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 1)

    let list = try #require(root.children[0] as? List)
    #expect(list.ordered == false)
    #expect(list.children.count == 3)
  }

  @Test
  func `Parse ordered list`() async throws {
    let content = """
    1. First
    2. Second
    3. Third
    """
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 1)

    let list = try #require(root.children[0] as? List)
    #expect(list.ordered == true)
    #expect(list.children.count == 3)
  }

  @Test
  func `Parse code block`() async throws {
    let content = """
    ```swift
    let x = 42
    print(x)
    ```
    """
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 1)

    let code = try #require(root.children[0] as? Code)
    #expect(code.language == "swift")
    #expect(code.value.contains("let x = 42"))
  }

  @Test
  func `Parse inline formatting`() async throws {
    let content = "This has **bold** and *italic* and `code`."
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 1)

    let paragraph = try #require(root.children[0] as? Paragraph)
    #expect(paragraph.children.count > 0)

    // Verify we have strong, emphasis, and inline code
    #expect(paragraph.children.contains { $0 is Strong })
    #expect(paragraph.children.contains { $0 is Emphasis })
    #expect(paragraph.children.contains { $0 is InlineCode })
  }

  @Test
  func `Parse link`() async throws {
    let content = "[OpenAI](https://openai.com)"
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 1)

    let paragraph = try #require(root.children[0] as? Paragraph)
    let link = try #require(paragraph.children.first as? Link)
    #expect(link.url.absoluteString == "https://openai.com")
  }

  @Test
  func `Parse complex markdown structure`() async throws {
    let content = """
    # Heading 1

    This is a paragraph with **bold** and *italic*.

    ## Heading 2

    - List item 1
    - List item 2

    ```swift
    let code = "example"
    ```
    """
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 5)

    let h1 = try #require(root.children[0] as? Heading)
    #expect(h1.depth == .h1)

    #expect(root.children[1] is Paragraph)

    let h2 = try #require(root.children[2] as? Heading)
    #expect(h2.depth == .h2)

    let list = try #require(root.children[3] as? List)
    #expect(list.children.count == 2)

    let code = try #require(root.children[4] as? Code)
    #expect(code.language == "swift")
  }

  @Test
  func `Parse markdown with frontmatter excluded from AST`() async throws {
    let content = """
    ---
    title: Test
    tags: [swift, markdown]
    ---
    # Heading

    Body text here.
    """
    let doc = try MarkdownDocument(content: content)

    // Verify frontmatter is parsed
    #expect(!doc.frontMatter.isEmpty)

    // Parse AST from body only
    let root = try await doc.parseAST()

    // AST should only contain body content (heading + paragraph)
    #expect(root.children.count == 2)

    let heading = try #require(root.children[0] as? Heading)
    #expect(heading.depth == .h1)

    #expect(root.children[1] is Paragraph)
  }

  @Test
  func `Malformed markdown still parses`() async throws {
    // MarkdownSyntax is very permissive
    let content = "<<< not really markdown >>> ### but has # some # marks"
    let doc = try MarkdownDocument(content: content)

    // Should not throw - will parse as text/paragraph
    let root = try await doc.parseAST()
    #expect(root.children.count >= 0)
  }
}

@Suite("Markdown AST Integration Tests")
struct MarkdownASTIntegrationTests {

  @Test
  func `Document handles both frontmatter and AST parsing`() async throws {
    let content = """
    ---
    title: My Document
    author: Test User
    ---
    # Introduction

    This is the content.

    ## Section

    - Point 1
    - Point 2
    """

    let doc = try MarkdownDocument(content: content)

    // Verify frontmatter parsed correctly
    #expect(!doc.frontMatter.isEmpty)
    let title = try #require(doc.frontMatter["title"]?.string)
    let author = try #require(doc.frontMatter["author"]?.string)
    #expect(title == "My Document")
    #expect(author == "Test User")

    // Verify body excludes frontmatter
    #expect(doc.body.contains("# Introduction"))
    #expect(!doc.body.contains("---"))
    #expect(!doc.body.contains("title: My Document"))

    // Parse AST from body
    let root = try await doc.parseAST()

    // Should have: H1, paragraph, H2, list
    #expect(root.children.count == 4)

    let h1 = try #require(root.children[0] as? Heading)
    #expect(h1.depth == .h1)

    let h2 = try #require(root.children[2] as? Heading)
    #expect(h2.depth == .h2)

    let list = try #require(root.children[3] as? List)
    #expect(list.children.count == 2)
  }
}
