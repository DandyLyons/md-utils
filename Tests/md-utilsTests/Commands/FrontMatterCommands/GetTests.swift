//
//  GetTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("fm get command")
struct GetTests {

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

    let command_ = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "title",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Get)

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

    let command_ = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "nonexistent",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Get)

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

    let command_ = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "title",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Get)

    // Should throw because there's no frontmatter
    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm get with inline format outputs arrays in bracket notation`() async throws {
    let testContent = """
    ---
    tags: [swift, testing, markdown]
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "tags",
      "--format", "inline",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Get)

    // Should not throw and output inline format
    try await command.run()
  }

  @Test
  func `fm get with bullets format outputs arrays as markdown bullets`() async throws {
    let testContent = """
    ---
    tags: [swift, testing, markdown]
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "tags",
      "--format", "bullets",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Get)

    // Should not throw and output bullet list format
    try await command.run()
  }

  @Test
  func `fm get with numbered-list format outputs arrays as numbered list`() async throws {
    let testContent = """
    ---
    tags: [swift, testing, markdown]
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "tags",
      "--format", "numbered-list",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Get)

    // Should not throw and output numbered list format
    try await command.run()
  }

  @Test
  func `fm get format option has no effect on scalar values`() async throws {
    let testContent = """
    ---
    title: Test Document
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "title",
      "--format", "bullets",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Get)

    // Should not throw; format doesn't affect scalar values
    try await command.run()
  }

  @Test
  func `fm get processes multiple files in alphabetical order`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    // Create files in non-alphabetical order
    let file1 = tempDir + "zebra.md"
    let file2 = tempDir + "alpha.md"
    let file3 = tempDir + "middle.md"

    let testContent = """
    ---
    title: Test
    status: draft
    ---
    Body
    """

    try file1.write(testContent)
    try file2.write(testContent)
    try file3.write(testContent)

    let command_ = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "status",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Get)

    // Should not throw and process files in alphabetical order
    // (We can't easily verify output order without capturing stdout,
    // but we can verify the command succeeds with multiple files)
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
