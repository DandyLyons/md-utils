import Foundation
import PathKit
import Testing
@testable import md_utils

struct WikilinkResolutionCommandsTests {
  @Test
  func `list check and backlinks share explicit path semantics`() throws {
    let root = Path(#filePath).parent().parent().parent().parent() + "tmp/link-resolution-\(UUID().uuidString)/"
    defer { try? root.delete() }
    for name in ["About/Daniel Lyons.md", "notes/About/Daniel Lyons.md", "notes/Local/Daniel Lyons.md"] {
      let file = root + name
      try file.parent().mkpath()
      try file.write("")
    }
    let source = root + "notes/source.md"
    let targets = [
      "About/Daniel Lyons.md", "About/Daniel Lyons", "./About/Daniel Lyons",
      "../About/Daniel Lyons", "Local/Daniel Lyons", "Daniel Lyons",
    ]
    try source.write(targets.map { "[[\($0)]]" }.joined(separator: "\n"))
    let list = try CLIProcessTestHelper.run(["links", "list", "--root", root.string, "--json", source.string])
    #expect(list.status == 0)
    let entries = try JSONDecoder().decode([FileLinksEntry].self, from: Data(list.standardOutput.utf8))
    let links = try #require(entries.first).links
    #expect(links.map(\.status) == ["resolved", "resolved", "resolved", "resolved", "unresolved", "ambiguous"])
    #expect(links.prefix(4).map(\.resolvedPath) == [
      (root + "About/Daniel Lyons.md").string, (root + "About/Daniel Lyons.md").string,
      (root + "notes/About/Daniel Lyons.md").string, (root + "About/Daniel Lyons.md").string,
    ])

    let check = try CLIProcessTestHelper.run(["links", "check", "--root", root.string, "--json", source.string])
    #expect(check.status != 0)
    let report = try JSONDecoder().decode(CheckReport.self, from: Data(check.standardOutput.utf8))
    #expect(report.totalLinks == 6)
    #expect(report.broken == 1)
    #expect(report.ambiguous == 1)
    #expect(report.problems.map(\.target) == ["Local/Daniel Lyons", "Daniel Lyons"])

    for (destination, expected) in [
      ("About/Daniel Lyons.md", [targets[0], targets[1], targets[3]]),
      ("notes/About/Daniel Lyons.md", [targets[2]]),
      ("notes/Local/Daniel Lyons.md", []),
    ] {
      let backlinks = try CLIProcessTestHelper.run([
        "links", "backlinks", "--root", root.string, "--scan-scope", (root + "notes/").string,
        "--json", (root + destination).string,
      ])
      #expect(backlinks.status == 0)
      let rows = try JSONDecoder().decode([BacklinkEntry].self, from: Data(backlinks.standardOutput.utf8))
      let row = try #require(rows.first)
      #expect(row.backlinks.flatMap(\.links) == expected)
      #expect(row.backlinks.map(\.file) == (expected.isEmpty ? [] : [source.string]))
    }
  }
}
