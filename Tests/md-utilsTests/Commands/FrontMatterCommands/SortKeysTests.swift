//
//  SortKeysTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("fm sort-keys command")
struct SortKeysTests {

  @Test
  func `fm sort-keys sorts alphabetically by default`() async throws {
    let testContent = """
    ---
    zebra: last
    title: Test Document
    author: Jane Doe
    date: 2024-01-15
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify the keys are sorted alphabetically
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    // Get keys in the order they appear
    let keys = Array(doc.frontMatter.keys).compactMap { $0.string }

    #expect(keys == ["author", "date", "title", "zebra"])

    // Verify values are preserved
    #expect(doc.getValue(forKey: "title")?.string == "Test Document")
    #expect(doc.getValue(forKey: "author")?.string == "Jane Doe")
    #expect(doc.getValue(forKey: "date")?.string == "2024-01-15")
    #expect(doc.getValue(forKey: "zebra")?.string == "last")
  }

  @Test
  func `fm sort-keys with reverse flag`() async throws {
    let testContent = """
    ---
    author: Jane
    title: Test
    zebra: Last
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      "--reverse",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify the keys are sorted in reverse alphabetical order
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    let keys = Array(doc.frontMatter.keys).compactMap { $0.string }

    #expect(keys == ["zebra", "title", "author"])
  }

  @Test
  func `fm sort-keys with short method flag`() async throws {
    let testContent = """
    ---
    abc: value1
    ab: value2
    a: value3
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      "-m", "length",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    let keys = Array(doc.frontMatter.keys).compactMap { $0.string }
    #expect(keys == ["a", "ab", "abc"])
  }

  @Test
  func `fm sort-keys by length`() async throws {
    let testContent = """
    ---
    very_long_key_name: value1
    short: value2
    mid_length: value3
    a: value4
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      "--method", "length",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify the keys are sorted by length
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    let keys = Array(doc.frontMatter.keys).compactMap { $0.string }

    #expect(keys == ["a", "short", "mid_length", "very_long_key_name"])

    // Verify values are preserved
    #expect(doc.getValue(forKey: "very_long_key_name")?.string == "value1")
    #expect(doc.getValue(forKey: "short")?.string == "value2")
    #expect(doc.getValue(forKey: "mid_length")?.string == "value3")
    #expect(doc.getValue(forKey: "a")?.string == "value4")
  }

  @Test
  func `fm sort-keys by length reversed`() async throws {
    let testContent = """
    ---
    a: value1
    abc: value2
    ab: value3
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      "--method", "length",
      "--reverse",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    let keys = Array(doc.frontMatter.keys).compactMap { $0.string }
    #expect(keys == ["abc", "ab", "a"])
  }

  @Test
  func `fm sort-keys preserves body content`() async throws {
    let bodyContent = "# Important Heading\n\nThis is critical content.\n"
    let testContent = """
    ---
    z: last
    a: first
    m: middle
    ---
    \(bodyContent)
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify body is preserved
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.body == bodyContent)
  }

  @Test
  func `fm sort-keys preserves complex values`() async throws {
    let testContent = """
    ---
    zebra:
      - item1
      - item2
      - item3
    metadata:
      created: 2024-01-01
      updated: 2024-01-15
    author: Jane Doe
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify the complex structures are preserved
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    let keys = Array(doc.frontMatter.keys).compactMap { $0.string }
    #expect(keys == ["author", "metadata", "zebra"])

    // Verify array was preserved
    let zebraArray = doc.getValue(forKey: "zebra")
    #expect(zebraArray != nil)
    #expect(zebraArray?.sequence?.count == 3)

    // Verify mapping was preserved
    let metadata = doc.getValue(forKey: "metadata")
    #expect(metadata != nil)
    #expect(metadata?.mapping != nil)
  }

  @Test
  func `fm sort-keys processes multiple files`() async throws {
    let content1 = """
    ---
    z: last
    a: first
    m: middle
    ---
    Body 1
    """

    let content2 = """
    ---
    title: Doc 2
    author: Jane
    date: 2024-01-15
    ---
    Body 2
    """

    let file1 = try createTempFile(content: content1, name: "doc1.md")
    let file2 = try createTempFile(content: content2, name: "doc2.md")
    defer {
      try? file1.delete()
      try? file2.delete()
    }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      file1.string,
      file2.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify both files were sorted
    let doc1 = try MarkdownDocument(content: try file1.read())
    let doc2 = try MarkdownDocument(content: try file2.read())

    let keys1 = Array(doc1.frontMatter.keys).compactMap { $0.string }
    let keys2 = Array(doc2.frontMatter.keys).compactMap { $0.string }

    #expect(keys1 == ["a", "m", "z"])
    #expect(keys2 == ["author", "date", "title"])
  }

  @Test
  func `fm sort-keys with directory recursion`() async throws {
    // Create temporary directory structure
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkdir()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "doc1.md"
    let file2 = tempDir + "doc2.md"

    let content = """
    ---
    z: last
    a: first
    m: middle
    ---
    Body
    """

    try file1.write(content)
    try file2.write(content)

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify both files were sorted
    let doc1 = try MarkdownDocument(content: try file1.read())
    let doc2 = try MarkdownDocument(content: try file2.read())

    let keys1 = Array(doc1.frontMatter.keys).compactMap { $0.string }
    let keys2 = Array(doc2.frontMatter.keys).compactMap { $0.string }

    #expect(keys1 == ["a", "m", "z"])
    #expect(keys2 == ["a", "m", "z"])
  }

  @Test
  func `fm sort-keys handles numeric and boolean values`() async throws {
    let testContent = """
    ---
    count: 42
    price: 19.99
    active: true
    disabled: false
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify values are preserved with correct types
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    let keys = Array(doc.frontMatter.keys).compactMap { $0.string }
    #expect(keys == ["active", "count", "disabled", "price"])

    #expect(doc.getValue(forKey: "count")?.int == 42)
    #expect(doc.getValue(forKey: "price")?.float == 19.99)
    #expect(doc.getValue(forKey: "active")?.bool == true)
    #expect(doc.getValue(forKey: "disabled")?.bool == false)
  }

  @Test
  func `fm sort-keys works with alias sk`() async throws {
    let testContent = """
    ---
    z: last
    a: first
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    // The alias is configured in the command configuration
    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify it worked
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    let keys = Array(doc.frontMatter.keys).compactMap { $0.string }
    #expect(keys == ["a", "z"])
  }

  @Test
  func `fm sort-keys handles empty frontmatter gracefully`() async throws {
    let testContent = """
    ---
    ---
    Body content only
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify file is unchanged
    let updatedContent: String = try tempFile.read()
    #expect(updatedContent.contains("Body content only"))
  }

  @Test
  func `fm sort-keys handles document without frontmatter`() async throws {
    let testContent = "# Just a heading\n\nNo frontmatter here."

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.SortKeys.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.SortKeys)

    try await command.run()

    // Verify file is unchanged
    let updatedContent: String = try tempFile.read()
    #expect(updatedContent == testContent)
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
