import Testing
import Foundation
import PathKit
@testable import md_utils

@Suite("Section Insert/Remove CLI Tests")
struct SectionInsertRemoveTests {
  private func createTestFile(content: String) throws -> Path {
    let tempDir = Path.temporary
    let testFile = tempDir + "test-\(UUID().uuidString).md"
    try testFile.write(content)
    return testFile
  }

  private func cleanup(file: Path) {
    try? file.delete()
  }

  @Test
  func `Insert command parses contents source`() throws {
    let testFile = try createTestFile(content: "# Old")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot([
      "section", "insert",
      "--name", "New Section",
      "--into", testFile.string,
      "--after", "Old",
      "--contents", "Body text.",
    ])
    let cmd = try #require(cmd_ as? CLIEntry.InsertSection)

    #expect(cmd.name == "New Section")
    #expect(cmd.into == testFile)
    #expect(cmd.after == "Old")
    #expect(cmd.contents == "Body text.")
  }

  @Test
  func `Insert command parses from-file and after-index alias`() throws {
    let testFile = try createTestFile(content: "# Old")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot([
      "section", "insert",
      "--name", "New Section",
      "--into", testFile.string,
      "--afterI", "1",
      "--from-file", "new-section.txt",
      "--in-place",
      "--dry-run",
    ])
    let cmd = try #require(cmd_ as? CLIEntry.InsertSection)

    #expect(cmd.afterIndex == 1)
    #expect(cmd.fromFile == Path("new-section.txt"))
    #expect(cmd.inPlace == true)
    #expect(cmd.dryRun == true)
  }

  @Test
  func `Insert command parses before-index alias`() throws {
    let testFile = try createTestFile(content: "# Old")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot([
      "section", "insert",
      "--name", "New Section",
      "--into", testFile.string,
      "--beforeI", "1",
      "--contents", "Body text.",
    ])
    let cmd = try #require(cmd_ as? CLIEntry.InsertSection)

    #expect(cmd.beforeIndex == 1)
  }

  @Test
  func `Remove command parses name target`() throws {
    let testFile = try createTestFile(content: "# Old")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot([
      "section", "remove",
      "--into", testFile.string,
      "--name", "Old",
      "--case-sensitive",
    ])
    let cmd = try #require(cmd_ as? CLIEntry.RemoveSection)

    #expect(cmd.into == testFile)
    #expect(cmd.name == "Old")
    #expect(cmd.caseSensitive == true)
  }

  @Test
  func `Remove command parses index target and dry-run`() throws {
    let testFile = try createTestFile(content: "# Old")
    defer { cleanup(file: testFile) }

    let cmd_ = try CLIEntry.parseAsRoot([
      "section", "remove",
      "--into", testFile.string,
      "--index", "1",
      "--dry-run",
    ])
    let cmd = try #require(cmd_ as? CLIEntry.RemoveSection)

    #expect(cmd.index == 1)
    #expect(cmd.dryRun == true)
  }
}
