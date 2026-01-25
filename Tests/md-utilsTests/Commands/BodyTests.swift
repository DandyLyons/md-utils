//
//  BodyTests.swift
//  md-utilsTests
//
//  Tests for the Body command that extracts body content without frontmatter
//

import Foundation
import PathKit
import Testing
@testable import md_utils
import MarkdownUtilities

@Suite("body command")
struct BodyTests {

  // MARK: - Test Fixtures

  /// Sample markdown with frontmatter
  let sampleWithFrontmatter = """
    ---
    title: Test Document
    author: Claude
    tags: [test, markdown]
    ---

    # Welcome

    This is **bold** text.

    ## Section

    - Item 1
    - Item 2

    ```swift
    let code = "example"
    ```
    """

  /// Expected body (markdown format) - includes leading newline after frontmatter
  let expectedBodyMarkdown = """

    # Welcome

    This is **bold** text.

    ## Section

    - Item 1
    - Item 2

    ```swift
    let code = "example"
    ```
    """

  /// Sample markdown without frontmatter
  let sampleWithoutFrontmatter = """
    # Just Body

    No frontmatter here.
    """

  // MARK: - Command Parsing Tests

  @Test
  func `command parses with default markdown format`() async throws {
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      "test.md"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    #expect(command.format == .markdown)
    #expect(command.options.paths.count == 1)
  }

  @Test
  func `command parses with plain-text format`() async throws {
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      "test.md",
      "--format", "plain-text"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    #expect(command.format == .plainText)
  }

  @Test
  func `command parses with short format flag`() async throws {
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      "test.md",
      "-f", "plain-text"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    #expect(command.format == .plainText)
  }

  @Test
  func `command accepts alias 'b'`() async throws {
    let command_ = try CLIEntry.parseAsRoot([
      "b",
      "test.md"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    #expect(command.options.paths.count == 1)
  }

  @Test
  func `command parses multiple file paths`() async throws {
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      "file1.md",
      "file2.md",
      "file3.md"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    #expect(command.options.paths.count == 3)
  }

  @Test
  func `command parses with global options`() async throws {
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      "docs/",
      "--recursive",
      "--include-hidden",
      "--format", "plain-text"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    #expect(command.options.recursive == true)
    #expect(command.options.includeHidden == true)
    #expect(command.format == .plainText)
  }

  // MARK: - Format Tests

  @Test
  func `markdown format preserves formatting`() async throws {
    // Create temporary file
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let testFile = tempDir + "test.md"
    try testFile.write(sampleWithFrontmatter)

    // Parse command
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      testFile.string,
      "--format", "markdown"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    // Extract body
    let doc = try MarkdownDocument(content: sampleWithFrontmatter)
    let output = try await command.extractBody(from: doc)

    #expect(output == expectedBodyMarkdown)
    #expect(output.contains("**bold**"))
    #expect(output.contains("```swift"))
    #expect(!output.contains("title: Test Document"))
  }

  @Test
  func `plain-text format strips markdown`() async throws {
    // Create temporary file
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let testFile = tempDir + "test.md"
    try testFile.write(sampleWithFrontmatter)

    // Parse command
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      testFile.string,
      "--format", "plain-text"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    // Extract body
    let doc = try MarkdownDocument(content: sampleWithFrontmatter)
    let output = try await command.extractBody(from: doc)

    #expect(!output.contains("**bold**"))
    #expect(!output.contains("```swift"))
    #expect(output.contains("bold"))  // Text should still be there
    #expect(output.contains("Welcome"))
    #expect(!output.contains("title: Test Document"))
  }

  @Test
  func `markdown format works without frontmatter`() async throws {
    // Create temporary file
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let testFile = tempDir + "test.md"
    try testFile.write(sampleWithoutFrontmatter)

    // Parse command
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      testFile.string
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    // Extract body
    let doc = try MarkdownDocument(content: sampleWithoutFrontmatter)
    let output = try await command.extractBody(from: doc)

    #expect(output == sampleWithoutFrontmatter)
  }

  @Test
  func `plain-text format works without frontmatter`() async throws {
    // Create temporary file
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let testFile = tempDir + "test.md"
    try testFile.write(sampleWithoutFrontmatter)

    // Parse command
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      testFile.string,
      "--format", "plain-text"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    // Extract body
    let doc = try MarkdownDocument(content: sampleWithoutFrontmatter)
    let output = try await command.extractBody(from: doc)

    #expect(output.contains("Just Body"))
    #expect(!output.contains("#"))  // Heading marker should be stripped
  }

  // MARK: - Edge Case Tests

  @Test
  func `handles empty body after frontmatter`() async throws {
    let emptyBody = """
      ---
      title: Empty
      ---
      """

    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let testFile = tempDir + "test.md"
    try testFile.write(emptyBody)

    let command_ = try CLIEntry.parseAsRoot([
      "body",
      testFile.string
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    let doc = try MarkdownDocument(content: emptyBody)
    let output = try await command.extractBody(from: doc)

    // Empty body should just be empty or whitespace
    #expect(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  @Test
  func `handles only frontmatter no body`() async throws {
    let onlyFrontmatter = """
      ---
      title: Only Frontmatter
      author: Test
      ---
      """

    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let testFile = tempDir + "test.md"
    try testFile.write(onlyFrontmatter)

    let command_ = try CLIEntry.parseAsRoot([
      "body",
      testFile.string
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    let doc = try MarkdownDocument(content: onlyFrontmatter)
    let output = try await command.extractBody(from: doc)

    #expect(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  @Test
  func `preserves whitespace in body`() async throws {
    let withWhitespace = """
      ---
      title: Test
      ---


      Line 1


      Line 2
      """

    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let testFile = tempDir + "test.md"
    try testFile.write(withWhitespace)

    let command_ = try CLIEntry.parseAsRoot([
      "body",
      testFile.string,
      "--format", "markdown"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    let doc = try MarkdownDocument(content: withWhitespace)
    let output = try await command.extractBody(from: doc)

    // Should preserve the blank lines between content
    #expect(output.contains("\n\n"))
  }

  // MARK: - File Processing Tests

  @Test
  func `processes single file successfully`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let testFile = tempDir + "test.md"
    try testFile.write(sampleWithFrontmatter)

    let command_ = try CLIEntry.parseAsRoot([
      "body",
      testFile.string
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    // Should not throw
    try await command.run()
  }

  @Test
  func `error on nonexistent file`() async throws {
    let command_ = try CLIEntry.parseAsRoot([
      "body",
      "/nonexistent/file.md"
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `processes directory with multiple files`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    // Create multiple test files
    let file1 = tempDir + "file1.md"
    let file2 = tempDir + "file2.md"
    try file1.write(sampleWithFrontmatter)
    try file2.write(sampleWithoutFrontmatter)

    let command_ = try CLIEntry.parseAsRoot([
      "body",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    // Should process without error
    try await command.run()
  }

  // MARK: - Input Mode Tests

  @Test
  func `determines single file input mode`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let testFile = tempDir + "test.md"
    try testFile.write(sampleWithFrontmatter)

    let command_ = try CLIEntry.parseAsRoot([
      "body",
      testFile.string
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    let inputMode = try command.determineInputMode()

    switch inputMode {
    case .singleFile(let path):
      #expect(path == testFile)
    default:
      Issue.record("Expected single file mode")
    }
  }

  @Test
  func `determines multiple files input mode`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "file1.md"
    let file2 = tempDir + "file2.md"
    try file1.write(sampleWithFrontmatter)
    try file2.write(sampleWithoutFrontmatter)

    let command_ = try CLIEntry.parseAsRoot([
      "body",
      file1.string,
      file2.string
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    let inputMode = try command.determineInputMode()

    switch inputMode {
    case .multipleFiles(let paths):
      #expect(paths.count == 2)
    default:
      Issue.record("Expected multiple files mode")
    }
  }

  @Test
  func `error when no markdown files found`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    // Create a non-markdown file
    let txtFile = tempDir + "test.txt"
    try txtFile.write("Not markdown")

    let command_ = try CLIEntry.parseAsRoot([
      "body",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.Body)

    // Should error when no .md files found in directory
    #expect(throws: Error.self) {
      try command.determineInputMode()
    }
  }
}
