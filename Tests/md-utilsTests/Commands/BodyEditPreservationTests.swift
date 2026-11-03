import ArgumentParser
import Foundation
import PathKit
import Testing
@testable import md_utils

struct BodyEditPreservationTests {
  @Test(arguments: [
    "---\ndate: 2026-10-01 # keep comment\nz: 'quoted'\na: [one, two]\n---\n",
    "+++\ndate = 2026-10-01 # keep comment\nz = 'quoted'\na = [1, 2]\n+++\n",
    "---\ninvalid: [\n---\n",
    "+++\ninvalid = [\n+++\n",
    "---\n---\n",
    "",
  ], [
    "set", "insert", "remove", "move-up", "move-down", "move-to",
    "promote", "demote", "format", "extract",
  ])
  func preservesOpaqueFrontmatter(prefix: String, operation: String) async throws {
    let directory = Path.current + "tmp" + "body-preservation-\(UUID().uuidString)"
    try directory.mkpath()
    defer { try? directory.delete() }
    let file = directory + "source.md"
    let replacement = directory + "replacement.txt"
    let body = "# First\n\n* old\n\n## Child\n\nchild\n\n# Second\n\nsecond\n"
    try file.write(prefix + body)
    try replacement.write("replacement")
    let arguments: [String]
    switch operation {
    case "set":
      arguments = ["section", "set", "--index", "1", "--input", replacement.string, "--in-place", file.string]
    case "insert":
      arguments = ["section", "insert", "--name", "Added", "--after-index", "1", "--contents", "added", "--in-place", "--into", file.string]
    case "remove":
      arguments = ["section", "remove", "--index", "1", "--in-place", "--into", file.string]
    case "move-up":
      arguments = ["section", "move-up", "--index", "3", "--in-place", file.string]
    case "move-down":
      arguments = ["section", "move-down", "--index", "1", "--in-place", file.string]
    case "move-to":
      arguments = ["section", "move-to", "--index", "3", "--position", "1", "--in-place", file.string]
    case "promote", "demote":
      arguments = ["headings", operation, "--index", "2", "--in-place", file.string]
    case "format":
      arguments = ["format", "--bullets-dashes", "--in-place", file.string]
    default:
      arguments = ["extract", "--index", "1", "--remove", "--in-place", "--output", (directory + "extracted.md").string, file.string]
    }
    var command = try #require(CLIEntry.parseAsRoot(arguments) as? any AsyncParsableCommand)
    try await command.run()
    let output: String = try file.read()
    #expect(output.utf8.starts(with: prefix.utf8))
    #expect(output != prefix + body)
    if operation == "set" {
      #expect(output.contains("replacement"))
      #expect(output.contains("# Second"))
      #expect(output.contains("* old") == false)
    }
  }
}
