//
//  Validate.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry.SchemaCommands {
  struct Validate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "validate",
      abstract: "Validate Markdown frontmatter against configured schema rules"
    )

    @Argument(help: "Optional schema rule name to validate")
    var ruleName: String?

    mutating func run() async throws {
      let summary = try SchemaValidatorRunner.validate(ruleName: ruleName)
      printSummary(summary)
      if summary.hasFailures {
        throw ExitCode.failure
      }
    }

    private func printSummary(_ summary: SchemaValidationSummary) {
      guard !summary.results.isEmpty else {
        print("No files matched configured schema rules.")
        return
      }

      if let ruleName {
        print("Validated \(summary.fileRuleMatches) file(s) against schema rule \"\(ruleName)\".")
      } else if summary.matchedFiles == summary.fileRuleMatches {
        print(
          "Validated \(summary.matchedFiles) file(s) against \(Set(summary.results.map(\.ruleName)).count) schema rule(s)."
        )
      } else {
        print(
          "Validated \(summary.fileRuleMatches) file-rule match(es) across \(summary.matchedFiles) file(s) and \(Set(summary.results.map(\.ruleName)).count) schema rule(s)."
        )
      }

      if summary.errors > 0 {
        print("Found \(summary.errors) error(s).")
      }
      if summary.skipped > 0 {
        print("Skipped \(summary.skipped) file(s) without frontmatter.")
      }
      print("")

      let grouped = Dictionary(grouping: summary.results, by: \.ruleName)
      for rule in grouped.keys.sorted() {
        print(rule)
        for result in grouped[rule] ?? [] {
          switch result.status {
          case .ok:
            print("  OK \(result.filePath)")
          case .skipped:
            print("  SKIP \(result.filePath)")
            for error in result.errors {
              print("    \(error.path): \(error.message)")
            }
          case .error:
            print("  ERROR \(result.filePath)")
            for error in result.errors {
              print("    \(error.path): \(error.message)")
            }
          }
        }
      }
    }
  }
}
