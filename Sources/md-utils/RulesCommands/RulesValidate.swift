//
//  RulesValidate.swift
//  md-utils
//

import ArgumentParser
/// Adds Markdown document behavior to ``CLIEntry.RulesCommands``.
///
/// See <doc:RulesValidationCommands> for workflow details.
extension CLIEntry.RulesCommands {
  /// Defines the `rules validate` command behavior.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  struct Validate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "validate",
      abstract: "Validate Markdown files against configured rules"
    )

    @Argument(help: "Optional rule name to validate")
    var ruleName: String?

    @Flag(name: .long, help: "Include successful validation results in output")
    var includeOk: Bool = false
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:RulesValidationCommands> for workflow details.
    mutating func run() async throws {
      let timer = CommandTimer()
      let summary = try RulesValidatorRunner.validate(ruleName: ruleName)
      print(RuleValidationSummaryFormatter.render(summary, ruleName: ruleName, includeOk: includeOk))
      timer.writeStatus("Validated \(summary.matchedFiles) file(s)")
      if summary.hasFailures {
        throw ExitCode.failure
      }
    }
  }
}
/// Formats `rules validate` command results.
///
/// See <doc:RulesValidationCommands> for workflow details.
enum RuleValidationSummaryFormatter {
  /// Renders the value into its output representation.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func render(
    _ summary: RuleValidationSummary,
    ruleName: String? = nil,
    includeOk: Bool = false
  ) -> String {
    var lines: [String] = []

    guard !summary.results.isEmpty else {
      return "No files matched configured rules."
    }

    if let ruleName {
      lines.append("Validated \(summary.fileRuleMatches) file(s) against rule \"\(ruleName)\".")
    } else if summary.matchedFiles == summary.fileRuleMatches {
      lines.append(
        "Validated \(summary.matchedFiles) file(s) against \(Set(summary.results.map(\.ruleName)).count) rule(s)."
      )
    } else {
      lines.append(
        "Validated \(summary.fileRuleMatches) file-rule match(es) across \(summary.matchedFiles) file(s) and \(Set(summary.results.map(\.ruleName)).count) rule(s)."
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
  /// Appends one validation result to the rendered summary lines.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  private static func append(_ result: RuleValidationResult, to lines: inout [String]) {
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
