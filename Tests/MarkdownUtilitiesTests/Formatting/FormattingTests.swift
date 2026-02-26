import Testing
import MarkdownSyntax
import Yams
@testable import MarkdownUtilities

// MARK: - BulletNormalizer Tests

@Suite("BulletNormalizer Tests")
struct BulletNormalizerTests {

    private func root(for content: String) async throws -> Root {
        let markdown = try await Markdown(text: content)
        return await markdown.parse()
    }

    @Test("Converts * markers to -")
    func convertAsterisksToDashes() async throws {
        let content = """
            * item one
            * item two
            * item three
            """
        let root = try await root(for: content)
        let result = BulletNormalizer.normalize(content, root: root, to: .dash)
        let expected = """
            - item one
            - item two
            - item three
            """
        #expect(result == expected)
    }

    @Test("Converts - markers to *")
    func convertDashesToAsterisks() async throws {
        let content = """
            - item one
            - item two
            """
        let root = try await root(for: content)
        let result = BulletNormalizer.normalize(content, root: root, to: .asterisk)
        let expected = """
            * item one
            * item two
            """
        #expect(result == expected)
    }

    @Test("Leaves already-correct markers unchanged (idempotent)")
    func idempotentDashes() async throws {
        let content = """
            - item one
            - item two
            """
        let root = try await root(for: content)
        let result = BulletNormalizer.normalize(content, root: root, to: .dash)
        #expect(result == content)
    }

    @Test("Converts + markers to target")
    func convertPlusMarkers() async throws {
        let content = """
            + item one
            + item two
            """
        let root = try await root(for: content)
        let result = BulletNormalizer.normalize(content, root: root, to: .dash)
        let expected = """
            - item one
            - item two
            """
        #expect(result == expected)
    }

    @Test("Handles nested lists")
    func nestedLists() async throws {
        let content = """
            * parent one
              * child one
              * child two
            * parent two
            """
        let root = try await root(for: content)
        let result = BulletNormalizer.normalize(content, root: root, to: .dash)
        let expected = """
            - parent one
              - child one
              - child two
            - parent two
            """
        #expect(result == expected)
    }

    @Test("Does not modify ordered list items")
    func orderedListPreserved() async throws {
        let content = """
            1. first
            2. second
            3. third
            """
        let root = try await root(for: content)
        let result = BulletNormalizer.normalize(content, root: root, to: .dash)
        #expect(result == content)
    }

    @Test("Does not modify content inside fenced code blocks")
    func fencedCodeBlockPreserved() async throws {
        let content = """
            ```
            * not a list item
            - also not a list item
            ```
            """
        let root = try await root(for: content)
        let result = BulletNormalizer.normalize(content, root: root, to: .dash)
        #expect(result == content)
    }

    @Test("Mixed ordered and unordered lists")
    func mixedLists() async throws {
        let content = """
            1. ordered
            2. ordered

            * unordered one
            * unordered two
            """
        let root = try await root(for: content)
        let result = BulletNormalizer.normalize(content, root: root, to: .dash)
        let expected = """
            1. ordered
            2. ordered

            - unordered one
            - unordered two
            """
        #expect(result == expected)
    }
}

// MARK: - ItalicNormalizer Tests

@Suite("ItalicNormalizer Tests")
struct ItalicNormalizerTests {

    private func root(for content: String) async throws -> Root {
        let markdown = try await Markdown(text: content)
        return await markdown.parse()
    }

    @Test("Converts *text* to _text_")
    func convertAsterisksToUnderscores() async throws {
        let content = "Hello *world* and *swift*"
        let root = try await root(for: content)
        let result = ItalicNormalizer.normalize(content, root: root, to: .underscore)
        #expect(result == "Hello _world_ and _swift_")
    }

    @Test("Converts _text_ to *text*")
    func convertUnderscoresToAsterisks() async throws {
        let content = "Hello _world_ there"
        let root = try await root(for: content)
        let result = ItalicNormalizer.normalize(content, root: root, to: .asterisk)
        #expect(result == "Hello *world* there")
    }

    @Test("Does not modify **bold**")
    func boldPreservedAsterisks() async throws {
        let content = "**bold text**"
        let root = try await root(for: content)
        let result = ItalicNormalizer.normalize(content, root: root, to: .underscore)
        #expect(result == content)
    }

    @Test("Does not modify __bold__")
    func boldPreservedUnderscores() async throws {
        let content = "__bold text__"
        let root = try await root(for: content)
        let result = ItalicNormalizer.normalize(content, root: root, to: .asterisk)
        #expect(result == content)
    }

    @Test("Does not modify inline code containing markers")
    func inlineCodePreserved() async throws {
        let content = "Use `*text*` for emphasis"
        let root = try await root(for: content)
        let result = ItalicNormalizer.normalize(content, root: root, to: .underscore)
        #expect(result == content)
    }

    @Test("Handles multiple emphasis nodes in one paragraph")
    func multipleEmphasisNodes() async throws {
        let content = "One *alpha* and *beta* and *gamma*"
        let root = try await root(for: content)
        let result = ItalicNormalizer.normalize(content, root: root, to: .underscore)
        #expect(result == "One _alpha_ and _beta_ and _gamma_")
    }

    @Test("Idempotent when markers already match")
    func idempotent() async throws {
        let content = "_already correct_"
        let root = try await root(for: content)
        let result = ItalicNormalizer.normalize(content, root: root, to: .underscore)
        #expect(result == content)
    }

    @Test("Handles emphasis in heading")
    func emphasisInHeading() async throws {
        let content = "# A *title* heading"
        let root = try await root(for: content)
        let result = ItalicNormalizer.normalize(content, root: root, to: .underscore)
        #expect(result == "# A _title_ heading")
    }
}

// MARK: - TableNormalizer Tests

@Suite("TableNormalizer Tests")
struct TableNormalizerTests {

    @Test("Pads cells to align columns")
    func basicTablePadding() {
        let input = """
            | Name | Age |
            | --- | --- |
            | Alice | 30 |
            | Bob | 25 |
            """
        let result = TableNormalizer.normalize(input)
        // Each row should have padded cells
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 4)
        // All rows should have the same width
        let widths = lines.map { $0.count }
        #expect(widths[0] == widths[1])
        #expect(widths[0] == widths[2])
        #expect(widths[0] == widths[3])
    }

    @Test("Preserves separator row dashes")
    func separatorRowPreserved() {
        let input = """
            | Name | Value |
            | ---- | ----- |
            | foo  | bar   |
            """
        let result = TableNormalizer.normalize(input)
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 3)
        // Separator row (index 1) should contain only dashes and pipes
        let sep = lines[1]
        let sepChars = sep.filter { !$0.isWhitespace && $0 != "|" }
        #expect(sepChars.allSatisfy { $0 == "-" })
    }

    @Test("Handles tables with alignment colons")
    func alignmentColons() {
        let input = """
            | Left | Center | Right |
            | :--- | :---: | ---: |
            | a | b | c |
            """
        let result = TableNormalizer.normalize(input)
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 3)
        // Separator row should preserve alignment colons
        let sep = lines[1]
        #expect(sep.contains(":"))
    }

    @Test("Leaves content without tables unchanged")
    func noTableUnchanged() {
        let input = """
            # Heading

            A paragraph with no table.
            """
        let result = TableNormalizer.normalize(input)
        #expect(result == input)
    }

    @Test("Normalizes tables inside fenced code blocks")
    func normalizesTablesInFencedCodeBlocks() {
        let input = """
            ```
            | not | a | table |
            | --- | - | ----- |
            ```
            """
        let result = TableNormalizer.normalize(input)
        let lines = result.components(separatedBy: "\n")
        // Fence markers are preserved
        #expect(lines[0] == "```")
        #expect(lines[3] == "```")
        // Table inside is normalized: all content rows have the same width
        #expect(lines[1].count == lines[2].count)
        // Separator contains only dashes and pipes
        let sepChars = lines[2].filter { !$0.isWhitespace && $0 != "|" }
        #expect(sepChars.allSatisfy { $0 == "-" })
    }

    @Test("Caps column padding at maxWidth")
    func maxWidthCapsColumnPadding() {
        // Column 2 has max content width of 5 ("hello"), but maxWidth = 3
        // So column 2 width = min(5, 3) = 3
        // "hello" (5 chars) > 3 → padded to max(3, 5) = 5, no truncation
        // "hi" (2 chars) < 3 → padded to max(3, 2) = 3
        let input = """
            | a | hello |
            | - | ----- |
            | b | hi |
            """
        let result = TableNormalizer.normalize(input, maxWidth: 3)
        let lines = result.components(separatedBy: "\n")
        #expect(lines[0].contains("hello"))   // content preserved, not truncated
        #expect(lines[2].contains("| hi  |")) // "hi" padded to 3 chars
    }

    @Test("Does not truncate cell content exceeding maxWidth")
    func cellContentNotTruncatedBeyondMaxWidth() {
        let longCell = String(repeating: "x", count: 100)
        let input = "| \(longCell) |\n| --- |\n| short |"
        let result = TableNormalizer.normalize(input, maxWidth: 10)
        #expect(result.contains(longCell))
    }

    @Test("Default maxWidth matches explicit maxWidth of 80")
    func defaultMaxWidthIs80() {
        let input = """
            | Name | Score |
            | ---- | ----- |
            | Alice | 100 |
            """
        let defaultResult = TableNormalizer.normalize(input)
        let explicitResult = TableNormalizer.normalize(input, maxWidth: 80)
        #expect(defaultResult == explicitResult)
    }

    @Test("Output is idempotent (second pass does not change result)")
    func idempotent() {
        let input = """
            | Name | Score |
            | ---- | ----- |
            | Alice | 100 |
            | Bob | 99 |
            """
        let first = TableNormalizer.normalize(input)
        let second = TableNormalizer.normalize(first)
        #expect(first == second)
    }
}

// MARK: - MarkdownDocument+Formatting Integration Tests

@Suite("MarkdownDocument Formatting Integration Tests")
struct MarkdownDocumentFormattingTests {

    @Test("Applies bullet normalization")
    func bulletNormalization() async throws {
        let doc = try MarkdownDocument(content: """
            * item one
            * item two
            """)
        let options = FormattingOptions(bulletMarker: .dash)
        let result = try await doc.format(options: options)
        #expect(result.body.contains("- item one"))
        #expect(result.body.contains("- item two"))
        #expect(!result.body.contains("* item"))
    }

    @Test("Applies italic normalization")
    func italicNormalization() async throws {
        let doc = try MarkdownDocument(content: "Hello *world*")
        let options = FormattingOptions(italicMarker: .underscore)
        let result = try await doc.format(options: options)
        #expect(result.body == "Hello _world_")
    }

    @Test("Applies table normalization")
    func tableNormalization() async throws {
        let doc = try MarkdownDocument(content: """
            | Name | Age |
            | --- | --- |
            | Alice | 30 |
            """)
        let options = FormattingOptions(normalizeTables: true)
        let result = try await doc.format(options: options)
        let lines = result.body.components(separatedBy: "\n")
        // All rows should be the same width
        let widths = lines.map { $0.count }
        #expect(widths[0] == widths[1])
        #expect(widths[0] == widths[2])
    }

    @Test("Applies multiple options in one call")
    func multipleOptions() async throws {
        let doc = try MarkdownDocument(content: """
            * _italic item_
            * another item
            """)
        let options = FormattingOptions(bulletMarker: .dash, italicMarker: .asterisk)
        let result = try await doc.format(options: options)
        #expect(result.body.contains("- *italic item*"))
        #expect(result.body.contains("- another item"))
    }

    @Test("Preserves YAML frontmatter")
    func frontmatterPreserved() async throws {
        let content = """
            ---
            title: Test
            ---
            * item one
            * item two
            """
        let doc = try MarkdownDocument(content: content)
        let options = FormattingOptions(bulletMarker: .dash)
        let result = try await doc.format(options: options)
        #expect(!result.frontMatter.isEmpty)
        // Frontmatter title preserved
        let titleKey = Yams.Node(stringLiteral: "title")
        #expect(result.frontMatter[titleKey] != nil)
        #expect(result.body.contains("- item one"))
    }

    @Test("No-op when all options are nil/false")
    func noOpOptions() async throws {
        let original = "* item one\n* item two"
        let doc = try MarkdownDocument(content: original)
        let options = FormattingOptions()
        let result = try await doc.format(options: options)
        #expect(result.body == doc.body)
    }
}
