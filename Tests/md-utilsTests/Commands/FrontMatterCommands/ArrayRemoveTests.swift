//
//  ArrayRemoveTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities
import Yams

@Suite("fm array remove command")
struct ArrayRemoveTests {

  @Test
  func `fm array remove removes first occurrence of value`() async throws {
    let testContent = """
    ---
    tags:
      - swift
      - programming
      - tutorial
    ---
    Test content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Remove.parseAsRoot([
      "--key", "tags",
      "--value", "programming",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Remove)

    try await command.run()

    // Verify the value was removed
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    let values = try extractArrayValues(from: doc, key: "tags")

    #expect(values == ["swift", "tutorial"])
  }

  @Test
  func `fm array remove only removes first occurrence when duplicates exist`() async throws {
    let testContent = """
    ---
    tags:
      - swift
      - swift
      - programming
    ---
    Test content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Remove.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Remove)

    try await command.run()

    // Verify only first occurrence was removed
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    let values = try extractArrayValues(from: doc, key: "tags")

    #expect(values == ["swift", "programming"])
  }

  @Test
  func `fm array remove case insensitive matching`() async throws {
    let testContent = """
    ---
    tags:
      - Swift
      - programming
    ---
    Test content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Remove.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      "--case-insensitive",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Remove)

    try await command.run()

    // Verify the value was removed (case-insensitive match)
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    let values = try extractArrayValues(from: doc, key: "tags")

    #expect(values == ["programming"])
  }

  @Test
  func `fm array remove skips files where value not found`() async throws {
    let testContent = """
    ---
    tags:
      - swift
      - programming
    ---
    Test content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Remove.parseAsRoot([
      "--key", "tags",
      "--value", "nonexistent",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Remove)

    try await command.run()

    // Verify the array was NOT modified
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    let values = try extractArrayValues(from: doc, key: "tags")

    #expect(values == ["swift", "programming"])
  }

  @Test
  func `fm array remove errors if key does not exist`() async throws {
    let testContent = """
    ---
    title: Test Post
    ---
    Body content here.
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Remove.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Remove)

    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm array remove errors if key exists but is not an array`() async throws {
    let testContent = """
    ---
    title: Test Post
    tags: not-an-array
    ---
    Body content here.
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Remove.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Remove)

    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  // MARK: - Test Helpers

  private func createTempFile(content: String, name: String) throws -> Path {
    let tempDir = Path(NSTemporaryDirectory())
    let tempFile = tempDir + "md-utils-test-\(UUID().uuidString)-\(name)"
    try tempFile.write(content)
    return tempFile
  }

  private func extractArrayValues(from doc: MarkdownDocument, key: String) throws -> [String] {
    guard let node = doc.getValue(forKey: key),
          case .sequence(let sequence) = node else {
      return []
    }
    return sequence.compactMap { node in
      guard case .scalar(let scalar) = node else { return nil }
      return scalar.string
    }
  }
}
