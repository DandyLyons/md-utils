//
//  ToHTMLCommandTests.swift
//  md-utilsTests
//
//  Tests for the to-html command that converts Markdown files to HTML.
//

import ArgumentParser
import Foundation
import PathKit
import Testing
@testable import md_utils
import MarkdownUtilities

@Suite("convert to-html command")
struct ToHTMLCommandTests {

    // MARK: - Command Parsing Tests

    @Test
    func `command parses with default options`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert",
            "to-html",
            "README.md"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        #expect(command.output == nil)
        #expect(command.inPlace == false)
        #expect(command.wrapDocument == false)
        #expect(command.includeFrontmatter == false)
        #expect(command.hardBreaks == false)
        #expect(command.allowUnsafeHtml == false)
        #expect(command.smartPunctuation == false)
        #expect(command.tables == true)
        #expect(command.autolinks == true)
        #expect(command.strikethrough == true)
        #expect(command.tagfilters == true)
        #expect(command.tasklist == true)
    }

    @Test
    func `command parses short output option`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md", "-o", "out.html"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        #expect(command.output?.string == "out.html")
    }

    @Test
    func `command parses long output option`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md", "--output", "result.html"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        #expect(command.output?.string == "result.html")
    }

    @Test
    func `command parses in-place flag`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md", "--in-place"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        #expect(command.inPlace == true)
    }

    @Test
    func `command parses wrap-document flag`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md", "--wrap-document"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        #expect(command.wrapDocument == true)
    }

    @Test
    func `command parses no-tables flag`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md", "--no-tables"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        #expect(command.tables == false)
        #expect(command.autolinks == true)
        #expect(command.strikethrough == true)
    }

    @Test
    func `command parses all no-X extension flags`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md",
            "--no-tables",
            "--no-autolinks",
            "--no-strikethrough",
            "--no-tagfilters",
            "--no-tasklist"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        #expect(command.tables == false)
        #expect(command.autolinks == false)
        #expect(command.strikethrough == false)
        #expect(command.tagfilters == false)
        #expect(command.tasklist == false)
    }

    @Test
    func `command parses global options`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "docs/",
            "--recursive",
            "--include-hidden"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        #expect(command.options.recursive == true)
        #expect(command.options.includeHidden == true)
    }

    @Test
    func `rejects output and in-place together`() async throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md",
            "--output", "out.html",
            "--in-place"
        ])
        var command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        await #expect(throws: (any Error).self) {
            try await command.run()
        }
    }

    // MARK: - Integration Tests

    @Test
    func `single file to output file`() async throws {
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-html-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        let inputFile = tempDir + "test.md"
        try inputFile.write("# Hello\n\n**World**")

        let outputFile = tempDir + "test.html"

        var command = try CLIEntry.parseAsRoot([
            "convert", "to-html",
            inputFile.string,
            "-o", outputFile.string
        ]) as? CLIEntry.ConvertCommands.ToHTML

        try await command?.run()

        #expect(outputFile.exists)
        let html: String = try outputFile.read()
        #expect(html.contains("<h1>Hello</h1>"))
        #expect(html.contains("<strong>World</strong>"))
    }

    @Test
    func `no-tables disables table rendering`() async throws {
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-html-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        let inputFile = tempDir + "table.md"
        try inputFile.write("| A | B |\n|---|---|\n| 1 | 2 |")

        let outputFile = tempDir + "table.html"

        var command = try CLIEntry.parseAsRoot([
            "convert", "to-html",
            inputFile.string,
            "-o", outputFile.string,
            "--no-tables"
        ]) as? CLIEntry.ConvertCommands.ToHTML

        try await command?.run()

        let html: String = try outputFile.read()
        #expect(!html.contains("<table>"))
    }

    @Test
    func `single file to output directory`() async throws {
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-html-test-\(UUID().uuidString)"
        let outDir = tempDir + "out"
        try outDir.mkpath()
        defer { try? tempDir.delete() }

        let inputFile = tempDir + "README.md"
        try inputFile.write("# Hello")

        var command = try CLIEntry.parseAsRoot([
            "convert", "to-html",
            inputFile.string,
            "-o", outDir.string
        ]) as? CLIEntry.ConvertCommands.ToHTML

        try await command?.run()

        let expectedOutput = outDir + "README.html"
        #expect(expectedOutput.exists)
    }

    @Test
    func `in-place writes html beside md`() async throws {
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-html-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        let inputFile = tempDir + "note.md"
        try inputFile.write("# Note")

        var command = try CLIEntry.parseAsRoot([
            "convert", "to-html",
            inputFile.string,
            "--in-place"
        ]) as? CLIEntry.ConvertCommands.ToHTML

        try await command?.run()

        let htmlFile = tempDir + "note.html"
        #expect(htmlFile.exists)
        let html: String = try htmlFile.read()
        #expect(html.contains("<h1>Note</h1>"))
    }

    @Test
    func `batch conversion to output directory`() async throws {
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-html-test-\(UUID().uuidString)"
        let outDir = tempDir + "html"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        let file1 = tempDir + "a.md"
        let file2 = tempDir + "b.md"
        try file1.write("# A")
        try file2.write("# B")

        var command = try CLIEntry.parseAsRoot([
            "convert", "to-html",
            tempDir.string,
            "-o", outDir.string
        ]) as? CLIEntry.ConvertCommands.ToHTML

        try await command?.run()

        #expect((outDir + "a.html").exists)
        #expect((outDir + "b.html").exists)
    }

    @Test
    func `wrap-document produces doctype`() async throws {
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-html-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        let inputFile = tempDir + "page.md"
        try inputFile.write("# Hello")

        let outputFile = tempDir + "page.html"

        var command = try CLIEntry.parseAsRoot([
            "convert", "to-html",
            inputFile.string,
            "-o", outputFile.string,
            "--wrap-document"
        ]) as? CLIEntry.ConvertCommands.ToHTML

        try await command?.run()

        let html: String = try outputFile.read()
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<body>"))
    }

    // MARK: - resolveOutputPath Tests

    @Test
    func `resolveOutputPath into existing directory appends html extension`() throws {
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-html-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        let inputFile = Path("docs/README.md")
        let result = command.resolveOutputPath(tempDir, for: inputFile)

        #expect(result.string.hasSuffix("README.html"))
    }

    @Test
    func `resolveOutputPath with trailing slash appends html extension`() throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        let result = command.resolveOutputPath(Path("output/"), for: Path("README.md"))
        #expect(result.string.hasSuffix("README.html"))
    }

    @Test
    func `resolveOutputPath to file returns file path as-is`() throws {
        let command_ = try CLIEntry.parseAsRoot([
            "convert", "to-html", "file.md"
        ])
        let command = try #require(command_ as? CLIEntry.ConvertCommands.ToHTML)

        let result = command.resolveOutputPath(Path("custom.html"), for: Path("README.md"))
        #expect(result.string == "custom.html")
    }

    // MARK: - Error Handling Tests

    @Test
    func `fails when no files found`() async throws {
        let tempDir = Path(NSTemporaryDirectory()) + "md-utils-html-test-\(UUID().uuidString)"
        try tempDir.mkpath()
        defer { try? tempDir.delete() }

        var command = try CLIEntry.parseAsRoot([
            "convert", "to-html",
            tempDir.string
        ]) as? CLIEntry.ConvertCommands.ToHTML

        await #expect(throws: (any Error).self) {
            try await command?.run()
        }
    }
}
