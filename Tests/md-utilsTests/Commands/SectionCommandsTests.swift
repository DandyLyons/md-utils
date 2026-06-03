import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("SectionCommands CLI Tests")
struct SectionCommandsTests {

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
  func `Section command group has correct configuration`() {
    let config = CLIEntry.SectionCommands.configuration

    #expect(config.commandName == "section")
    #expect(config.subcommands.count == 6)
    #expect(config.subcommands[0] is CLIEntry.ListSections.Type)
    #expect(config.subcommands[1] is CLIEntry.GetSection.Type)
    #expect(config.subcommands[2] is CLIEntry.SetSection.Type)
    #expect(config.subcommands[3] is CLIEntry.MoveSectionUp.Type)
    #expect(config.subcommands[4] is CLIEntry.MoveSectionDown.Type)
    #expect(config.subcommands[5] is CLIEntry.MoveSectionTo.Type)
  }

  @Test
  func `List command has correct configuration`() {
    let config = CLIEntry.ListSections.configuration
    #expect(config.commandName == "list")
  }

  @Test
  func `List parses GenerateTOC options`() throws {
    let testFile = try createTestFile(content: "# Test\n## Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot([
      "section", "list", testFile.string,
      "--min-level", "2",
      "--max-level", "4",
      "--flat",
      "--no-slugs",
      "--format", "plain",
    ])
    let cmd = try #require(cmd_ as? CLIEntry.ListSections)

    #expect(cmd.toc.options.paths.count == 1)
    #expect(cmd.toc.minLevel == 2)
    #expect(cmd.toc.maxLevel == 4)
    #expect(cmd.toc.flat == true)
    #expect(cmd.toc.noSlugs == true)
    #expect(cmd.toc.format == .plain)
  }

  @Test
  func `List alias parses`() throws {
    let testFile = try createTestFile(content: "# Test")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(["section", "ls", testFile.string])
    _ = try #require(cmd_ as? CLIEntry.ListSections)
  }

  @Test
  func `Move-up command has correct configuration`() {
    let config = CLIEntry.MoveSectionUp.configuration
    #expect(config.commandName == "move-up")
  }

  @Test
  func `Move-down command has correct configuration`() {
    let config = CLIEntry.MoveSectionDown.configuration
    #expect(config.commandName == "move-down")
  }

  @Test
  func `Move-to command has correct configuration`() {
    let config = CLIEntry.MoveSectionTo.configuration
    #expect(config.commandName == "move-to")
  }

  // MARK: - Argument Parsing Tests

  @Test
  func `Move-up parses index argument`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(["section", "move-up", "--index", "2", testFile.string])
    let cmd = try #require(cmd_ as? CLIEntry.MoveSectionUp)

    #expect(cmd.index == 2)
    #expect(cmd.name == nil)
    #expect(cmd.inPlace == false)
  }

  @Test
  func `Move-down parses name argument`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "move-down", "--name", "Other", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.MoveSectionDown)

    #expect(cmd.name == "Other")
    #expect(cmd.index == nil)
  }

  @Test
  func `Move-to parses position argument`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "move-to", "--index", "1", "--position", "2", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.MoveSectionTo)

    #expect(cmd.index == 1)
    #expect(cmd.position == 2)
  }

  @Test
  func `Move-up parses in-place flag`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "move-up", "--index", "2", "--in-place", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.MoveSectionUp)

    #expect(cmd.inPlace == true)
  }

  @Test
  func `Move-up parses case-sensitive flag`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "move-up", "--name", "Other", "--case-sensitive", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.MoveSectionUp)

    #expect(cmd.caseSensitive == true)
  }

  // MARK: - Count Argument Tests

  @Test
  func `Move-up parses count argument`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other\n# Third")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "move-up", "--index", "3", "--count", "2", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.MoveSectionUp)

    #expect(cmd.count == 2)
  }

  @Test
  func `Move-down parses count argument`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other\n# Third")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "move-down", "--index", "1", "--count", "2", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.MoveSectionDown)

    #expect(cmd.count == 2)
  }

  @Test
  func `Move-up count defaults to 1`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "move-up", "--index", "2", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.MoveSectionUp)

    #expect(cmd.count == 1)
  }

  @Test
  func `Move-up parses short count flag`() throws {
    let testFile = try createTestFile(content: "# Test\n# Other\n# Third")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot(
      ["section", "move-up", "--index", "3", "-c", "2", testFile.string]
    )
    let cmd = try #require(cmd_ as? CLIEntry.MoveSectionUp)

    #expect(cmd.count == 2)
  }
}
