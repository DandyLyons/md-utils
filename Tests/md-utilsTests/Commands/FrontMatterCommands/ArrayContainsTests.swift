//
//  ArrayContainsTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities
import Yams

@Suite("fm array contains command")
struct ArrayContainsTests {

  @Test
  func `fm array contains finds files with matching value`() async throws {
    let testContent1 = """
    ---
    tags:
      - swift
      - programming
    ---
    Test content
    """

    let testContent2 = """
    ---
    tags:
      - rust
      - systems
    ---
    Test content
    """

    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "file1.md"
    let file2 = tempDir + "file2.md"
    try file1.write(testContent1)
    try file2.write(testContent2)

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Contains.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Contains)

    try await command.run()
    // Command should succeed and output file1 path
  }

  @Test
  func `fm array contains with invert flag finds files not containing value`() async throws {
    let testContent1 = """
    ---
    tags:
      - swift
      - programming
    ---
    Test content
    """

    let testContent2 = """
    ---
    tags:
      - rust
      - systems
    ---
    Test content
    """

    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "file1.md"
    let file2 = tempDir + "file2.md"
    try file1.write(testContent1)
    try file2.write(testContent2)

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Contains.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      "--invert",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Contains)

    try await command.run()
    // Command should succeed and output file2 path
  }

  @Test
  func `fm array contains case insensitive matching`() async throws {
    let testContent = """
    ---
    tags:
      - Swift
      - Programming
    ---
    Test content
    """

    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file = tempDir + "file.md"
    try file.write(testContent)

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Contains.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      "--case-insensitive",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Contains)

    try await command.run()
    // Command should succeed (case-insensitive match)
  }

  @Test
  func `fm array contains skips files where key is not an array`() async throws {
    let testContent = """
    ---
    tags: not-an-array
    ---
    Test content
    """

    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file = tempDir + "file.md"
    try file.write(testContent)

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Contains.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Contains)

    // Should fail with no matches found
    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm array contains exits with error when no matches found`() async throws {
    let testContent = """
    ---
    tags:
      - rust
      - systems
    ---
    Test content
    """

    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file = tempDir + "file.md"
    try file.write(testContent)

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Contains.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Contains)

    // Should fail with no matches found
    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm array contains skips files where key does not exist`() async throws {
    let testContent = """
    ---
    title: Test Post
    ---
    Test content
    """

    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file = tempDir + "file.md"
    try file.write(testContent)

    let command_ = try CLIEntry.FrontMatterCommands.ArrayCommands.Contains.parseAsRoot([
      "--key", "tags",
      "--value", "swift",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.ArrayCommands.Contains)

    // Should fail with no matches found
    await #expect(throws: Error.self) {
      try await command.run()
    }
  }
}
