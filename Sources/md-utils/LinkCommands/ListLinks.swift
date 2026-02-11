//
//  ListLinks.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry {
  /// List all wikilinks in Markdown files with resolution status.
  struct ListLinks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List wikilinks in Markdown files with resolution status",
      aliases: ["ls"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Root directory for link resolution (default: current directory)",
      transform: { Path($0) }
    )
    var root: Path = Path.current

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    mutating func run() async throws {
      let files = try options.resolvedPaths()
      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found")
      }

      let resolver = try WikilinkResolver(root: root)
      var entries: [FileLinksEntry] = []

      for file in files {
        let content: String = try file.read()
        let doc = try MarkdownDocument(content: content)
        let wikilinks = doc.wikilinks()

        let resolved = wikilinks.map { link in
          ResolvedWikilink(
            wikilink: link,
            resolution: resolver.resolve(link, from: file)
          )
        }

        entries.append(FileLinksEntry(file: file.string, links: resolved))
      }

      if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        guard let output = String(data: data, encoding: .utf8) else {
          throw ValidationError("Failed to encode JSON")
        }
        print(output)
      } else {
        printPlainText(entries)
      }
    }

    private func printPlainText(_ entries: [FileLinksEntry]) {
      let multiFile = entries.count > 1
      for entry in entries {
        if multiFile {
          print("==> \(entry.file) <==")
        }
        if entry.links.isEmpty {
          print("  (no wikilinks)")
        } else {
          for link in entry.links {
            let statusIcon = statusIcon(for: link.status)
            let target = link.target
            let resolution = link.resolvedPath ?? link.status
            print("  \(statusIcon) [[\(target)]] -> \(resolution)")
          }
        }
        if multiFile {
          print("")
        }
      }
    }

    private func statusIcon(for status: String) -> String {
      switch status {
      case "resolved": return "✓"
      case "unresolved": return "✗"
      case "ambiguous": return "?"
      default: return " "
      }
    }
  }
}

/// JSON output model for links list.
struct FileLinksEntry: Sendable, Codable {
  let file: String
  let links: [ResolvedWikilink]
}
