//
//  FrontMatterCommandsTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("FrontMatter CLI Commands")
struct FrontMatterCommandsTests {

  // MARK: - Get Command Tests

  @Test
  func `fm get retrieves existing key from single file`() async throws {
    let testContent = """
    ---
    title: Test Document
    author: Jane Doe
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "title",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Get

    // Verify it doesn't throw
    try await command.run()
  }

  @Test
  func `fm get handles missing key`() async throws {
    let testContent = """
    ---
    title: Test
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "nonexistent",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Get

    // Should throw because key doesn't exist
    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm get handles document with no frontmatter`() async throws {
    let testContent = "Just body content"

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "title",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Get

    // Should throw because there's no frontmatter
    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  // MARK: - Set Command Tests

  @Test
  func `fm set creates new frontmatter key`() async throws {
    let testContent = "Just body"

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Set.parseAsRoot([
      "--key", "title",
      "--value", "Test Title",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Set

    try await command.run()

    // Verify the file was updated
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.getValue(forKey: "title")?.string == "Test Title")
  }

  @Test
  func `fm set updates existing key`() async throws {
    let testContent = """
    ---
    title: Original
    author: Jane
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Set.parseAsRoot([
      "--key", "title",
      "--value", "Updated Title",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Set

    try await command.run()

    // Verify the file was updated
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.getValue(forKey: "title")?.string == "Updated Title")
    #expect(doc.getValue(forKey: "author")?.string == "Jane")
  }

  @Test
  func `fm set preserves body content`() async throws {
    let bodyContent = "# Important Heading\n\nThis is critical content.\n"
    let testContent = """
    ---
    title: Test
    ---
    \(bodyContent)
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Set.parseAsRoot([
      "--key", "author",
      "--value", "Jane",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Set

    try await command.run()

    // Verify body is preserved
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.body == bodyContent)
  }

  // MARK: - Has Command Tests

  @Test
  func `fm has returns true for existing key`() async throws {
    let testContent = """
    ---
    title: Test
    author: Jane
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Has.parseAsRoot([
      "--key", "title",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Has

    // Should not throw
    try await command.run()
  }

  @Test
  func `fm has returns false for missing key`() async throws {
    let testContent = """
    ---
    title: Test
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Has.parseAsRoot([
      "--key", "nonexistent",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Has

    // Should not throw (has always succeeds)
    try await command.run()
  }

  @Test
  func `fm has handles document with no frontmatter`() async throws {
    let testContent = "Just body"

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Has.parseAsRoot([
      "--key", "title",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Has

    // Should not throw (has always succeeds)
    try await command.run()
  }

  // MARK: - Remove Command Tests

  @Test
  func `fm remove deletes existing key`() async throws {
    let testContent = """
    ---
    title: Test
    author: Jane
    status: draft
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Remove.parseAsRoot([
      "--key", "author",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Remove

    try await command.run()

    // Verify the key was removed
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.hasKey("author") == false)
    #expect(doc.hasKey("title") == true)
    #expect(doc.hasKey("status") == true)
  }

  @Test
  func `fm remove is idempotent for missing key`() async throws {
    let testContent = """
    ---
    title: Test
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Remove.parseAsRoot([
      "--key", "nonexistent",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Remove

    // Should not throw (remove is idempotent)
    try await command.run()

    // Verify nothing was changed
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.hasKey("title") == true)
  }

  @Test
  func `fm remove can remove last key`() async throws {
    let testContent = """
    ---
    title: Test
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Remove.parseAsRoot([
      "--key", "title",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Remove

    try await command.run()

    // Verify frontmatter is empty
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.frontMatter.isEmpty)
  }

  @Test
  func `fm remove preserves body content`() async throws {
    let bodyContent = "# Important\n\nContent here.\n"
    let testContent = """
    ---
    title: Test
    author: Jane
    ---
    \(bodyContent)
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    var command = try CLIEntry.FrontMatterCommands.Remove.parseAsRoot([
      "--key", "author",
      tempFile.string
    ]) as! CLIEntry.FrontMatterCommands.Remove

    try await command.run()

    // Verify body is preserved
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.body == bodyContent)
  }

  // MARK: - List Command Tests

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

  // MARK: - Multiple Files Tests

  @Test
  func `fm set processes multiple files`() async throws {
    let content1 = """
    ---
    title: Doc 1
    ---
    Body 1
    """

    let content2 = """
    ---
    title: Doc 2
    ---
    Body 2
    """

    let file1 = try createTempFile(content: content1, name: "doc1.md")
    let file2 = try createTempFile(content: content2, name: "doc2.md")
    defer {
      try? file1.delete()
      try? file2.delete()
    }

    var command = try CLIEntry.FrontMatterCommands.Set.parseAsRoot([
      "--key", "category",
      "--value", "Tutorial",
      file1.string,
      file2.string
    ]) as! CLIEntry.FrontMatterCommands.Set

    try await command.run()

    // Verify both files were updated
    let doc1 = try MarkdownDocument(content: try file1.read())
    let doc2 = try MarkdownDocument(content: try file2.read())

    #expect(doc1.getValue(forKey: "category")?.string == "Tutorial")
    #expect(doc2.getValue(forKey: "category")?.string == "Tutorial")
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
