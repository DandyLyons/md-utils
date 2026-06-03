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

    @Flag(name: .long, help: "Include successful validation results in output")
    var includeOk: Bool = false

    mutating func run() async throws {
      let timer = CommandTimer()
      let summary = try SchemaValidatorRunner.validate(ruleName: ruleName)
      print(SchemaValidationSummaryFormatter.render(summary, ruleName: ruleName, includeOk: includeOk))
      timer.writeStatus("Validated \(summary.matchedFiles) file(s)")
      if summary.hasFailures {
        throw ExitCode.failure
      }
    }
  }
}

enum SchemaValidationSummaryFormatter {
  static func render(
    _ summary: SchemaValidationSummary,
    ruleName: String? = nil,
    includeOk: Bool = false
  ) -> String {
    var lines: [String] = []

    guard !summary.results.isEmpty else {
      return "No files matched configured schema rules."
    }

    if let ruleName {
      lines.append("Validated \(summary.fileRuleMatches) file(s) against schema rule \"\(ruleName)\".")
    } else if summary.matchedFiles == summary.fileRuleMatches {
      lines.append(
        "Validated \(summary.matchedFiles) file(s) against \(Set(summary.results.map(\.ruleName)).count) schema rule(s)."
      )
    } else {
      lines.append(
        "Validated \(summary.fileRuleMatches) file-rule match(es) across \(summary.matchedFiles) file(s) and \(Set(summary.results.map(\.ruleName)).count) schema rule(s)."
      )
    }
    lines.append("Rules validated: \(Set(summary.results.map(\.ruleName)).sorted().joined(separator: ", ")).")

    if summary.errors > 0 {
      lines.append("Found \(summary.errors) error(s).")
    }
    if summary.skipped > 0 {
      lines.append("Skipped \(summary.skipped) file(s) without frontmatter.")
    }

    let visibleResults = summary.results.filter { includeOk || $0.status == .error }
    if !visibleResults.isEmpty {
      lines.append("")
      let grouped = Dictionary(grouping: visibleResults, by: \.ruleName)
      for rule in grouped.keys.sorted() {
        lines.append(rule)
        for result in grouped[rule] ?? [] {
          append(result, to: &lines)
        }
      }
    }

    return lines.joined(separator: "\n")
  }

  private static func append(_ result: SchemaValidationResult, to lines: inout [String]) {
    switch result.status {
    case .ok:
      lines.append("  OK \(result.filePath)")
    case .skipped:
      lines.append("  SKIP \(result.filePath)")
      for error in result.errors {
        lines.append("    \(error.path): \(error.message)")
      }
    case .error:
      lines.append("  ERROR \(result.filePath)")
      for error in result.errors {
        lines.append("    \(error.path): \(error.message)")
      }
    }
  }
}
