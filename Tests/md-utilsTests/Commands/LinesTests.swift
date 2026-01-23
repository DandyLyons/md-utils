//
//  LinesTests.swift
//  md-utilsTests
//
//  Tests for the lines command

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("lines command")
struct LinesTests {

  @Test
  func `lines extracts specified range from file`() async throws {
    let testContent = """
    Line 1
    Line 2
    Line 3
    Line 4
    Line 5
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "2",
      "--end", "4"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)

    // Verify it doesn't throw
    try command.run()
  }

  @Test
  func `lines extracts single line`() async throws {
    let testContent = """
    Line 1
    Line 2
    Line 3
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "2",
      "--end", "2"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)

    try command.run()
  }

  @Test
  func `lines works with numbered flag`() async throws {
    let testContent = """
    Line 1
    Line 2
    Line 3
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "1",
      "--end", "3",
      "--numbered"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)

    try command.run()
  }

  @Test
  func `lines handles range beyond file length`() async throws {
    let testContent = """
    Line 1
    Line 2
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "1",
      "--end", "10"
    ]) 
    var command = try #require(command_ as? CLIEntry.Lines)

    // Should not throw - returns all lines up to end of file
    try command.run()
  }

  @Test
  func `lines throws for invalid start line`() async throws {
    let testContent = """
    Line 1
    Line 2
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    // Start line must be greater than 0
    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "0",
      "--end", "2"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)
    #expect(throws: Error.self) {
      try command.run()
    }
  }

  @Test
  func `lines throws when end is before start`() async throws {
    let testContent = """
    Line 1
    Line 2
    Line 3
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "3",
      "--end", "1"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)
    #expect(throws: Error.self) {
      try command.run()
    }
  }

  @Test
  func `lines throws when file does not exist`() async throws {
    let command_ = try CLIEntry.Lines.parseAsRoot([
      "/nonexistent/file.md",
      "--start", "1",
      "--end", "10"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)
    #expect(throws: Error.self) {
      try command.run()
    }
  }

  @Test
  func `lines throws when start line exceeds file length`() async throws {
    let testContent = """
    Line 1
    Line 2
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "10",
      "--end", "15"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)
    #expect(throws: Error.self) {
      try command.run()
    }
  }

  @Test
  func `lines works with markdown frontmatter`() async throws {
    let testContent = """
    ---
    title: Test
    author: Jane
    ---

    # Heading

    Content line 1
    Content line 2
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "1",
      "--end", "4"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)

    try command.run()
  }

  @Test
  func `lines uses short flags`() async throws {
    let testContent = """
    Line 1
    Line 2
    Line 3
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "-s", "1",
      "-e", "2",
      "-n"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)

    try command.run()
  }

  @Test
  func `lines works with alias`() async throws {
    let testContent = """
    Line 1
    Line 2
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    // Test that 'l' alias works
    let command_ = try CLIEntry.parseAsRoot([
      "l",
      tempFile.string,
      "-s", "1",
      "-e", "2"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)

    try command.run()
  }

  @Test
  func `lines extracts from first line`() async throws {
    let testContent = """
    First line
    Second line
    Third line
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "1",
      "--end", "2"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)

    try command.run()
  }

  @Test
  func `lines extracts to last line`() async throws {
    let testContent = """
    Line 1
    Line 2
    Line 3
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "2",
      "--end", "3"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)

    try command.run()
  }

  @Test
  func `lines handles empty lines`() async throws {
    let testContent = """
    Line 1

    Line 3

    Line 5
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.Lines.parseAsRoot([
      tempFile.string,
      "--start", "1",
      "--end", "5"
    ])
    var command = try #require(command_ as? CLIEntry.Lines)

    try command.run()
  }

  // MARK: - Test Helpers

  /// Create a temporary file with the given content
  private func createTempFile(content: String, name: String) throws -> Path {
    let tempDir = Path(NSTemporaryDirectory())
    let tempFile = tempDir + "md-utils-test-\(UUID().uuidString)-\(name)"

    try tempFile.write(content)

    return tempFile
  }
}
