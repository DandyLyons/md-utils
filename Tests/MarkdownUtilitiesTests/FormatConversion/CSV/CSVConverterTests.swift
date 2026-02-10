//
//  CSVConverterTests.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownUtilities
import Testing

@Suite("CSVConverter Tests")
struct CSVConverterTests {

    // MARK: - Basic Conversion

    @Test
    func `Convert single document to CSV`() throws {
        let markdown = """
            ---
            title: Test Document
            author: Alice
            ---
            Body content here.
            """
        let doc = try MarkdownDocument(content: markdown)
        let converter = CSVConverter()
        let options = CSVOptions()

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)

        // Should have header row with frontmatter columns
        #expect(csv.contains("author"))
        #expect(csv.contains("title"))
        #expect(csv.contains("$body"))

        // Should contain the data
        #expect(csv.contains("Alice"))
        #expect(csv.contains("Test Document"))
        #expect(csv.contains("Body content here."))
    }

    @Test
    func `Convert multiple documents to CSV`() throws {
        let doc1 = try MarkdownDocument(content: """
            ---
            title: Doc 1
            author: Alice
            ---
            Content 1
            """)

        let doc2 = try MarkdownDocument(content: """
            ---
            title: Doc 2
            author: Bob
            ---
            Content 2
            """)

        let converter = CSVConverter()
        let options = CSVOptions()

        let csv = try converter.convert(
            documents: [("doc1.md", doc1), ("doc2.md", doc2)],
            options: options
        )

        // Should contain data from both documents
        #expect(csv.contains("Doc 1"))
        #expect(csv.contains("Doc 2"))
        #expect(csv.contains("Alice"))
        #expect(csv.contains("Bob"))
    }

    @Test
    func `Handle empty documents array`() throws {
        let converter = CSVConverter()
        let options = CSVOptions()

        let csv = try converter.convert(documents: [], options: options)

        // Should return just the header (with body column only if includeBody is true)
        #expect(!csv.isEmpty)
    }

    // MARK: - Column Ordering

    @Test
    func `Frontmatter columns are alphabetically sorted`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            zebra: z
            apple: a
            banana: b
            ---
            Content
            """)

        let converter = CSVConverter()
        let options = CSVOptions()

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)
        let header = csv.split(separator: "\n")[0]

        // Header should have columns in order: $body, apple, banana, zebra
        let headerStr = String(header)
        let applePos = headerStr.range(of: "apple")
        let bananaPos = headerStr.range(of: "banana")
        let zebraPos = headerStr.range(of: "zebra")

        #expect(applePos != nil)
        #expect(bananaPos != nil)
        #expect(zebraPos != nil)

        // Verify alphabetical order
        if let a = applePos, let b = bananaPos, let z = zebraPos {
            #expect(a.lowerBound < b.lowerBound)
            #expect(b.lowerBound < z.lowerBound)
        }
    }

    @Test
    func `Metadata columns appear first`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            title: Test
            ---
            Content
            """)

        let converter = CSVConverter()
        let options = CSVOptions(
            includeBody: true,
            metadataColumns: [.fileName, .absPath]
        )

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)
        let header = csv.split(separator: "\n")[0]
        let headerStr = String(header)

        // Metadata columns should appear before body and frontmatter
        let fileNamePos = headerStr.range(of: "$fileName")
        let absPathPos = headerStr.range(of: "$absPath")
        let bodyPos = headerStr.range(of: "$body")
        let titlePos = headerStr.range(of: "title")

        #expect(fileNamePos != nil)
        #expect(absPathPos != nil)
        #expect(bodyPos != nil)
        #expect(titlePos != nil)

        if let fn = fileNamePos, let ap = absPathPos, let b = bodyPos, let t = titlePos {
            // Metadata should come before body and title
            #expect(fn.lowerBound < b.lowerBound)
            #expect(ap.lowerBound < b.lowerBound)
            #expect(b.lowerBound < t.lowerBound)
        }
    }

    @Test
    func `Body column appears after metadata and before frontmatter`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            author: Alice
            ---
            Body text
            """)

        let converter = CSVConverter()
        let options = CSVOptions(
            includeBody: true,
            metadataColumns: [.fileName]
        )

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)
        let header = csv.split(separator: "\n")[0]
        let headerStr = String(header)

        // Order should be: $fileName, $body, author
        let parts = headerStr.split(separator: ",")
        #expect(parts.count == 3)
        #expect(parts[0] == "$fileName")
        #expect(parts[1] == "$body")
        #expect(parts[2] == "author")
    }

    // MARK: - Metadata Columns

    @Test
    func `Include fileName metadata column`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            title: Test
            ---
            Content
            """)

        let converter = CSVConverter()
        let options = CSVOptions(metadataColumns: [.fileName])

        let csv = try converter.convert(documents: [("docs/test.md", doc)], options: options)
        let lines = csv.split(separator: "\n")
        let dataRow = String(lines[1])

        // Should have "test.md" as the fileName value
        #expect(dataRow.contains("test.md"))
    }

    @Test
    func `Include absPath metadata column`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            title: Test
            ---
            Content
            """)

        let converter = CSVConverter()
        let options = CSVOptions(metadataColumns: [.absPath])

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)
        let header = csv.split(separator: "\n")[0]

        #expect(String(header).contains("$absPath"))
    }

    @Test
    func `Include relPath metadata column with base directory`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            title: Test
            ---
            Content
            """)

        let converter = CSVConverter()
        let options = CSVOptions(
            metadataColumns: [.relPath],
            baseDirectory: "/base"
        )

        // Path should be relative to base
        let csv = try converter.convert(documents: [("/base/docs/test.md", doc)], options: options)
        let lines = csv.split(separator: "\n")
        let dataRow = String(lines[1])

        #expect(dataRow.contains("docs/test.md"))
    }

    // MARK: - Body Inclusion

    @Test
    func `Include body when includeBody is true`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            title: Test
            ---
            Body content here.
            """)

        let converter = CSVConverter()
        let options = CSVOptions(includeBody: true)

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)

        // Header should contain $body
        #expect(csv.contains("$body"))

        // Data row should contain body content
        #expect(csv.contains("Body content here."))
    }

    @Test
    func `Exclude body when includeBody is false`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            title: Test
            ---
            Body content here.
            """)

        let converter = CSVConverter()
        let options = CSVOptions(includeBody: false)

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)

        // Header should not contain $body
        #expect(!csv.contains("$body"))

        // Data row should not contain body content
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(!String(lines[1]).contains("Body content here."))
    }

    // MARK: - CSV Escaping

    @Test
    func `Escape fields with commas`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            title: Test, Document
            ---
            Content
            """)

        let converter = CSVConverter()
        let options = CSVOptions()

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)

        // Field with comma should be quoted
        #expect(csv.contains("\"Test, Document\""))
    }

    @Test
    func `Escape fields with quotes`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            title: Test "Quote" Document
            ---
            Content
            """)

        let converter = CSVConverter()
        let options = CSVOptions()

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)

        // Field with quotes should be quoted and quotes doubled
        #expect(csv.contains("\"Test \"\"Quote\"\" Document\""))
    }

    @Test
    func `Escape fields with newlines`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            title: Test
            ---
            Body with
            newline
            """)

        let converter = CSVConverter()
        let options = CSVOptions(includeBody: true)

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        // Body field with newlines should be quoted
        // The CSV should still have only 2 logical rows (header + data)
        #expect(csv.contains("\"Body with"))
    }

    // MARK: - Nested YAML

    @Test
    func `Convert nested arrays to JSON`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            tags:
              - javascript
              - typescript
            ---
            Content
            """)

        let converter = CSVConverter()
        let options = CSVOptions()

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)

        // Array should be serialized as JSON (with or without spaces after commas)
        #expect(csv.contains("javascript"))
        #expect(csv.contains("typescript"))
        #expect(csv.contains("tags"))
        // Check for JSON array brackets
        #expect(csv.contains("[") && csv.contains("]"))
    }

    @Test
    func `Convert nested objects to JSON`() throws {
        let doc = try MarkdownDocument(content: """
            ---
            author:
              name: Alice
              email: alice@example.com
            ---
            Content
            """)

        let converter = CSVConverter()
        let options = CSVOptions()

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)

        // Object should be serialized as JSON
        #expect(csv.contains("\"name\"") && csv.contains("\"Alice\""))
        #expect(csv.contains("\"email\"") && csv.contains("\"alice@example.com\""))
    }

    // MARK: - Missing Keys

    @Test
    func `Handle missing frontmatter keys with empty cells`() throws {
        let doc1 = try MarkdownDocument(content: """
            ---
            title: Doc 1
            author: Alice
            ---
            Content 1
            """)

        let doc2 = try MarkdownDocument(content: """
            ---
            title: Doc 2
            ---
            Content 2
            """)

        let converter = CSVConverter()
        let options = CSVOptions()

        let csv = try converter.convert(
            documents: [("doc1.md", doc1), ("doc2.md", doc2)],
            options: options
        )

        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3)

        // Header should have both author and title
        #expect(String(lines[0]).contains("author"))
        #expect(String(lines[0]).contains("title"))

        // Second row should have empty author field (two consecutive commas or comma at end)
        let row2 = String(lines[2])
        #expect(row2.contains("Doc 2"))
    }

    // MARK: - Files Without Frontmatter

    @Test
    func `Handle files without frontmatter`() throws {
        let doc = try MarkdownDocument(content: "# Just content\n\nNo frontmatter here.")

        let converter = CSVConverter()
        let options = CSVOptions(includeBody: true)

        let csv = try converter.convert(documents: [("test.md", doc)], options: options)

        // Should still generate valid CSV with body content
        #expect(csv.contains("$body"))
        #expect(csv.contains("Just content"))
        #expect(csv.contains("No frontmatter here"))
    }

    @Test
    func `Handle mixed documents with and without frontmatter`() throws {
        let doc1 = try MarkdownDocument(content: """
            ---
            title: Doc with FM
            ---
            Content 1
            """)

        let doc2 = try MarkdownDocument(content: "# Doc without FM\n\nContent 2")

        let converter = CSVConverter()
        let options = CSVOptions(includeBody: true)

        let csv = try converter.convert(
            documents: [("doc1.md", doc1), ("doc2.md", doc2)],
            options: options
        )

        // Should have title column from doc1
        #expect(csv.contains("title"))

        // Both documents should be present
        #expect(csv.contains("Doc with FM"))
        #expect(csv.contains("Doc without FM"))
    }
}
