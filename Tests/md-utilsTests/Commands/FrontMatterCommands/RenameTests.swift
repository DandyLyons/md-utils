//
//  RenameTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("fm rename command")
struct RenameTests {

  @Test
  func `fm rename successfully renames existing key`() async throws {
    let testContent = """
    ---
    title: Test Document
    author: Jane Doe
    date: 2024-01-15
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "--key", "date",
      "--new-key", "created",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    try await command.run()

    // Verify the key was renamed
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.hasKey("date") == false)
    #expect(doc.hasKey("created") == true)
    #expect(doc.getValue(forKey: "created")?.string == "2024-01-15")
    // Other keys should remain unchanged
    #expect(doc.getValue(forKey: "title")?.string == "Test Document")
    #expect(doc.getValue(forKey: "author")?.string == "Jane Doe")
  }

  @Test
  func `fm rename with short option`() async throws {
    let testContent = """
    ---
    title: Test
    status: draft
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "-k", "status",
      "--new-key", "publish_status",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    try await command.run()

    // Verify the key was renamed
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.hasKey("status") == false)
    #expect(doc.hasKey("publish_status") == true)
    #expect(doc.getValue(forKey: "publish_status")?.string == "draft")
  }

  @Test
  func `fm rename throws when old key does not exist`() async throws {
    let testContent = """
    ---
    title: Test
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "--key", "nonexistent",
      "--new-key", "newkey",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    // Should throw an error
    await #expect(throws: Error.self) {
      try await command.run()
    }

    // Verify file was not modified
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    #expect(doc.hasKey("title") == true)
    #expect(doc.hasKey("newkey") == false)
  }

  @Test
  func `fm rename throws when new key already exists`() async throws {
    let testContent = """
    ---
    title: Test
    author: Jane
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "--key", "title",
      "--new-key", "author",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    // Should throw an error
    await #expect(throws: Error.self) {
      try await command.run()
    }

    // Verify file was not modified
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    #expect(doc.getValue(forKey: "title")?.string == "Test")
    #expect(doc.getValue(forKey: "author")?.string == "Jane")
  }

  @Test
  func `fm rename preserves body content`() async throws {
    let bodyContent = "# Important Heading\n\nThis is critical content.\n"
    let testContent = """
    ---
    title: Test
    ---
    \(bodyContent)
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "--key", "title",
      "--new-key", "heading",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    try await command.run()

    // Verify body is preserved
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.body == bodyContent)
  }

  @Test
  func `fm rename preserves complex values`() async throws {
    let testContent = """
    ---
    tags:
      - swift
      - markdown
      - cli
    metadata:
      created: 2024-01-01
      updated: 2024-01-15
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "--key", "tags",
      "--new-key", "categories",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    try await command.run()

    // Verify the array was preserved
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.hasKey("tags") == false)
    #expect(doc.hasKey("categories") == true)

    let categories = doc.getValue(forKey: "categories")
    #expect(categories != nil)
    #expect(categories?.sequence?.count == 3)

    // Verify other keys are intact
    #expect(doc.hasKey("metadata") == true)
  }

  @Test
  func `fm rename processes multiple files`() async throws {
    let content1 = """
    ---
    title: Doc 1
    old_key: Value 1
    ---
    Body 1
    """

    let content2 = """
    ---
    title: Doc 2
    old_key: Value 2
    ---
    Body 2
    """

    let file1 = try createTempFile(content: content1, name: "doc1.md")
    let file2 = try createTempFile(content: content2, name: "doc2.md")
    defer {
      try? file1.delete()
      try? file2.delete()
    }

    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "--key", "old_key",
      "--new-key", "new_key",
      file1.string,
      file2.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    try await command.run()

    // Verify both files were updated
    let doc1 = try MarkdownDocument(content: try file1.read())
    let doc2 = try MarkdownDocument(content: try file2.read())

    #expect(doc1.hasKey("old_key") == false)
    #expect(doc1.hasKey("new_key") == true)
    #expect(doc1.getValue(forKey: "new_key")?.string == "Value 1")

    #expect(doc2.hasKey("old_key") == false)
    #expect(doc2.hasKey("new_key") == true)
    #expect(doc2.getValue(forKey: "new_key")?.string == "Value 2")
  }

  @Test
  func `fm rename with directory recursion`() async throws {
    // Create temporary directory structure
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkdir()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "doc1.md"
    let file2 = tempDir + "doc2.md"

    let content = """
    ---
    old_name: Test Value
    other: Keep This
    ---
    Body
    """

    try file1.write(content)
    try file2.write(content)

    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "--key", "old_name",
      "--new-key", "new_name",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    try await command.run()

    // Verify both files were updated
    let doc1 = try MarkdownDocument(content: try file1.read())
    let doc2 = try MarkdownDocument(content: try file2.read())

    #expect(doc1.hasKey("old_name") == false)
    #expect(doc1.hasKey("new_name") == true)
    #expect(doc1.getValue(forKey: "new_name")?.string == "Test Value")
    #expect(doc1.getValue(forKey: "other")?.string == "Keep This")

    #expect(doc2.hasKey("old_name") == false)
    #expect(doc2.hasKey("new_name") == true)
    #expect(doc2.getValue(forKey: "new_name")?.string == "Test Value")
    #expect(doc2.getValue(forKey: "other")?.string == "Keep This")
  }

  @Test
  func `fm rename handles numeric values`() async throws {
    let testContent = """
    ---
    count: 42
    price: 19.99
    active: true
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "--key", "count",
      "--new-key", "total",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    try await command.run()

    // Verify numeric value was preserved
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.hasKey("count") == false)
    #expect(doc.hasKey("total") == true)
    #expect(doc.getValue(forKey: "total")?.int == 42)
  }

  @Test
  func `fm rename works with alias rn`() async throws {
    let testContent = """
    ---
    before: value
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    // Use the 'rn' alias
    let command_ = try CLIEntry.FrontMatterCommands.Rename.parseAsRoot([
      "--key", "before",
      "--new-key", "after",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Rename)

    try await command.run()

    // Verify it worked
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.hasKey("before") == false)
    #expect(doc.hasKey("after") == true)
    #expect(doc.getValue(forKey: "after")?.string == "value")
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
