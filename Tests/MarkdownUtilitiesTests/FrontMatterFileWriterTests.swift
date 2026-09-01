import Foundation
import MarkdownUtilities
import PathKit
import Testing

@Suite("Frontmatter file writer")
struct FrontMatterFileWriterTests {
  @Test
  func `atomically writes when the source revision still matches`() throws {
    let fixture = try makeFixture(content: "before\n")
    defer { try? fixture.parent().delete() }

    try FrontMatterFileWriter.write("after\n", to: fixture, expectedSource: "before\n")

    let updated: String = try fixture.read()
    #expect(updated == "after\n")
  }

  @Test
  func `refuses a stale edit and preserves the latest bytes`() throws {
    let fixture = try makeFixture(content: "latest\n")
    defer { try? fixture.parent().delete() }

    #expect(throws: FrontMatterFileWriteError.self) {
      try FrontMatterFileWriter.write("stale edit\n", to: fixture, expectedSource: "older\n")
    }

    let preserved: String = try fixture.read()
    #expect(preserved == "latest\n")
  }

  @Test
  func `snapshot and revision check preserve a UTF-8 BOM`() throws {
    let fixture = try makeFixture(content: "placeholder")
    defer { try? fixture.parent().delete() }
    let original = "\u{FEFF}before\n"
    try Data(original.utf8).write(to: URL(fileURLWithPath: fixture.string))

    let snapshot = try FrontMatterFileWriter.readSnapshot(from: fixture)
    #expect(snapshot == original)
    try FrontMatterFileWriter.write(
      "\u{FEFF}after\n",
      to: fixture,
      expectedSource: snapshot
    )

    #expect(try Data(contentsOf: URL(fileURLWithPath: fixture.string)) == Data("\u{FEFF}after\n".utf8))
  }

  @Test
  func `snapshot rejects invalid UTF-8`() throws {
    let fixture = try makeFixture(content: "placeholder")
    defer { try? fixture.parent().delete() }
    try Data([0xFF, 0xFE, 0xFD]).write(to: URL(fileURLWithPath: fixture.string))

    #expect(throws: FrontMatterFileWriteError.self) {
      _ = try FrontMatterFileWriter.readSnapshot(from: fixture)
    }
  }

  private func makeFixture(content: String) throws -> Path {
    let directory = Path.current + "tmp/frontmatter-file-writer-\(UUID().uuidString)/"
    try directory.mkpath()
    let file = directory + "fixture.swift"
    try content.write(toFile: file.string, atomically: true, encoding: .utf8)
    return file
  }
}
