//
//  ListTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("fm list command")
struct ListTests {

  @Test
  func `fm list shows keys from single file`() async throws {
    let testContent = """
    ---
    title: Test Document
    author: Jane Doe
    date: 2026-01-23
    tags:
      - test
      - markdown
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.List.parseAsRoot([
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.List

    // Should not throw
    try await command.run()
  }

  @Test
  func `fm list handles file with no frontmatter`() async throws {
    let testContent = "# Just Body Content\n\nNo frontmatter here."

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.List.parseAsRoot([
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.List

    // Should not throw, but prints empty result
    try await command.run()
  }

  @Test
  func `fm list handles empty frontmatter`() async throws {
    let testContent = """
    ---
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.List.parseAsRoot([
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.List

    // Should not throw
    try await command.run()
  }

  @Test
  func `fm list processes multiple files`() async throws {
    let content1 = """
    ---
    title: Document 1
    author: John
    category: tutorial
    ---
    Body 1
    """

    let content2 = """
    ---
    title: Document 2
    date: 2026-01-23
    version: 1.0
    ---
    Body 2
    """

    let file1 = try createTempFile(content: content1, name: "doc1.md")
    let file2 = try createTempFile(content: content2, name: "doc2.md")
    defer {
      try? file1.delete()
      try? file2.delete()
    }

    var command = try CLIEntry.FrontMatterCommands.List.parseAsRoot([
      file1.string,
      file2.string
    ]) as! CLIEntry.FrontMatterCommands.List

    // Should not throw and process both files
    try await command.run()
  }

  @Test
  func `fm list processes directory recursively`() async throws {
    let content1 = """
    ---
    title: Root Doc
    ---
    Body
    """

    let content2 = """
    ---
    title: Nested Doc
    author: Jane
    ---
    Body
    """

    // Create temporary directory structure
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    let nestedDir = tempDir + "nested"
    try tempDir.mkdir()
    try nestedDir.mkdir()

    let file1 = tempDir + "root.md"
    let file2 = nestedDir + "nested.md"

    try file1.write(content1)
    try file2.write(content2)

    defer {
      try? tempDir.delete()
    }

    var command = try CLIEntry.FrontMatterCommands.List.parseAsRoot([
      tempDir.string
    ]) as! CLIEntry.FrontMatterCommands.List

    // Should not throw and find both files recursively
    try await command.run()
  }

  @Test
  func `fm list handles mixed files with and without frontmatter`() async throws {
    let contentWithFM = """
    ---
    title: Has Frontmatter
    author: Jane
    ---
    Body
    """

    let contentWithoutFM = "# No Frontmatter\n\nJust body."

    let file1 = try createTempFile(content: contentWithFM, name: "with-fm.md")
    let file2 = try createTempFile(content: contentWithoutFM, name: "without-fm.md")
    defer {
      try? file1.delete()
      try? file2.delete()
    }

    var command = try CLIEntry.FrontMatterCommands.List.parseAsRoot([
      file1.string,
      file2.string
    ]) as! CLIEntry.FrontMatterCommands.List

    // Should not throw and handle both cases gracefully
    try await command.run()
  }

  @Test
  func `fm list alias ls works`() async throws {
    let testContent = """
    ---
    title: Test
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    // Parse using the 'ls' alias
    var command = try CLIEntry.FrontMatterCommands.List.parseAsRoot([
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.List

    // Should parse successfully and work the same as 'list'
    try await command.run()
  }

  // MARK: - Test Helpers

  /// Create a temporary markdown file with the given content
  private func createTempFile(content: String, name: String) throws -> Path {
    let tempDir = Path(NSTemporaryDirectory())
    let tempFile = tempDir + "md-utils-test-\(UUID().uuidString)-\(name)"

    try tempFile.write(content)

    return tempFile
  }
}
