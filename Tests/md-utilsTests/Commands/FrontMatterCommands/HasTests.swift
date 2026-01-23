//
//  HasTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("fm has command")
struct HasTests {

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

  // MARK: - Test Helpers

  /// Create a temporary markdown file with the given content
  private func createTempFile(content: String, name: String) throws -> Path {
    let tempDir = Path(NSTemporaryDirectory())
    let tempFile = tempDir + "md-utils-test-\(UUID().uuidString)-\(name)"

    try tempFile.write(content)

    return tempFile
  }
}
