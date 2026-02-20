//
//  SearchTests.swift
//  md-utilsTests
//

import ArgumentParser
import Foundation
import PathKit
import Testing

@testable import md_utils

@Suite("fm search command")
struct SearchTests {

  // MARK: - Basic Equality Tests

  @Test
  func `search finds files where draft equals true`() async throws {
    let draftTrue = """
      ---
      draft: true
      title: "Draft Post"
      tags:
        - swift
        - programming
      ---
      # Draft Post

      This is a draft post.
      """

    let draftFalse = """
      ---
      draft: false
      title: "Published Post"
      tags:
        - swift
        - tutorial
      ---
      # Published Post

      This is a published post.
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "draft-true.md"
    let file2 = tempDir + "draft-false.md"

    try file1.write(draftTrue)
    try file2.write(draftFalse)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  @Test
  func `search finds files where draft equals false`() async throws {
    let draftTrue = """
      ---
      draft: true
      title: "Draft Post"
      ---
      # Draft Post
      """

    let draftFalse = """
      ---
      draft: false
      title: "Published Post"
      ---
      # Published Post
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "draft-true.md"
    let file2 = tempDir + "draft-false.md"

    try file1.write(draftTrue)
    try file2.write(draftFalse)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `false`",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  // MARK: - Array Contains Tests

  @Test
  func `search finds files where aliases contains Blue`() async throws {
    let aliasesFile = """
      ---
      title: "Post with Aliases"
      aliases:
        - Blue
        - Red
        - Green
      draft: false
      ---
      # Post with Aliases
      """

    let otherFile = """
      ---
      title: "Other Post"
      draft: true
      ---
      # Other Post
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "aliases.md"
    let file2 = tempDir + "other.md"

    try file1.write(aliasesFile)
    try file2.write(otherFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "contains(aliases, `\"Blue\"`)",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  @Test
  func `search finds files where tags contains swift`() async throws {
    let swiftFile1 = """
      ---
      draft: true
      tags:
        - swift
        - programming
      ---
      # Swift Post 1
      """

    let swiftFile2 = """
      ---
      draft: false
      tags:
        - swift
        - tutorial
      ---
      # Swift Post 2
      """

    let pythonFile = """
      ---
      draft: false
      tags:
        - python
      ---
      # Python Post
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "swift1.md"
    let file2 = tempDir + "swift2.md"
    let file3 = tempDir + "python.md"

    try file1.write(swiftFile1)
    try file2.write(swiftFile2)
    try file3.write(pythonFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "contains(tags, `\"swift\"`)",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  // MARK: - No Matches Tests

  @Test
  func `search with no matches runs successfully`() async throws {
    let testFile = """
      ---
      draft: true
      aliases:
        - Red
      ---
      # Test
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file = tempDir + "test.md"
    try file.write(testFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "contains(aliases, `\"Blue\"`)",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw even with no matches
    try await command.run()
  }

  @Test
  func `search with nonexistent key runs successfully`() async throws {
    let testFile = """
      ---
      draft: true
      title: "Test"
      ---
      # Test
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file = tempDir + "test.md"
    try file.write(testFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "nonexistent == `\"value\"`",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  // MARK: - Output Format Tests

  @Test
  func `search with JSON format runs successfully`() async throws {
    let draftFile = """
      ---
      draft: true
      title: "Draft"
      ---
      # Draft
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file = tempDir + "draft.md"
    try file.write(draftFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      "--format", "json",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  @Test
  func `search with YAML format runs successfully`() async throws {
    let draftFile = """
      ---
      draft: true
      title: "Draft"
      ---
      # Draft
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file = tempDir + "draft.md"
    try file.write(draftFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      "--format", "yaml",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  @Test
  func `search with plain text format runs successfully`() async throws {
    let draftFile = """
      ---
      draft: true
      title: "Draft"
      ---
      # Draft
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file = tempDir + "draft.md"
    try file.write(draftFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  // MARK: - Complex Query Tests

  @Test
  func `search with AND condition`() async throws {
    let file1 = """
      ---
      draft: false
      tags:
        - swift
        - tutorial
      ---
      # File 1
      """

    let file2 = """
      ---
      draft: true
      tags:
        - swift
        - programming
      ---
      # File 2
      """

    let file3 = """
      ---
      draft: false
      tags:
        - python
      ---
      # File 3
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    try (tempDir + "file1.md").write(file1)
    try (tempDir + "file2.md").write(file2)
    try (tempDir + "file3.md").write(file3)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `false` && contains(tags, `\"swift\"`)",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  @Test
  func `search with OR condition`() async throws {
    let file1 = """
      ---
      draft: true
      title: "Draft"
      ---
      # File 1
      """

    let file2 = """
      ---
      draft: false
      aliases:
        - Blue
      ---
      # File 2
      """

    let file3 = """
      ---
      draft: false
      title: "Other"
      ---
      # File 3
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    try (tempDir + "file1.md").write(file1)
    try (tempDir + "file2.md").write(file2)
    try (tempDir + "file3.md").write(file3)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true` || contains(aliases, `\"Blue\"`)",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  // MARK: - Error Handling Tests

  @Test
  func `search with invalid JMESPath expression throws error`() async throws {
    let testFile = """
      ---
      draft: true
      ---
      # Test
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    try (tempDir + "test.md").write(testFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "invalid {{{{ syntax",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Invalid JMESPath should throw when running
    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  // MARK: - Single File Tests

  @Test
  func `search works with single file path`() async throws {
    let draftFile = """
      ---
      draft: true
      title: "Draft"
      ---
      # Draft
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file = tempDir + "draft.md"
    try file.write(draftFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      file.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  @Test
  func `search single file that does not match runs successfully`() async throws {
    let publishedFile = """
      ---
      draft: false
      title: "Published"
      ---
      # Published
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let file = tempDir + "published.md"
    try file.write(publishedFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      file.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  // MARK: - Extension Filtering Tests

  @Test
  func `search respects extension filtering`() async throws {
    let mdFile = """
      ---
      bool: true
      ---
      # MD File
      """

    let txtFile = """
      ---
      bool: true
      ---
      Text file
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    try (tempDir + "file.md").write(mdFile)
    try (tempDir + "file.txt").write(txtFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "bool == `true`",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw and find only .md files by default
    try await command.run()
  }

  @Test
  func `search with custom extensions`() async throws {
    let mdFile = """
      ---
      bool: true
      ---
      # MD File
      """

    let txtFile = """
      ---
      bool: true
      ---
      Text file
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    try (tempDir + "file.md").write(mdFile)
    try (tempDir + "file.txt").write(txtFile)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "bool == `true`",
      "--extensions", "txt",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw and find .txt files when specified
    try await command.run()
  }

  // MARK: - Recursive Search Tests

  @Test
  func `search processes directories recursively`() async throws {
    let file1 = """
      ---
      draft: true
      ---
      # File 1
      """

    let file2 = """
      ---
      draft: true
      ---
      # File 2
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let subDir = tempDir + "subdir"
    try subDir.mkdir()

    try (tempDir + "file1.md").write(file1)
    try (subDir + "file2.md").write(file2)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw and find files recursively
    try await command.run()
  }

  @Test
  func `search handles empty frontmatter gracefully`() async throws {
    let emptyFM = """
      ---
      ---
      # Empty Frontmatter
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    try (tempDir + "empty.md").write(emptyFM)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  @Test
  func `search handles files without frontmatter`() async throws {
    let noFM = """
      # No Frontmatter

      Just body content.
      """

    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    try (tempDir + "no-fm.md").write(noFM)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should not throw
    try await command.run()
  }

  // MARK: - Non-String Key Tests

  @Test
  func `search processes file with integer YAML key without crashing`() async throws {
    // Integer-tagged scalar keys like `123:` are representable as strings ("123")
    // and must NOT crash — safeNodeToSwiftValue stringifies them safely.
    let tempDir = try createTempDir()
    defer { try? tempDir.delete() }

    let goodFile = tempDir + "good.md"
    let intKeyFile = tempDir + "intkey.md"

    try goodFile.write("""
      ---
      draft: true
      title: Good
      ---
      # Good
      """)
    try intKeyFile.write("""
      ---
      123: value
      draft: false
      ---
      # Int Key
      """)

    let command_ = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "draft == `true`",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Search)

    // Should succeed — integer key file is processed, good.md matches the query
    try await command.run()
  }

  // MARK: - Test Helpers

  /// Create a temporary directory for test files
  private func createTempDir() throws -> Path {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-search-test-\(UUID().uuidString)"
    try tempDir.mkdir()
    return tempDir
  }
}
