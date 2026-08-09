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

  private func makeFixture(content: String) throws -> Path {
    let directory = Path.current + "tmp/frontmatter-file-writer-\(UUID().uuidString)/"
    try directory.mkpath()
    let file = directory + "fixture.swift"
    try content.write(toFile: file.string, atomically: true, encoding: .utf8)
    return file
  }
}
