import ArgumentParser
import Foundation
import PathKit
import Testing
@testable import md_utils

struct ConvertLinksTests {
  @Test
  func `directory discovery skips symlink cycles before planning`() async throws {
    let root = try workspace()
    defer { try? root.delete() }
    try (root + "source.md").write("[[Alice]]")
    try FileManager.default.createSymbolicLink(atPath: (root + "loop").string, withDestinationPath: root.string)
    var convert = try command(["--to", "wiki-path", "--root", root.string, root.string, "--in-place"])
    try await convert.run()
    #expect(try (root + "source.md").read() as String == "[[People/Alice.md]]")
  }

  @Test(arguments: ["auto", "include", "omit"])
  func `CLI forwards Markdown extension policy`(policy: String) async throws {
    let root = try workspace()
    defer { try? root.delete() }
    try (root + "People/Notes.txt").write("")
    let file = root + "source.md"
    try file.write("[[Alice]] [[Notes.txt]]")
    var convert = try command([
      "--to", "wiki-path", "--markdown-extension", policy,
      "--root", root.string, file.string, "--in-place",
    ])
    try await convert.run()
    #expect(try file.read() as String == "[[People/Alice\(policy == "omit" ? "" : ".md")]] [[People/Notes.txt]]")
  }

  @Test
  func `invalid Markdown extension policy is rejected`() async throws {
    var convert = try command(["--to", "wiki-path", "--root", ".", "--markdown-extension", "strip-all"])
    await #expect(throws: ValidationError.self) { try await convert.run() }
  }

  private func workspace() throws -> Path {
    let root = Path(#filePath).parent().parent().parent().parent() + "tmp/convert-cli-\(UUID().uuidString)"
    try (root + "People").mkpath()
    try (root + "People/Alice.md").write("")
    return root
  }

  private func command(_ arguments: [String]) throws -> CLIEntry.ConvertLinks {
    try #require(CLIEntry.parseAsRoot(["links", "convert"] + arguments) as? CLIEntry.ConvertLinks)
  }

  @Test
  func `preview is default and in place preserves no op modification time`() async throws {
    let root = try workspace()
    defer { try? root.delete() }
    let file = root + "source.md"
    try file.write("[[Alice]]")
    let args = ["--to", "wiki-path", "--root", root.string, file.string]
    var preview = try command(args)
    try await preview.run()
    #expect(try file.read() as String == "[[Alice]]")
    var apply = try command(args + ["--in-place"])
    try await apply.run()
    #expect(try file.read() as String == "[[People/Alice.md]]")
    let date = Date(timeIntervalSince1970: 1_000_000)
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.string)
    try await apply.run()
    #expect(try FileManager.default.attributesOfItem(atPath: file.string)[.modificationDate] as? Date == date)
  }

  @Test
  func `required root and unsupported options fail`() async throws {
    #expect(throws: (any Error).self) { try command(["--to", "wiki-path"]) }
    for extra in [["--to", "md-links"], ["--to", "wiki-path", "--key", "related"], ["--to", "wiki-path", "--scope", "invalid"]] {
      var invalid = try command(["--root", "."] + extra)
      await #expect(throws: ValidationError.self) { try await invalid.run() }
    }
  }

  @Test
  func `json batch reports committed failed and unprocessed files`() throws {
    let root = try workspace()
    defer { try? root.delete() }
    try (root + "a.md").write("[[Alice]]")
    try (root + "b.md").write("---\nbad: [\n---\n")
    try (root + "c.md").write("[[Alice]]")
    let result = try CLIProcessTestHelper.run([
      "links", "convert", "--to", "wiki-path", "--root", root.string,
      "--in-place", "--json", (root + "a.md").string, (root + "b.md").string, (root + "c.md").string,
    ])
    #expect(result.status != 0)
    let rows = try #require(JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [[String: Any]])
    #expect(rows.compactMap { $0["status"] as? String } == ["changed", "failed", "unprocessed"])
    #expect(try (root + "a.md").read() as String == "[[People/Alice.md]]")
    #expect(try (root + "c.md").read() as String == "[[Alice]]")
  }

  @Test
  func `selection flags change only selected frontmatter keys`() async throws {
    let root = try workspace()
    defer { try? root.delete() }
    let file = root + "source.md"
    try file.write("---\nrelated: '[[Alice]]'\nother: '[[Alice]]'\n---\n[[Alice]]")
    var convert = try command([
      "--to", "wiki-path", "--root", root.string, file.string,
      "--scope", "frontmatter", "--key", "related", "--key", "missing", "--in-place",
    ])
    try await convert.run()
    let source: String = try file.read()
    #expect(source.contains("[[People/Alice.md]]"))
    #expect(source.components(separatedBy: "[[Alice]]").count == 3)
  }

  @Test
  func `outside inputs fail without writing`() async throws {
    let root = try workspace()
    defer { try? root.delete() }
    let file = root + "source.md"
    try file.write("[[Alice]]")
    var convert = try command([
      "--to", "wiki-path", "--root", (root + "People").string, file.string, "--in-place",
    ])
    await #expect(throws: ExitCode.failure) { try await convert.run() }
    #expect(try file.read() as String == "[[Alice]]")
  }

  @Test
  func `json preview reports skipped links without failing or writing`() throws {
    let root = try workspace()
    defer { try? root.delete() }
    let file = root + "source.md"
    let source = "[[Alice]] [[Missing]]"
    try file.write(source)
    let result = try CLIProcessTestHelper.run([
      "links", "convert", "--to", "wiki-path", "--root", root.string, "--json", file.string,
    ])
    #expect(result.status == 0)
    let rows = try #require(JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [[String: Any]])
    let row = try #require(rows.first)
    #expect(row["status"] as? String == "would-change")
    let changes = try #require(row["changes"] as? [[String: String]])
    #expect(changes.first?["replacement"] == "[[People/Alice.md]]")
    #expect(changes.last?["diagnostic"] == "unresolved target")
    #expect(try file.read() as String == source)
  }
}
