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

  // MARK: - Test Helpers

  /// Create a temporary markdown file with the given content
  private func createTempFile(content: String, name: String) throws -> Path {
    let tempDir = Path(NSTemporaryDirectory())
    let tempFile = tempDir + "md-utils-test-\(UUID().uuidString)-\(name)"

    try tempFile.write(content)

    return tempFile
  }
}
