//
//  ListLinks.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilities
import PathKit
/// Adds command implementations to ``CLIEntry``.
///
/// See <doc:WikilinkCommands> for workflow details.
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
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:WikilinkCommands> for workflow details.
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
    /// Prints command results in the plain text output format.
    ///
    /// See <doc:WikilinkCommands> for workflow details.
    private func printPlainText(_ entries: [FileLinksEntry]) {
      let multiFile = entries.count > 1
      for entry in entries {
        if multiFile {
          print(CLIStyle.heading("==> \(entry.file) <=="))
        }
        if entry.links.isEmpty {
          print("  \(CLIStyle.muted("(no wikilinks)"))")
        } else {
          for link in entry.links {
            let statusIcon = styledStatusIcon(for: link.status)
            let target = link.target
            let resolution = link.resolvedPath.map(CLIStyle.path) ?? styledStatus(link.status)
            print("  \(statusIcon) [[\(target)]] \(CLIStyle.metadata("->")) \(resolution)")
          }
        }
        if multiFile {
          print("")
        }
      }
    }
    /// Returns the display marker for a link resolution status.
    ///
    /// See <doc:WikilinkCommands> for workflow details.
    private func styledStatusIcon(for status: String) -> String {
      switch status {
      case "resolved": return CLIStyle.success("✓")
      case "unresolved": return CLIStyle.error("✗")
      case "ambiguous": return CLIStyle.warning("?")
      default: return " "
      }
    }

    /// Returns a styled display value for a link resolution status.
    private func styledStatus(_ status: String) -> String {
      switch status {
      case "resolved": return CLIStyle.success(status)
      case "unresolved": return CLIStyle.error(status)
      case "ambiguous": return CLIStyle.warning(status)
      default: return status
      }
    }
  }
}

/// JSON output model for links list.
struct FileLinksEntry: Sendable, Codable {
  let file: String
  let links: [ResolvedWikilink]
}
