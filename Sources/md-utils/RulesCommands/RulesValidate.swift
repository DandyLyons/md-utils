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
      abstract: "Validate files against configured rules",
      discussion: RulesNonMarkdownHelp.appending(
        to: "Uses and refreshes an existing project index automatically, falling back to source files if the index is unavailable. --indexed-only requires registered scopes and checks only recorded candidates without discovery or fallback; success has limited coverage. Ordinary validation/index refresh discovers new files. Project scans remain Markdown-only unless non-Markdown files are explicitly included."
      )
    )

    @Argument(help: "Optional rule name to validate")
    var ruleName: String?

    @Flag(name: .long, help: "Include successful validation results in output")
    var includeOk: Bool = false

    @Flag(name: .long, help: "Include non-Markdown files selected by configured rule paths")
    var includeNonMD = false
    @Flag(name: .long, help: "Validate source files directly without using the project index")
    var noIndex = false
    @Flag(name: .long, help: "Validate only recorded candidates in registered rule scopes; require an index and never discover new files or fall back")
    var indexedOnly = false
    @Flag(name: .long, help: "Hash every indexed candidate to detect edits preserving size and modification time")
    var verifyHashes = false
    @OptionGroup var project: RuleProjectOptions
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:RulesValidationCommands> for workflow details.
    mutating func run() async throws {
      let timer = CommandTimer()
      let summary = try await RulesValidatorRunner.validate(
        ruleName: ruleName,
        includeNonMarkdown: includeNonMD,
        configPath: project.configPath,
        projectRoot: project.root,
        noIndex: noIndex,
        indexedOnly: indexedOnly,
        verifyHashes: verifyHashes,
      )
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
    if summary.indexedOnly {
      lines.append("Limited coverage: only recorded candidates were validated. New files were not discovered.")
      if !summary.uncoveredRules.isEmpty {
        lines.append("Configured rules not covered: \(summary.uncoveredRules.sorted().joined(separator: ", ")).")
      }
    }

    guard !summary.results.isEmpty else {
      return (lines + ["No files matched configured rules."]).joined(separator: "\n")
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
