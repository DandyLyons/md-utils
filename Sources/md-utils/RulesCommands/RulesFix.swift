import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesServerNative
import PathKit

extension CLIEntry.RulesCommands {
  struct Fix: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "fix",
      abstract: "Preview rule Fix-Its; persist only explicitly selected changes with --apply",
      discussion: "Selections accept comma-separated numbers and repeated flags. Noninteractive application requires the printed --review token. --yes selects automatic fixes only; relationship assertions require explicit selection. Previews never refresh an index or stage drafts. Application uses shared revision-checked drafts and receipts and can partially complete.",
    )
    @Argument(help: "Optional rule name") var ruleName: String?
    @OptionGroup var project: RuleProjectOptions
    @Option(name: .long, help: "Fix numbers, for example 1,4,5; may be repeated") var select: [String] = []
    @Option(name: .long, help: "Token printed by the reviewed preview") var review: String?
    @Flag(name: .long, help: "Persist the selected changes after evidence checks") var apply = false
    @Flag(name: .long, help: "Select automatic fixes only; does not authorize writes") var yes = false
    @Flag(name: .long, help: "Include and permit advisory fixes") var includeRecommendations = false
    @Flag(name: .long, help: "Print structured review, changes and assessments") var json = false

    mutating func run() async throws {
      let config = try project.load()
      let root = config.standaloneProject?.projectRoot ?? project.root ?? Path.current
      let service = MarkdownRuleFixService(projectRoot: root.string, configPath: project.configPath.string,
        rules: ruleName.map { [$0] },
      )
      let current = try await service.review(includeRecommendations: includeRecommendations)
      if let review, review != current.token { throw MarkdownFixItReviewError.staleReview }
      var numbers = try MarkdownFixItReview.parseSelections(select)
      var selected = try current.review.select(numbers: numbers, automatic: yes, includeRecommendations: includeRecommendations)
      var output = RuleFixOutput(review: current.review, token: current.token,
        before: current.suggestions.assessment, diagnostics: current.suggestions.diagnostics, selected: selected,
      )
      let command = "md-utils rules fix" + (ruleName.map { " " + Self.shellQuote($0) } ?? "")
        + " --config " + Self.shellQuote(project.configPath.absolute().string)
        + " --project-root " + Self.shellQuote(root.absolute().string + "/")
        + (includeRecommendations ? " --include-recommendations" : "")
      if selected.isEmpty && !apply {
        for index in current.review.proposals.indices {
          try Task.checkCancellation()
          do {
            let candidate = try await service.preview(current, numbers: [index + 1], includeRecommendations: includeRecommendations)
            output.candidates.append(.init(number: index + 1, after: candidate.after, blockers: candidate.blockers,
              files: Self.changedFiles(current, candidate),
            ))
          } catch is CancellationError { throw CancellationError() }
          catch { output.candidates.append(.init(number: index + 1, after: nil, blockers: [error.localizedDescription], files: [])) }
        }
      }
      if !json { print(Self.render(current, command: command, candidates: output.candidates)) }
      let automaticOnly = yes && select.isEmpty
      if apply && review == nil && !automaticOnly {
        guard !json, isatty(STDIN_FILENO) == 1 else {
          throw ValidationError("Application requires --review '\(current.token)'; preview and explicitly select fixes first.")
        }
        if selected.isEmpty {
          print("Select fix numbers (for example 1,4,5), or press Return to cancel:")
          guard let input = readLine(), !input.isEmpty else { return }
          numbers = try MarkdownFixItReview.parseSelections([input])
          selected = try current.review.select(numbers: numbers, automatic: yes, includeRecommendations: includeRecommendations)
          output.selected = selected
        }
      }
      if selected.isEmpty && apply { throw ValidationError("No fixes selected; no files changed.") }
      if !selected.isEmpty {
        let overlay = try await service.preview(current, numbers: selected, includeRecommendations: includeRecommendations)
        output.after = overlay.after; output.blockers = overlay.blockers
        output.files = Self.changedFiles(current, overlay)
        if !json {
          for file in output.files {
            print("\n--- \(file.path) (before)\n\(file.before)\n+++ \(file.path) (proposed)\n\(file.after)")
          }
          print("\nCombined assessment: \(overlay.before.outcome.rawValue) → \(overlay.after.outcome.rawValue)")
          for blocker in overlay.blockers { print("BLOCKED: \(blocker)") }
        }
      }
      if apply {
        guard output.blockers.isEmpty else {
          if json { try Self.printJSON(output) }
          throw ExitCode.failure
        }
        if review == nil && !automaticOnly {
          print("Apply these exact changes? [y/N]")
          guard readLine()?.lowercased() == "y" else { print("No files changed."); return }
        }
        let stream = AsyncStream<MarkdownDraftReport>.makeStream(bufferingPolicy: .bufferingNewest(1_000))
        var success = false
        do {
          success = try await service.apply(token: current.token, numbers: selected,
            includeRecommendations: includeRecommendations, report: { stream.continuation.yield($0) },
          )
        } catch {
          output.blockers.append(error.localizedDescription)
        }
        stream.continuation.finish()
        for await report in stream.stream { output.results.append(report) }
        output.applied = true
        let final: MarkdownRuleFixReview?
        do {
          final = try await service.review(includeRecommendations: includeRecommendations)
          output.after = final?.suggestions.assessment
        } catch {
          final = nil; output.after = nil; output.blockers.append("Final assessment unavailable: " + error.localizedDescription)
        }
        if !json {
          for result in output.results {
            print("\(result.path?.rawValue ?? "<file>"): \(result.state.rawValue) · draft \(result.draftID)")
            if let message = result.failureMessage { print(message) }
          }
          if !success && !output.results.isEmpty {
            let ids = output.results.map(\.draftID).map(Self.shellQuote).joined(separator: " ")
            print("Inspect drafts with index draft show. Resolve indeterminate attempts with index draft resolve.")
            print("Resume: md-utils index apply --project-root \(Self.shellQuote(root.absolute().string + "/")) \(ids)")
          }
          for blocker in output.blockers { print("ERROR: \(blocker)") }
          print("Final assessment: \(final?.suggestions.assessment.outcome.rawValue ?? "unavailable")")
          if let final, final.suggestions.assessment.outcome != .pass { print(Self.render(final, command: command)) }
        }
        if json { try Self.printJSON(output) }
        if !success || final?.suggestions.assessment.outcome != .pass || !output.blockers.isEmpty { throw ExitCode.failure }
      } else {
        if json { try Self.printJSON(output) }
        else { print("\nPreview only. No files changed.") }
        if !output.blockers.isEmpty || current.suggestions.assessment.outcome != .pass { throw ExitCode.failure }
      }
    }

    private static func shellQuote(_ value: String) -> String {
      "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func printJSON(_ output: RuleFixOutput) throws {
      let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      print(String(decoding: try encoder.encode(output), as: UTF8.self))
    }

    private static func changedFiles(_ current: MarkdownRuleFixReview, _ overlay: MarkdownFixItOverlay) -> [RuleFixOutput.File] {
      overlay.records.keys.sorted().compactMap { path in
        guard let before = current.collection.records[path], let after = overlay.records[path], before.content != after.content else { return nil }
        return .init(path: path, before: before.content, after: after.content)
      }
    }

    private static func render(_ current: MarkdownRuleFixReview, command: String, candidates: [RuleFixOutput.Candidate] = []) -> String {
      var lines = ["Review: \(current.token)"]
      for rule in current.suggestions.assessment.rules {
        for policy in rule.policies {
          for problem in policy.diagnostics {
            let diagnostic = problem.diagnostic
            lines.append("\n\(diagnostic.severity == .error ? "ERROR" : "WARNING") · rule: \(rule.rule) · policy: \(policy.origin.policy)")
            let declaration = policy.origin.declaration.objectValue ?? [:]
            let kind = declaration["kind"]?.stringValue ?? "relationship"
            if kind == "reciprocity" {
              let name = declaration["relation"]?.objectValue?["name"]?.stringValue ?? "<relationship>"
              lines.append("The \(rule.rule) rule requires reciprocal links for the declared \(name) relationship.")
            }
            lines.append(diagnostic.message)
            for index in problem.occurrences where current.suggestions.assessment.extraction.occurrences.indices.contains(index) {
              let occurrence = current.suggestions.assessment.extraction.occurrences[index]
              let location = MarkdownFixItPropertyChange(path: occurrence.propertyPath, before: nil, after: nil).location
              lines.append("\(occurrence.source) frontmatter \(location) contains \(Self.value(occurrence.value)) → \(occurrence.resolution?.destination ?? "unavailable").")
            }
          }
        }
        for record in rule.records where record.outcome != .pass {
          for diagnostic in record.assessment.diagnostics + record.assessment.applicabilityDiagnostics {
            lines.append("\(diagnostic.severity == .error ? "ERROR" : "WARNING") · \(rule.rule) · \(record.path) · \(diagnostic.location): \(diagnostic.message)")
          }
        }
      }
      for (index, proposal) in current.review.proposals.enumerated() {
        let number = index + 1
        lines.append("\nFix \(number): \(proposal.fixIt.title) [\(proposal.fixIt.safety.rawValue)]")
        for change in proposal.changes {
          lines.append("  \(proposal.path.rawValue) frontmatter \(change.location): \(value(change.before)) → \(value(change.after))")
        }
        if proposal.fixIt.safety == .requiresInput { lines.append("This changes an assertion; confirm that it is correct.") }
        if let candidate = candidates.first(where: { $0.number == number }) {
          lines.append("Assessment when selected alone: \(current.suggestions.assessment.outcome.rawValue) → \(candidate.after?.outcome.rawValue ?? "unavailable")")
          for blocker in candidate.blockers { lines.append("BLOCKED when selected alone: \(blocker)") }
          for file in candidate.files {
            lines.append("--- \(file.path) (before)\n\(file.before)\n+++ \(file.path) (proposed)\n\(file.after)")
          }
        }
        if proposal.fixIt.safety != .advisoryOnly {
          lines.append("Preview this fix:\n  \(command) --select \(number)")
          lines.append("Apply this fix:\n  \(command) --select \(number) --review '\(current.token)' --apply")
        }
      }
      for diagnostic in current.suggestions.diagnostics { lines.append("\(diagnostic.code): \(diagnostic.message)") }
      if current.review.proposals.isEmpty { lines.append("No executable Fix-Its are available.") }
      return lines.joined(separator: "\n")
    }

    private static func value(_ value: JSONValue?) -> String {
      guard let value else { return "missing" }
      let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      return (try? String(decoding: encoder.encode(value), as: UTF8.self)) ?? "<unavailable>"
    }
  }
}

private struct RuleFixOutput: Encodable {
  struct File: Encodable { let path: String; let before: String; let after: String }
  struct Candidate: Encodable { let number: Int; let after: MarkdownRuleCollectionAssessment?; let blockers: [String]; let files: [File] }
  let review: MarkdownFixItReview
  let token: String
  let before: MarkdownRuleCollectionAssessment
  let diagnostics: [MarkdownDiagnostic]
  var selected: [Int]
  var files: [File] = []
  var after: MarkdownRuleCollectionAssessment?
  var blockers: [String] = []
  var results: [MarkdownDraftReport] = []
  var applied = false
  var candidates: [Candidate] = []
}
