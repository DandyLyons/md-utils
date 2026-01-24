//
//  ArrayAppendTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities
import Yams

@Suite("fm array append command")
struct ArrayAppendTests {

  @Test
  func `fm array append adds value to end of array`() async throws {
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

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Append.parseAsRoot([
      "--key", "tags",
      "--value", "tutorial",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Append)

    try await command.run()

    // Verify the array was updated
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    let values = try extractArrayValues(from: doc, key: "tags")

    #expect(values == ["swift", "programming", "tutorial"])
  }

  @Test
  func `fm array append skip duplicates prevents adding existing value`() async throws {
    let testContent = """
    ---
    tags:
      - swift
    ---
    Test content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Append.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      "--skip-duplicates",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Append)

    try await command.run()

    // Verify the array was NOT modified
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    let values = try extractArrayValues(from: doc, key: "tags")

    #expect(values == ["swift"])
  }

  @Test
  func `fm array append without skip duplicates allows duplicates`() async throws {
    let testContent = """
    ---
    tags:
      - swift
    ---
    Test content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Append.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Append)

    try await command.run()

    // Verify the array now has duplicate
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    let values = try extractArrayValues(from: doc, key: "tags")

    #expect(values == ["swift", "swift"])
  }

  @Test
  func `fm array append case insensitive duplicate detection`() async throws {
    let testContent = """
    ---
    tags:
      - Swift
    ---
    Test content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Append.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      "--case-insensitive",
      "--skip-duplicates",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Append)

    try await command.run()

    // Verify the array was NOT modified (case-insensitive match)
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    let values = try extractArrayValues(from: doc, key: "tags")

    #expect(values == ["Swift"])
  }

  @Test
  func `fm array append creates array if key does not exist`() async throws {
    let testContent = """
    ---
    title: Test Post
    ---
    Body content here.
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Append.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Append)

    try await command.run()

    // Verify the array was created with the value
    let content: String = try tempFile.read()
    let doc = try MarkdownDocument(content: content)
    let values = try extractArrayValues(from: doc, key: "tags")

    #expect(values == ["swift"])
  }

  @Test
  func `fm array append errors if key exists but is not an array`() async throws {
    let testContent = """
    ---
    title: Test Post
    tags: not-an-array
    ---
    Body content here.
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Append.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Append)

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
