//
//  SetTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities
import ArgumentParser

@Suite("fm set command")
struct SetTests {

  @Test
  func `fm set creates new frontmatter key`() async throws {
    let testContent = "Just body"

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Set.parseAsRoot([
      "--key", "title",
      "--value", "Test Title",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Set)

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

    let command_ = try CLIEntry.FrontMatterCommands.Set.parseAsRoot([
      "--key", "title",
      "--value", "Updated Title",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Set)

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

    let command_ = try CLIEntry.FrontMatterCommands.Set.parseAsRoot([
      "--key", "author",
      "--value", "Jane",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Set)

    try await command.run()

    // Verify body is preserved
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.body == bodyContent)
  }

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

    let command_ = try CLIEntry.FrontMatterCommands.Set.parseAsRoot([
      "--key", "category",
      "--value", "Tutorial",
      file1.string,
      file2.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Set)

    try await command.run()

    // Verify both files were updated
    let doc1 = try MarkdownDocument(content: try file1.read())
    let doc2 = try MarkdownDocument(content: try file2.read())

    #expect(doc1.getValue(forKey: "category")?.string == "Tutorial")
    #expect(doc2.getValue(forKey: "category")?.string == "Tutorial")
  }

  // MARK: - Invalid YAML Error Handling Tests

  @Test
  func `batch set skips file with invalid YAML processes valid files and exits with failure`() async throws {
    let validContent = """
    ---
    title: Valid File
    ---
    Body
    """
    // Invalid YAML: unclosed array bracket
    let invalidContent = """
    ---
    key: [unclosed
    ---
    Body
    """

    let validFile = try createTempFile(content: validContent, name: "valid.md")
    let invalidFile = try createTempFile(content: invalidContent, name: "invalid.md")
    defer {
      try? validFile.delete()
      try? invalidFile.delete()
    }

    let command_ = try CLIEntry.FrontMatterCommands.Set.parseAsRoot([
      "--key", "status",
      "--value", "processed",
      validFile.string, invalidFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Set)

    // Should throw ExitCode.failure, not propagate the raw YAML error
    do {
      try await command.run()
      Issue.record("Expected ExitCode.failure to be thrown")
    } catch let code as ExitCode {
      #expect(code == ExitCode.failure)
    } catch {
      Issue.record("Expected ExitCode, got: \(error)")
    }

    // Valid file should have been processed despite the error on the invalid file
    let updatedDoc = try MarkdownDocument(content: try validFile.read())
    #expect(updatedDoc.getValue(forKey: "status")?.string == "processed")

    // Invalid file should be unchanged (parse failed before write)
    let invalidFileContent: String = try invalidFile.read()
    #expect(invalidFileContent == invalidContent)
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
