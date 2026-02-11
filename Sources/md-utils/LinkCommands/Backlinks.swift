//
//  Backlinks.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry {
  /// Find files that link to a given target.
  struct Backlinks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "backlinks",
      abstract: "Find files that link to a given target",
      discussion: """
        [BETA] Backlinks detection is experimental and may produce incomplete \
        results, particularly with complex vault structures or non-standard \
        wikilink usage.

        Scans Markdown files for wikilinks that resolve to the given target \
        file(s). Use --scan-scope to limit the search directory.
        """,
      aliases: ["bl"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Root directory for link resolution (default: current directory)",
      transform: { Path($0) }
    )
    var root: Path = Path.current

    @Option(
      name: .long,
      help: "Directory to scan for backlinks (default: same as --root)",
      transform: { Path($0) }
    )
    var scanScope: Path?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    mutating func run() async throws {
      let targetFiles = try options.resolvedPaths()
      guard !targetFiles.isEmpty else {
        throw ValidationError("No target files specified")
      }

      let resolver = try WikilinkResolver(root: root)
      let scope = scanScope ?? root
      let scanResolver = try WikilinkResolver(root: scope)
      let filesToScan = scanResolver.markdownFiles

      // Normalize target paths for comparison
      let targetAbsolute = Set(targetFiles.map { $0.absolute().string })

      var entries: [BacklinkEntry] = []

      for targetFile in targetFiles {
        var linkingFiles: [BacklinkSource] = []

        for scanFile in filesToScan {
          // Don't report a file as backlinking to itself
          if scanFile.absolute().string == targetFile.absolute().string {
            continue
          }

          let content: String = try scanFile.read()
          let doc = try MarkdownDocument(content: content)
          let wikilinks = doc.wikilinks()

          let matchingLinks = wikilinks.filter { link in
            let resolution = resolver.resolve(link, from: scanFile)
            if case .resolved(let path) = resolution {
              return targetAbsolute.contains(path.string)
            }
            return false
          }

          if !matchingLinks.isEmpty {
            linkingFiles.append(BacklinkSource(
              file: scanFile.string,
              links: matchingLinks.map(\.target)
            ))
          }
        }

        entries.append(BacklinkEntry(
          target: targetFile.string,
          backlinks: linkingFiles
        ))
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

    private func printPlainText(_ entries: [BacklinkEntry]) {
      let multiTarget = entries.count > 1
      for entry in entries {
        if multiTarget {
          print("==> \(entry.target) <==")
        }
        if entry.backlinks.isEmpty {
          print("  (no backlinks)")
        } else {
          for source in entry.backlinks {
            let linkText = source.links.map { "[[\($0)]]" }.joined(separator: ", ")
            print("  \(source.file) via \(linkText)")
          }
        }
        if multiTarget {
          print("")
        }
      }
    }
  }
}

/// A file that links to the target.
struct BacklinkSource: Sendable, Codable {
  let file: String
  let links: [String]
}

/// JSON output model for backlinks result.
struct BacklinkEntry: Sendable, Codable {
  let target: String
  let backlinks: [BacklinkSource]
}
