//
//  RemoveTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("fm remove command")
struct RemoveTests {

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

    let command_ = try CLIEntry.FrontMatterCommands.Remove.parseAsRoot([
      "--key", "author",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Remove)

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

    let command_ = try CLIEntry.FrontMatterCommands.Remove.parseAsRoot([
      "--key", "nonexistent",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Remove)

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

    let command_ = try CLIEntry.FrontMatterCommands.Remove.parseAsRoot([
      "--key", "title",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Remove)

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

    let command_ = try CLIEntry.FrontMatterCommands.Remove.parseAsRoot([
      "--key", "author",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Remove)

    try await command.run()

    // Verify body is preserved
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.body == bodyContent)
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
