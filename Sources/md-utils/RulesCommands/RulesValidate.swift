//
//  RulesValidate.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import Yams
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
    @Flag(name: .long, help: "Report one cycle witness per cyclic component (default)")
    var cycleWitnessPerComponent = false
    @Flag(name: .long, help: "Stop each cycle policy's cycle search after its first witness")
    var cycleWitnessFirst = false
    @Flag(name: .long, help: "Emit structured JSON validation evidence") var json = false
    @Flag(name: .long, help: "Emit structured YAML validation evidence") var yaml = false
    @OptionGroup var project: RuleProjectOptions
    mutating func validate() throws {
      guard !(cycleWitnessFirst && cycleWitnessPerComponent) else {
        throw ValidationError("--cycle-witness-first and --cycle-witness-per-component are mutually exclusive")
      }
      guard !(json && yaml) else { throw ValidationError("--json and --yaml are mutually exclusive") }
    }
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
        cycleWitnessMode: cycleWitnessFirst ? .first : .perComponent,
      )
      if json || yaml {
        let output = RuleValidationOutput(summary)
        if yaml { print(try YAMLEncoder().encode(output)) }
        else {
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
          print(String(decoding: try encoder.encode(output), as: UTF8.self))
        }
      } else { print(RuleValidationSummaryFormatter.render(summary, ruleName: ruleName, includeOk: includeOk)) }
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
    if let collection = summary.collectionAssessment {
      return renderCollection(collection, summary: summary, includeOk: includeOk)
    }
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
  private static func renderCollection(_ collection: MarkdownRuleCollectionAssessment,
    summary: RuleValidationSummary, includeOk: Bool,
  ) -> String {
    var lines = ["Collection validation: \(collection.outcome.rawValue)"]
    if summary.indexedOnly { lines.append("Limited coverage: new files were not discovered.") }
    if !summary.uncoveredRules.isEmpty { lines.append("Uncovered rules: " + summary.uncoveredRules.joined(separator: ", ")) }
    func append(_ value: MarkdownPolicyDiagnostic) {
      lines.append("  \(value.diagnostic.severity.rawValue): \(value.diagnostic.code): \(value.diagnostic.message)")
      for origin in value.origins { lines.append("    \(origin.rule)/\(origin.policy) at \(origin.definitionSource ?? "<definition>") \(origin.location)") }
      for index in value.occurrences where collection.extraction.occurrences.indices.contains(index) {
        let occurrence = collection.extraction.occurrences[index]
        lines.append("    \(occurrence.source) \(occurrence.propertyPath) [\(occurrence.type).\(occurrence.relationship)] → \(occurrence.resolution?.destination ?? "?")")
      }
    }
    for rule in collection.rules {
      lines.append("\(rule.rule): \(rule.outcome.rawValue); source coverage \(rule.sourcesComplete ? "complete" : "limited")")
      for record in rule.records where record.membership != .notMatched {
        if includeOk || record.outcome != .pass { lines.append("  \(record.outcome.rawValue): \(record.path)") }
        for diagnostic in record.assessment.applicabilityDiagnostics + record.assessment.diagnostics {
          lines.append("    \(diagnostic.severity.rawValue): \(diagnostic.code) \(diagnostic.location): \(diagnostic.message)")
        }
      }
      for policy in rule.policies {
        lines.append("  Policy \(policy.origin.policy): \(policy.outcome.rawValue) (\(policy.severity.rawValue)); \(policy.checkedRecords.count) records; graph \(policy.graphComplete ? "complete" : "limited"); \(policy.boundaryEdges.count) boundary edges")
        for diagnostic in policy.diagnostics { append(diagnostic) }
        if policy.cycleSearchStoppedEarly { lines.append("    Cycle search stopped after the first witness; additional cycles were not searched for.") }
      }
    }
    for conflict in collection.conflicts { append(conflict) }
    for limitation in collection.limitations { lines.append("  " + limitation) }
    if collection.diagnosticsTruncated { lines.append("Diagnostic or conflict-search output is incomplete due to resource limits.") }
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

/// One stable envelope for text-equivalent JSON and YAML validation output.
struct RuleValidationOutput: Encodable {
  var results: [RuleValidationResult]
  var totalFiles: Int
  var indexedOnly: Bool
  var uncoveredRules: [String]
  var hasFailures: Bool
  var collectionAssessment: MarkdownRuleCollectionAssessment?

  init(_ summary: RuleValidationSummary) {
    results = summary.results
    totalFiles = summary.totalFiles
    indexedOnly = summary.indexedOnly
    uncoveredRules = summary.uncoveredRules
    hasFailures = summary.hasFailures
    collectionAssessment = summary.collectionAssessment
  }
}
