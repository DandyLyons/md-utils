import ArgumentParser
import Foundation
import Testing
@testable import md_utils

@Suite("CLI help audit regressions")
struct CLIHelpTests {
  /// Follow registration rather than a second command list, so new nested pages
  /// must be added to the reviewable audit inventory as the CLI grows.
  private func registeredCommands(
    _ command: ParsableCommand.Type = CLIEntry.self,
    path: [String] = ["md-utils"],
  ) -> [(path: [String], command: ParsableCommand.Type)] {
    [(path, command)] + command.configuration.subcommands.flatMap { child in
      registeredCommands(child, path: path + [child._commandName])
    }
  }

  @Test(.bug("https://github.com/DandyLyons/md-utils/issues/187"))
  func `audit inventory covers every registered help page and alias`() throws {
    let root = URL(filePath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let document = try String(contentsOf: root.appending(path: "docs/cli-help-audit.md"), encoding: .utf8)
    let rows = document.split(separator: "\n").filter { $0.hasPrefix("| `md-utils") }
    let documented = rows.compactMap { $0.split(separator: "`").dropFirst().first.map(String.init) }
    let registered = registeredCommands()
    #expect(documented.count == Set(documented).count)
    #expect(Set(documented) == Set(registered.map { $0.path.joined(separator: " ") }))
    for entry in registered {
      let help = CLIEntry.helpMessage(for: entry.command, columns: 120)
      #expect(help.contains("USAGE:"), Comment(rawValue: entry.path.joined(separator: " ")))
      #expect(entry.command.configuration.abstract.isEmpty == false,
        Comment(rawValue: entry.path.joined(separator: " ")))
      let row = try #require(rows.first { $0.hasPrefix("| `\(entry.path.joined(separator: " "))` |") })
      for alias in entry.command.configuration.aliases {
        #expect(row.contains("`\(alias)`"), Comment(rawValue: "Missing alias \(alias)"))
      }
    }
  }

  @Test
  func `root help exposes nested search and contract conversion without flattening`() {
    let help = CLIEntry.helpMessage(columns: 120)
    #expect(help.contains("fm search --help"))
    #expect(help.contains("JMESPath"))
    #expect(help.contains("links convert --help"))
    #expect(help.contains("--type"))
    #expect(CLIEntry.configuration.subcommands.contains { $0._commandName == "search" } == false)
  }

  @Test(arguments: [
    (["fm", "search"], ["--format", "raw", "toml is rejected", "No matches", "SQLite"]),
    (["section", "list"], ["USAGE: md-utils section list", "md-only-headings", "filename headers"]),
    (["toc"], ["headings only", "default: md-only-headings", "md-bullet-links"]),
    (["index", "field"], ["Add a managed JSON expression index", "Remove a managed field", "List managed fields"]),
    (["index", "search"], ["Enable body retention", "Remove retained bodies", "Print stored body mode"]),
    (["links", "convert"], ["exactly one of --to or --type", "vault/notes/", "whole-type conformance"]),
    (["template", "render"], ["Path to a JSON object file", "Path to an optional JSON Schema file"]),
    (["convert", "to-text"], ["Number of newlines between block elements (default: 2)", "Number of spaces per indentation level (default: 2)"]),
    (["types", "check"], ["markdown (text-style), json, yaml, or toml", "structured output always includes all results"]),
  ])
  func `executable help retains corrected guidance`(_ example: ([String], [String])) throws {
    // Rendering and alias routing belong to the executable boundary. Normalize
    // only wrapping so these assertions do not depend on terminal width.
    let result = try CLIProcessTestHelper.run(example.0 + ["--help"])
    try #require(result.status == 0)
    let help = result.standardOutput.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    for fragment in example.1 {
      #expect(help.contains(fragment), Comment(rawValue: "Missing help guidance: \(fragment)"))
    }
    #expect(help.contains("section table-of-contents list") == false)
    #expect(help.contains("json (default)") == false)
    #expect(help.contains("(default: 2) (default: 2)") == false)
  }
}
