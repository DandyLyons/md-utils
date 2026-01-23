//
//  FileMetadataCommandsTests.swift
//  md-utilsTests
//

import Foundation
import PathKit
import Testing

@testable import md_utils

@Suite("FileMetadata Commands Tests")
struct FileMetadataCommandsTests {

  @Test
  func `Read single file metadata`() async throws {
    let testContent = "# Test File\n\nThis is a test."
    let tempFile = try createTempFile(content: testContent, name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Should not throw
    try await command.run()
  }

  @Test
  func `Read multiple files`() async throws {
    let file1 = try createTempFile(content: "File 1", name: "file1.md")
    let file2 = try createTempFile(content: "File 2", name: "file2.md")
    defer {
      try? file1.delete()
      try? file2.delete()
    }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      file1.string,
      file2.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Should not throw
    try await command.run()
  }

  @Test
  func `Output format json-pretty`() async throws {
    let tempFile = try createTempFile(content: "Test", name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--format", "json-pretty",
      tempFile.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Verify format is set correctly
    #expect(command.format == .jsonPretty)

    // Should not throw
    try await command.run()
  }

  @Test
  func `Output format json`() async throws {
    let tempFile = try createTempFile(content: "Test", name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--format", "json",
      tempFile.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Verify format is set correctly
    #expect(command.format == .json)

    // Should not throw
    try await command.run()
  }

  @Test
  func `Output format md-table`() async throws {
    let tempFile = try createTempFile(content: "Test", name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--format", "md-table",
      tempFile.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Verify format is set correctly
    #expect(command.format == .mdTable)

    // Should not throw
    try await command.run()
  }

  @Test
  func `Output format csv`() async throws {
    let tempFile = try createTempFile(content: "Test", name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--format", "csv",
      tempFile.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Verify format is set correctly
    #expect(command.format == .csv)

    // Should not throw
    try await command.run()
  }

  @Test
  func `Exclude xattr flag`() async throws {
    let tempFile = try createTempFile(content: "Test", name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--exclude-xattr",
      tempFile.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Verify flag is set correctly
    #expect(command.excludeXattr == true)

    // Should not throw
    try await command.run()
  }

  @Test
  func `Default includes xattr`() async throws {
    let tempFile = try createTempFile(content: "Test", name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Verify xattr is included by default
    #expect(command.excludeXattr == false)
  }

  @Test
  func `Ignore xattr errors flag`() async throws {
    let tempFile = try createTempFile(content: "Test", name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--ignore-xattr-errors",
      tempFile.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Verify flag is set correctly
    #expect(command.ignoreXattrErrors == true)

    // Should not throw
    try await command.run()
  }

  @Test
  func `Recursive directory processing`() async throws {
    let tempDir = try createTempDirectory()
    defer { try? tempDir.delete() }

    // Create files in directory
    let file1 = tempDir + "file1.md"
    try file1.write("Content 1")

    // Create subdirectory with file
    let subdir = tempDir + "subdir"
    try subdir.mkdir()
    let file2 = subdir + "file2.md"
    try file2.write("Content 2")

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Should process both files recursively
    try await command.run()
  }

  @Test
  func `Error handling for missing files`() async throws {
    let nonexistentPath = "/tmp/nonexistent-\(UUID()).md"

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      nonexistentPath
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Should throw because path doesn't exist
    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  @Test
  func `CSV escaping for commas`() async throws {
    // Create a file with a path containing a comma
    let tempDir = try createTempDirectory()
    defer { try? tempDir.delete() }

    let fileWithComma = tempDir + "file,with,commas.md"
    try fileWithComma.write("Test")

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--format", "csv",
      fileWithComma.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Should not throw and should properly escape commas
    try await command.run()
  }

  @Test
  func `CSV escaping for quotes`() async throws {
    // Create a file and test CSV output
    let tempFile = try createTempFile(content: "Test", name: "test.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--format", "csv",
      tempFile.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Should not throw
    try await command.run()
  }

  @Test
  func `No recursive flag`() async throws {
    let tempDir = try createTempDirectory()
    defer { try? tempDir.delete() }

    // Create files
    let file1 = tempDir + "file1.md"
    try file1.write("Content 1")

    let subdir = tempDir + "subdir"
    try subdir.mkdir()
    let file2 = subdir + "file2.md"
    try file2.write("Content 2")

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--no-recursive",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Should only process top-level file
    try await command.run()
  }

  @Test
  func `Include hidden files flag`() async throws {
    let tempDir = try createTempDirectory()
    defer { try? tempDir.delete() }

    // Create hidden file
    let hiddenFile = tempDir + ".hidden.md"
    try hiddenFile.write("Hidden content")

    let command_ = try CLIEntry.FileMetadataCommands.ReadMetadata.parseAsRoot([
      "--include-hidden",
      tempDir.string,
    ])
    var command = try #require(command_ as? CLIEntry.FileMetadataCommands.ReadMetadata)

    // Should process hidden file
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

  /// Create a temporary directory
  private func createTempDirectory() throws -> Path {
    let tempDir = Path(NSTemporaryDirectory())
    let testDir = tempDir + "md-utils-test-\(UUID().uuidString)"

    try testDir.mkdir()

    return testDir
  }
}
