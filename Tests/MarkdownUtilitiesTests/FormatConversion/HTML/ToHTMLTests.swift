//
//  ToHTMLTests.swift
//  MarkdownUtilitiesTests
//

import Foundation
import MarkdownUtilities
import Testing

@Suite("MarkdownDocument.toHTML Tests")
struct ToHTMLTests {

    // MARK: - Basic CommonMark Elements

    @Test
    func `heading renders as h tag`() async throws {
        let doc = try MarkdownDocument(content: "# Hello World")
        let html = try await doc.toHTML()

        #expect(html.contains("<h1>Hello World</h1>"))
    }

    @Test
    func `paragraph renders as p tag`() async throws {
        let doc = try MarkdownDocument(content: "Simple paragraph.")
        let html = try await doc.toHTML()

        #expect(html.contains("<p>Simple paragraph.</p>"))
    }

    @Test
    func `bold renders as strong tag`() async throws {
        let doc = try MarkdownDocument(content: "**bold text**")
        let html = try await doc.toHTML()

        #expect(html.contains("<strong>bold text</strong>"))
    }

    @Test
    func `unordered list renders as ul and li tags`() async throws {
        let markdown = "- First\n- Second\n- Third"
        let doc = try MarkdownDocument(content: markdown)
        let html = try await doc.toHTML()

        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>First</li>"))
        #expect(html.contains("<li>Second</li>"))
    }

    @Test
    func `fenced code block renders as pre and code tags`() async throws {
        let markdown = "```swift\nlet x = 1\n```"
        let doc = try MarkdownDocument(content: markdown)
        let html = try await doc.toHTML()

        #expect(html.contains("<pre>") || html.contains("<pre "))
        #expect(html.contains("<code"))
        #expect(html.contains("let x = 1"))
    }

    // MARK: - GFM Tables

    @Test
    func `GFM table renders as table tag by default`() async throws {
        let markdown = """
            | Name  | Age |
            |-------|-----|
            | Alice | 30  |
            | Bob   | 25  |
            """
        let doc = try MarkdownDocument(content: markdown)
        let html = try await doc.toHTML()

        #expect(html.contains("<table>"))
        #expect(html.contains("<th>"))
        #expect(html.contains("Alice"))
        #expect(html.contains("Bob"))
    }

    @Test
    func `GFM table disabled with no tables option`() async throws {
        let markdown = """
            | Name  | Age |
            |-------|-----|
            | Alice | 30  |
            """
        let doc = try MarkdownDocument(content: markdown)
        var ext = MarkdownExtensionOptions.all
        ext.remove(.tables)
        let options = HTMLOptions(extensions: ext)
        let html = try await doc.toHTML(options: options)

        #expect(!html.contains("<table>"))
    }

    // MARK: - GFM Strikethrough

    @Test
    func `strikethrough renders as del tag`() async throws {
        let markdown = "~~deleted text~~"
        let doc = try MarkdownDocument(content: markdown)
        let html = try await doc.toHTML()

        #expect(html.contains("<del>deleted text</del>"))
    }

    @Test
    func `strikethrough disabled without extension`() async throws {
        let markdown = "~~deleted text~~"
        let doc = try MarkdownDocument(content: markdown)
        var ext = MarkdownExtensionOptions.all
        ext.remove(.strikethrough)
        let options = HTMLOptions(extensions: ext)
        let html = try await doc.toHTML(options: options)

        #expect(!html.contains("<del>"))
        #expect(html.contains("~~"))
    }

    // MARK: - GFM Task Lists

    @Test
    func `task list item renders with checkbox input`() async throws {
        let markdown = "- [x] Done\n- [ ] Todo"
        let doc = try MarkdownDocument(content: markdown)
        let html = try await doc.toHTML()

        #expect(html.contains("<input"))
        #expect(html.contains("type=\"checkbox\""))
        #expect(html.contains("checked"))
    }

    // MARK: - Document Wrapping

    @Test
    func `wrapInDocument produces doctype skeleton`() async throws {
        let doc = try MarkdownDocument(content: "# Hello")
        let options = HTMLOptions(wrapInDocument: true)
        let html = try await doc.toHTML(options: options)

        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<html>"))
        #expect(html.contains("<head>"))
        #expect(html.contains("<body>"))
        #expect(html.contains("</html>"))
    }

    @Test
    func `default options do not wrap in document`() async throws {
        let doc = try MarkdownDocument(content: "# Hello")
        let html = try await doc.toHTML()

        #expect(!html.contains("<!DOCTYPE html>"))
        #expect(!html.contains("<html>"))
    }

    // MARK: - Frontmatter

    @Test
    func `includeFrontmatter prepends YAML as HTML comment`() async throws {
        let markdown = """
            ---
            title: My Page
            author: Alice
            ---

            # Body
            """
        let doc = try MarkdownDocument(content: markdown)
        let options = HTMLOptions(includeFrontmatter: true)
        let html = try await doc.toHTML(options: options)

        #expect(html.contains("<!--"))
        #expect(html.contains("title: My Page"))
        #expect(html.contains("author: Alice"))
        #expect(html.contains("-->"))
        #expect(html.contains("<h1>Body</h1>"))
    }

    @Test
    func `frontmatter excluded by default`() async throws {
        let markdown = """
            ---
            title: My Page
            ---

            # Body
            """
        let doc = try MarkdownDocument(content: markdown)
        let html = try await doc.toHTML()

        #expect(!html.contains("title: My Page"))
        #expect(html.contains("<h1>Body</h1>"))
    }

    @Test
    func `includeFrontmatter with empty frontmatter omits comment`() async throws {
        let doc = try MarkdownDocument(content: "# No frontmatter")
        let options = HTMLOptions(includeFrontmatter: true)
        let html = try await doc.toHTML(options: options)

        #expect(!html.contains("<!--"))
    }

    // MARK: - Hard Breaks

    @Test
    func `hardBreaks converts soft breaks to br tags`() async throws {
        let markdown = "Line one\nLine two"
        let doc = try MarkdownDocument(content: markdown)
        let options = HTMLOptions(hardBreaks: true)
        let html = try await doc.toHTML(options: options)

        #expect(html.contains("<br"))
    }

    @Test
    func `default soft breaks do not produce br tags`() async throws {
        let markdown = "Line one\nLine two"
        let doc = try MarkdownDocument(content: markdown)
        let html = try await doc.toHTML()

        #expect(!html.contains("<br"))
    }

    // MARK: - CommonMark-only mode

    @Test
    func `extensions none disables all GFM features`() async throws {
        let markdown = """
            | A | B |
            |---|---|
            | 1 | 2 |

            ~~strike~~
            """
        let doc = try MarkdownDocument(content: markdown)
        let options = HTMLOptions(extensions: .none)
        let html = try await doc.toHTML(options: options)

        #expect(!html.contains("<table>"))
        #expect(!html.contains("<del>"))
    }
}
