import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("Section Get/Set CLI Tests")
struct SectionGetSetTests {

  private func createTestFile(content: String) throws -> Path {
    let tempDir = Path.temporary
    let testFile = tempDir + "test-\(UUID().uuidString).md"
    try testFile.write(content)
    return testFile
  }

  private func cleanup(file: Path) {
    try? file.delete()
  }

  // MARK: - Command Configuration Tests

  @Test
  func `Section command group includes get and set`() {
    let config = CLIEntry.SectionCommands.configuration

    #expect(config.subcommands.count == 5)
    #expect(config.subcommands[0] is CLIEntry.GetSection.Type)
    #expect(config.subcommands[1] is CLIEntry.SetSection.Type)
  }

  @Test
  func `Get command has correct configuration`() {
    let config = CLIEntry.GetSection.configuration
    #expect(config.commandName == "get")
  }

  @Test
  func `Set command has correct configuration`() {
    let config = CLIEntry.SetSection.configuration
    #expect(config.commandName == "set")
  }

  // MARK: - Get Argument Parsing Tests

  @Test
  func `Get parses index argument`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(["section", "get", "--index", "1", testFile.string])
    let cmd = try #require(cmd_ as? CLIEntry.GetSection)

    #expect(cmd.index == 1)
    #expect(cmd.name == nil)
  }

  @Test
  func `Get parses name argument`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(["section", "get", "--name", "Test", testFile.string])
    let cmd = try #require(cmd_ as? CLIEntry.GetSection)

    #expect(cmd.name == "Test")
    #expect(cmd.index == nil)
  }

  @Test
  func `Get parses case-sensitive flag`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "get", "--name", "Test", "--case-sensitive", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.GetSection)

    #expect(cmd.caseSensitive == true)
  }

  @Test
  func `Get parses output option`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "get", "--index", "1", "--output", "/tmp/out.md", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.GetSection)

    #expect(cmd.output == Path("/tmp/out.md"))
  }

  // MARK: - Set Argument Parsing Tests

  @Test
  func `Set parses index argument`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(["section", "set", "--index", "1", testFile.string])
    let cmd = try #require(cmd_ as? CLIEntry.SetSection)

    #expect(cmd.index == 1)
    #expect(cmd.name == nil)
  }

  @Test
  func `Set parses name argument`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(["section", "set", "--name", "Test", testFile.string])
    let cmd = try #require(cmd_ as? CLIEntry.SetSection)

    #expect(cmd.name == "Test")
    #expect(cmd.index == nil)
  }

  @Test
  func `Set parses in-place flag`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "set", "--index", "1", "--in-place", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.SetSection)

    #expect(cmd.inPlace == true)
  }

  @Test
  func `Set parses input option`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "set", "--index", "1", "--input", "/tmp/replacement.md", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.SetSection)

    #expect(cmd.input == Path("/tmp/replacement.md"))
  }

  @Test
  func `Set parses case-sensitive flag`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "set", "--name", "Test", "--case-sensitive", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.SetSection)

    #expect(cmd.caseSensitive == true)
  }
}
