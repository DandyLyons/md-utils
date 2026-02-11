//
//  Check.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry {
  /// Check for broken or ambiguous wikilinks.
  struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "check",
      abstract: "Check for broken or ambiguous wikilinks"
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
      var totalLinks = 0
      var brokenCount = 0
      var ambiguousCount = 0
      var problems: [CheckProblem] = []

      for file in files {
        let content: String = try file.read()
        let doc = try MarkdownDocument(content: content)
        let wikilinks = doc.wikilinks()

        for link in wikilinks {
          totalLinks += 1
          let resolution = resolver.resolve(link, from: file)

          switch resolution {
          case .resolved:
            break
          case .unresolved:
            brokenCount += 1
            problems.append(CheckProblem(
              file: file.string,
              target: link.target,
              status: "unresolved",
              candidates: nil
            ))
          case .ambiguous(let paths):
            ambiguousCount += 1
            problems.append(CheckProblem(
              file: file.string,
              target: link.target,
              status: "ambiguous",
              candidates: paths.map(\.string)
            ))
          }
        }
      }

      if json {
        let report = CheckReport(
          totalLinks: totalLinks,
          broken: brokenCount,
          ambiguous: ambiguousCount,
          problems: problems
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        guard let output = String(data: data, encoding: .utf8) else {
          throw ValidationError("Failed to encode JSON")
        }
        print(output)
      } else {
        for problem in problems {
          let icon = problem.status == "unresolved" ? "✗" : "?"
          print("\(icon) \(problem.file): [[\(problem.target)]] (\(problem.status))")
          if let candidates = problem.candidates {
            for candidate in candidates {
              print("    candidate: \(candidate)")
            }
          }
        }
        print("")
        print("Total: \(totalLinks) links, \(brokenCount) broken, \(ambiguousCount) ambiguous")
      }

      if brokenCount > 0 || ambiguousCount > 0 {
        throw ExitCode.failure
      }
    }
  }
}

/// A single broken or ambiguous link found during check.
struct CheckProblem: Sendable, Codable {
  let file: String
  let target: String
  let status: String
  let candidates: [String]?
}

/// JSON output model for check report.
struct CheckReport: Sendable, Codable {
  let totalLinks: Int
  let broken: Int
  let ambiguous: Int
  let problems: [CheckProblem]
}
