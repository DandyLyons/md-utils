import Foundation
import PathKit
import Testing
@testable import md_utils

struct BacklinksCommandsTests {
  @Test(.bug("https://github.com/DandyLyons/md-utils/issues/197"), arguments: [false, true])
  func perTargetAttribution(directorySelection: Bool) throws {
    let root = Path(#filePath).parent().parent().parent().parent() + "tmp/backlinks-\(UUID().uuidString)/"
    defer { try? root.delete() }
    try (root + "targets/").mkpath()
    try (root + "sources/").mkpath()
    for (name, content) in [
      ("targets/A.md", "[[A]] [[B]]"),
      ("targets/B.md", "[[B]] [[A]]"),
      ("targets/Empty.md", "[[Empty]]"),
      ("sources/OnlyA.md", "[[A]]"),
      ("sources/OnlyB.md", "[[B]]"),
      ("sources/Both.md", "[[A]] [[B]] [[A]]"),
    ] {
      try (root + name).write(content)
    }
    let targets = ["A", "B", "Empty"].map { (root + "targets/\($0).md").string }
    let selection = directorySelection ? [(root + "targets/").string] : targets
    let arguments = ["links", "backlinks", "--root", root.string] + selection
    let result = try CLIProcessTestHelper.run(arguments + ["--json"])
    try #require(result.status == 0)
    let rows = try JSONDecoder().decode([BacklinkEntry].self, from: Data(result.standardOutput.utf8))
    #expect(Set(rows.map(\.target)) == Set(targets))
    let text = try CLIProcessTestHelper.run(arguments)
    try #require(text.status == 0)
    for row in rows {
      let name = Path(row.target).lastComponentWithoutExtension
      let actual = Dictionary(uniqueKeysWithValues: row.backlinks.map { ($0.file, $0.links) })
      let expected: [String: [String]] = name == "Empty" ? [:] : [
        (root + "sources/Only\(name).md").string: [name],
        (root + "sources/Both.md").string: name == "A" ? ["A", "A"] : ["B"],
        (root + "targets/\(name == "A" ? "B" : "A").md").string: [name],
      ]
      #expect(actual == expected)
      let single = try CLIProcessTestHelper.run([
        "links", "backlinks", "--root", root.string, row.target, "--json",
      ])
      try #require(single.status == 0)
      let singleRow = try #require(JSONDecoder().decode(
        [BacklinkEntry].self, from: Data(single.standardOutput.utf8),
      ).first)
      #expect(Dictionary(uniqueKeysWithValues: singleRow.backlinks.map { ($0.file, $0.links) }) == expected)
      let section = try #require(text.standardOutput.components(separatedBy: "==> \(row.target) <==\n").dropFirst().first)
        .components(separatedBy: "\n\n")[0]
      let expectedLines = expected.map { file, links in
        "  \(file) via \(links.map { "[[\($0)]]" }.joined(separator: ", "))"
      }
      #expect(Set(section.components(separatedBy: "\n")) == Set(expectedLines.isEmpty ? ["  (no backlinks)"] : expectedLines))
    }
  }
}
