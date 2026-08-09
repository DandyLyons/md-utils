//
//  RulesMatching.swift
//  md-utils
//

import ArgumentParser
import PathKit

/// Adds Markdown document behavior to ``CLIEntry.RulesCommands``.
///
/// See <doc:RulesValidationCommands> for workflow details.
extension CLIEntry.RulesCommands {
  /// Defines the `rules matching` command behavior.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  struct Matching: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "matching",
      abstract: "List configured rules matching a file",
      discussion: RulesNonMarkdownHelp.appending(
        to: "An explicit mapped non-Markdown file is selected automatically."
      )
    )

    @Argument(help: "File path to match rules against")
    var fileName: String

    @Flag(name: .long, help: "Include a plain .txt or other non-Markdown file")
    var includeNonMD = false

    @Flag(name: .long, help: "Explain why each configured rule matched or did not match")
    var explain = false

    @Flag(name: .long, help: "Explain matching rules only, omitting skipped rules")
    var explainNoSkips = false

    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:RulesValidationCommands> for workflow details.
    mutating func run() async throws {
      if explain && explainNoSkips {
        throw ValidationError("Use either --explain or --explain-no-skips, not both.")
      }
      let evaluations = try await RulesValidatorRunner.rulesMatching(
        fileName: fileName,
        includeNonMarkdown: includeNonMD
      )
      print(RulesMatchingFormatter.render(
        evaluations,
        fileName: fileName,
        explain: explain || explainNoSkips,
        includeSkips: !explainNoSkips
      ))
      if evaluations.contains(where: { $0.diagnostics.isEmpty == false }) {
        throw ExitCode.failure
      }
    }
  }
}

enum RulesMatchingFormatter {
  static func render(
    _ evaluations: [RuleMatchEvaluation],
    fileName: String,
    explain: Bool = false,
    includeSkips: Bool = true
  ) -> String {
    if explain {
      return renderExplanation(evaluations, fileName: fileName, includeSkips: includeSkips)
    }

    let names = evaluations.filter(\.matched).map(\.rule.name)
    let diagnostics = evaluations.flatMap(\.diagnostics)
    guard !names.isEmpty || !diagnostics.isEmpty else {
      return CLIStyle.muted("No rules matched file \"\(fileName)\".")
    }
    return (names + diagnostics.map { "ERROR: \($0)" }).joined(separator: "\n")
  }

  private static func renderExplanation(
    _ evaluations: [RuleMatchEvaluation],
    fileName: String,
    includeSkips: Bool
  ) -> String {
    guard !evaluations.isEmpty else {
      return CLIStyle.muted("No rules are configured.")
    }

    let visibleEvaluations = includeSkips ? evaluations : evaluations.filter(\.matched)
    guard !visibleEvaluations.isEmpty else {
      return CLIStyle.muted("No rules matched file \"\(fileName)\".")
    }

    var lines = ["Rules matching \(CLIStyle.path(fileName)):"]
    for evaluation in visibleEvaluations {
      let status = evaluation.matched ? CLIStyle.success("MATCH") : CLIStyle.muted("SKIP")
      lines.append("  \(status) \(CLIStyle.heading(evaluation.rule.name))")
      for reason in evaluation.reasons {
        lines.append("    - \(reason)")
      }
      for diagnostic in evaluation.diagnostics where evaluation.reasons.contains(diagnostic) == false {
        lines.append("    - \(diagnostic)")
      }
    }
    return lines.joined(separator: "\n")
  }
}
