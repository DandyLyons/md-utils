//
//  ReplaceTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("fm replace command")
struct ReplaceTests {

  @Test
  func `fm replace with inline JSON data`() async throws {
    let testContent = """
    ---
    title: Original Title
    author: Jane Doe
    draft: true
    ---
    # My Document

    This is the body content.
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let jsonData = """
    {"title": "New Title", "status": "published"}
    """

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", jsonData,
      "--format", "json",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    try await command.run()

    // Verify the frontmatter was replaced
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.getValue(forKey: "title")?.string == "New Title")
    #expect(doc.getValue(forKey: "status")?.string == "published")
    // Old keys should be gone
    #expect(doc.getValue(forKey: "author") == nil)
    #expect(doc.getValue(forKey: "draft") == nil)
  }

  @Test
  func `fm replace with inline YAML data`() async throws {
    let testContent = """
    ---
    old_key: old_value
    ---
    Body content
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let yamlData = """
    title: YAML Title
    category: tutorial
    tags:
      - swift
      - markdown
    """

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", yamlData,
      "--format", "yaml",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    try await command.run()

    // Verify the frontmatter was replaced
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.getValue(forKey: "title")?.string == "YAML Title")
    #expect(doc.getValue(forKey: "category")?.string == "tutorial")
    #expect(doc.getValue(forKey: "old_key") == nil)
  }

  @Test
  func `fm replace from file`() async throws {
    let testContent = """
    ---
    title: Original
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    // Create a file with new frontmatter
    let frontmatterData = """
    {
      "title": "From File",
      "author": "Test Author",
      "version": 2
    }
    """
    let dataFile = try createTempFile(content: frontmatterData, name: "frontmatter.json")
    defer { try? dataFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--from-file", dataFile.string,
      "--format", "json",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    try await command.run()

    // Verify the frontmatter was replaced
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.getValue(forKey: "title")?.string == "From File")
    #expect(doc.getValue(forKey: "author")?.string == "Test Author")
    #expect(doc.getValue(forKey: "version")?.string == "2")
  }

  @Test
  func `fm replace preserves body content`() async throws {
    let bodyContent = """
    # Important Heading

    This is critical content that must not be lost.

    ## Subheading

    More content here.
    """

    let testContent = """
    ---
    title: Original
    ---
    \(bodyContent)
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let jsonData = """
    {"title": "New Title"}
    """

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", jsonData,
      "--format", "json",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    try await command.run()

    // Verify body is preserved exactly
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.body == bodyContent)
  }

  @Test
  func `fm replace processes multiple files`() async throws {
    let content1 = """
    ---
    title: Doc 1
    type: old
    ---
    Body 1
    """

    let content2 = """
    ---
    title: Doc 2
    type: old
    ---
    Body 2
    """

    let file1 = try createTempFile(content: content1, name: "doc1.md")
    let file2 = try createTempFile(content: content2, name: "doc2.md")
    defer {
      try? file1.delete()
      try? file2.delete()
    }

    let jsonData = """
    {"category": "tutorial", "status": "published"}
    """

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", jsonData,
      "--format", "json",
      "--yes",
      file1.string,
      file2.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    try await command.run()

    // Verify both files were updated with same frontmatter
    let doc1 = try MarkdownDocument(content: try file1.read())
    let doc2 = try MarkdownDocument(content: try file2.read())

    #expect(doc1.getValue(forKey: "category")?.string == "tutorial")
    #expect(doc1.getValue(forKey: "status")?.string == "published")
    #expect(doc1.getValue(forKey: "title") == nil)
    #expect(doc1.getValue(forKey: "type") == nil)

    #expect(doc2.getValue(forKey: "category")?.string == "tutorial")
    #expect(doc2.getValue(forKey: "status")?.string == "published")
    #expect(doc2.getValue(forKey: "title") == nil)
    #expect(doc2.getValue(forKey: "type") == nil)
  }

  @Test
  func `fm replace with plist format`() async throws {
    let testContent = """
    ---
    title: Original
    ---
    Body
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let plistData = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>title</key>
      <string>Plist Title</string>
      <key>version</key>
      <integer>3</integer>
    </dict>
    </plist>
    """

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", plistData,
      "--format", "plist",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    try await command.run()

    // Verify the frontmatter was replaced
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.getValue(forKey: "title")?.string == "Plist Title")
    #expect(doc.getValue(forKey: "version")?.string == "3")
  }

  @Test
  func `fm replace validates both data and from-file not allowed`() async throws {
    let tempFile = try createTempFile(content: "Body", name: "test.md")
    defer { try? tempFile.delete() }

    let dataFile = try createTempFile(content: "{}", name: "data.json")
    defer { try? dataFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", "{}",
      "--from-file", dataFile.string,
      "--format", "json",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm replace validates either data or from-file required`() async throws {
    let tempFile = try createTempFile(content: "Body", name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--format", "json",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm replace validates data must be mapping - rejects array`() async throws {
    let tempFile = try createTempFile(content: "Body", name: "test.md")
    defer { try? tempFile.delete() }

    let jsonArray = """
    ["item1", "item2"]
    """

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", jsonArray,
      "--format", "json",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm replace validates data must be mapping - rejects scalar`() async throws {
    let tempFile = try createTempFile(content: "Body", name: "test.md")
    defer { try? tempFile.delete() }

    let jsonScalar = """
    "just a string"
    """

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", jsonScalar,
      "--format", "json",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm replace validates invalid JSON`() async throws {
    let tempFile = try createTempFile(content: "Body", name: "test.md")
    defer { try? tempFile.delete() }

    let invalidJSON = """
    {invalid json}
    """

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", invalidJSON,
      "--format", "json",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `fm replace replaces empty frontmatter with new data`() async throws {
    let testContent = """
    Just body content, no frontmatter.
    """

    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let jsonData = """
    {"title": "Added Title", "draft": false}
    """

    let command_ = try CLIEntry.FrontMatterCommands.Replace.parseAsRoot([
      "--data", jsonData,
      "--format", "json",
      "--yes",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Replace)

    try await command.run()

    // Verify frontmatter was added
    let updatedContent: String = try tempFile.read()
    let doc = try MarkdownDocument(content: updatedContent)

    #expect(doc.getValue(forKey: "title")?.string == "Added Title")
    #expect(doc.getValue(forKey: "draft")?.string == "false")
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
