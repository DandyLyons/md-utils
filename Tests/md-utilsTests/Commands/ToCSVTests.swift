//
//  ToCSVTests.swift
//  md-utilsTests
//
//  Tests for the to-csv command that converts Markdown files with frontmatter to CSV
//

import ArgumentParser
import Foundation
import PathKit
import Testing
@testable import md_utils
import MarkdownUtilities

@Suite("convert to-csv command")
struct ToCSVTests {

    // MARK: - Command Parsing Tests

    @Test
    func `command parses with default options`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            "test/"
        ])
        var command = try #require(command_ as? CLIEntry.ConvertCommands.ToCSV)

        #expect(command.body == true)
        #expect(command.includeMeta == nil)
        #expect(command.output == nil)
    }

    @Test
    func `command parses with no-body flag`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            "test/",
            "--no-body"
        ])
        var command = try #require(command_ as? CLIEntry.ConvertCommands.ToCSV)

        #expect(command.body == false)
    }

    @Test
    func `command parses with output option`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            "test/",
            "-o", "output.csv"
        ])
        var command = try #require(command_ as? CLIEntry.ConvertCommands.ToCSV)

        #expect(command.output?.string == "output.csv")
    }

    @Test
    func `command parses with long output option`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            "test/",
            "--output", "results.csv"
        ])
        var command = try #require(command_ as? CLIEntry.ConvertCommands.ToCSV)

        #expect(command.output?.string == "results.csv")
    }

    @Test
    func `command parses metadata columns - fileName`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            "test/",
            "--include-meta", "fileName"
        ])
        var command = try #require(command_ as? CLIEntry.ConvertCommands.ToCSV)

        let meta = try #require(command.includeMeta)
        #expect(meta.contains(.fileName))
        #expect(meta.count == 1)
    }

    @Test
    func `command parses metadata columns - multiple`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            "test/",
            "--include-meta", "fileName,relPath,absPath"
        ])
        var command = try #require(command_ as? CLIEntry.ConvertCommands.ToCSV)

        let meta = try #require(command.includeMeta)
        #expect(meta.contains(.fileName))
        #expect(meta.contains(.relPath))
        #expect(meta.contains(.absPath))
        #expect(meta.count == 3)
    }

    @Test
    func `command parses metadata columns with spaces`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            "test/",
            "--include-meta", "fileName, relPath, absPath"
        ])
        var command = try #require(command_ as? CLIEntry.ConvertCommands.ToCSV)

        let meta = try #require(command.includeMeta)
        #expect(meta.count == 3)
    }

    @Test
    func `command rejects invalid metadata column`() async throws {
        #expect(throws: (any Error).self) {
            try CLIEntry.parseAsRoot([
                "convert",
                "to-csv",
                "test/",
                "--include-meta", "invalid"
            ])
        }
    }

    @Test
    func `command parses with global options`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            "docs/",
            "--recursive",
            "--include-hidden"
        ])
        var command = try #require(command_ as? CLIEntry.ConvertCommands.ToCSV)

        #expect(command.options.recursive == true)
        #expect(command.options.includeHidden == true)
    }

    // MARK: - Integration Tests

    @Test
    func `converts single file to CSV`() async throws {
        // Create temporary directory
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        // Create test file
        let testFile = tempDir + "test.md"
        try testFile.write("""
            ---
            title: Test Document
            author: Alice
            ---

            Body content here.
            """)

        let outputFile = tempDir + "output.csv"

        // Run command
        var command = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            testFile.string,
            "-o", outputFile.string
        ]) as? CLIEntry.ConvertCommands.ToCSV

        try await command?.run()

        // Verify output exists
        #expect(outputFile.exists)

        // Verify CSV content
        let csv: String = try outputFile.read()
        #expect(csv.contains("$body"))
        #expect(csv.contains("author"))
        #expect(csv.contains("title"))
        #expect(csv.contains("Alice"))
        #expect(csv.contains("Test Document"))
        #expect(csv.contains("Body content here."))
    }

    @Test
    func `converts multiple files to CSV`() async throws {
        // Create temporary directory
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        // Create test files
        let file1 = tempDir + "doc1.md"
        try file1.write("""
            ---
            title: Doc 1
            author: Alice
            ---
            Content 1
            """)

        let file2 = tempDir + "doc2.md"
        try file2.write("""
            ---
            title: Doc 2
            author: Bob
            ---
            Content 2
            """)

        let outputFile = tempDir + "output.csv"

        // Run command
        var command = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            tempDir.string,
            "-o", outputFile.string
        ]) as? CLIEntry.ConvertCommands.ToCSV

        try await command?.run()

        // Verify output exists
        #expect(outputFile.exists)

        // Verify CSV content
        let csv: String = try outputFile.read()
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3) // Header + 2 data rows

        // Check both documents are present
        #expect(csv.contains("Doc 1"))
        #expect(csv.contains("Doc 2"))
        #expect(csv.contains("Alice"))
        #expect(csv.contains("Bob"))
    }

    @Test
    func `excludes body when --no-body flag is set`() async throws {
        // Create temporary directory
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        // Create test file
        let testFile = tempDir + "test.md"
        try testFile.write("""
            ---
            title: Test
            ---
            Body content
            """)

        let outputFile = tempDir + "output.csv"

        // Run command
        var command = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            testFile.string,
            "-o", outputFile.string,
            "--no-body"
        ]) as? CLIEntry.ConvertCommands.ToCSV

        try await command?.run()

        // Verify CSV doesn't include $body column
        let csv: String = try outputFile.read()
        #expect(!csv.contains("$body"))
        #expect(!csv.contains("Body content"))
    }

    @Test
    func `includes metadata columns`() async throws {
        // Create temporary directory
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        // Create test file
        let testFile = tempDir + "test.md"
        try testFile.write("""
            ---
            title: Test
            ---
            Content
            """)

        let outputFile = tempDir + "output.csv"

        // Run command
        var command = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            testFile.string,
            "-o", outputFile.string,
            "--include-meta", "fileName,absPath"
        ]) as? CLIEntry.ConvertCommands.ToCSV

        try await command?.run()

        // Verify metadata columns are present
        let csv: String = try outputFile.read()
        #expect(csv.contains("$fileName"))
        #expect(csv.contains("$absPath"))
        #expect(csv.contains("test.md"))
    }

    @Test
    func `handles files without frontmatter`() async throws {
        // Create temporary directory
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        // Create test file without frontmatter
        let testFile = tempDir + "test.md"
        try testFile.write("# Just Content\n\nNo frontmatter here.")

        let outputFile = tempDir + "output.csv"

        // Run command
        var command = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            testFile.string,
            "-o", outputFile.string
        ]) as? CLIEntry.ConvertCommands.ToCSV

        try await command?.run()

        // Verify output exists and contains body
        #expect(outputFile.exists)
        let csv: String = try outputFile.read()
        #expect(csv.contains("Just Content"))
    }

    @Test
    func `default output path for directory`() async throws {
        // Create temporary directory
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
        let docsDir = tempDir + "docs"
        try docsDir.mkpath()
        defer { try? tempDir.delete() }

        // Create test file
        let testFile = docsDir + "test.md"
        try testFile.write("""
            ---
            title: Test
            ---
            Content
            """)

        // Parse command properly to initialize all properties
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            docsDir.string
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToCSV)

        // Test the output path determination
        let outputPath = try command.determineOutputPath(inputFiles: [testFile])
        #expect(outputPath.string.hasSuffix("docs.csv"))
    }

    // MARK: - Error Handling Tests

    @Test
    func `fails when no files found`() async throws {
        // Create empty temporary directory
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        // Run command
        var command = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            tempDir.string
        ]) as? CLIEntry.ConvertCommands.ToCSV

        // Should throw validation error
        await #expect(throws: (any Error).self) {
            try await command?.run()
        }
    }

    @Test
    func `handles mixed valid and invalid files`() async throws {
        // Create temporary directory
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        // Create valid file
        let validFile = tempDir + "valid.md"
        try validFile.write("""
            ---
            title: Valid
            ---
            Content
            """)

        // Create invalid file with malformed YAML (invalid mapping syntax)
        let invalidFile = tempDir + "invalid.md"
        try invalidFile.write("""
            ---
            title: [unclosed array
            author: test
            ---
            Content
            """)

        let outputFile = tempDir + "output.csv"

        // Run command - should process valid files and report errors
        var command = try CLIEntry.parseAsRoot([
            "convert",
            "to-csv",
            tempDir.string,
            "-o", outputFile.string
        ]) as? CLIEntry.ConvertCommands.ToCSV

        // Command should complete but report errors and exit with failure
        await #expect(throws: ExitCode.self) {
            try await command?.run()
        }
    }

    // MARK: - Metadata Column Parsing Tests

    @Test
    func `parseMetadataColumns handles fileName`() throws {
        let result = try CLIEntry.ConvertCommands.ToCSV.parseMetadataColumns("fileName")
        #expect(result.contains(.fileName))
        #expect(result.count == 1)
    }

    @Test
    func `parseMetadataColumns handles relPath`() throws {
        let result = try CLIEntry.ConvertCommands.ToCSV.parseMetadataColumns("relPath")
        #expect(result.contains(.relPath))
        #expect(result.count == 1)
    }

    @Test
    func `parseMetadataColumns handles absPath`() throws {
        let result = try CLIEntry.ConvertCommands.ToCSV.parseMetadataColumns("absPath")
        #expect(result.contains(.absPath))
        #expect(result.count == 1)
    }

    @Test
    func `parseMetadataColumns handles multiple columns`() throws {
        let result = try CLIEntry.ConvertCommands.ToCSV.parseMetadataColumns("fileName,relPath")
        #expect(result.contains(.fileName))
        #expect(result.contains(.relPath))
        #expect(result.count == 2)
    }

    @Test
    func `parseMetadataColumns is case insensitive`() throws {
        let result = try CLIEntry.ConvertCommands.ToCSV.parseMetadataColumns("FILENAME,RelPath")
        #expect(result.contains(.fileName))
        #expect(result.contains(.relPath))
        #expect(result.count == 2)
    }

    @Test
    func `parseMetadataColumns rejects invalid column`() throws {
        #expect(throws: ValidationError.self) {
            try CLIEntry.ConvertCommands.ToCSV.parseMetadataColumns("invalid")
        }
    }

    @Test
    func `parseMetadataColumns handles whitespace`() throws {
        let result = try CLIEntry.ConvertCommands.ToCSV.parseMetadataColumns(" fileName , relPath ")
        #expect(result.contains(.fileName))
        #expect(result.contains(.relPath))
        #expect(result.count == 2)
    }
}
