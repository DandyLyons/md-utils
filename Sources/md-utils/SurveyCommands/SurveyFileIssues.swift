import ArgumentParser
import Foundation
import MarkdownUtilitiesCore

struct SurveyFileIssue: Codable {
  struct Reason: Codable {
    var code: String
    var message: String
  }
  var path: String
  var category: String
  var reasons: [Reason]
}

struct SurveyFileIssues: Codable {
  var rows: [SurveyFileIssue] = []
  var total = 0
  var omitted = 0
  var counts: [String: Int] = [:]
}

extension SurveyReport {
  /// Retain counts for the full scope, but bound diagnostic evidence by the requested limit.
  mutating func recordFileIssue(path: String, category: String, code: String, message: String, reasons: [SurveyFileIssue.Reason] = []) {
    fileIssues.total += 1
    fileIssues.counts[category, default: 0] += 1
    let limit: Int
    if case .integer(let count) = parameters["limit"] { limit = count } else { limit = 20 }
    if limit == 0 || fileIssues.rows.count < limit {
      let prefix = root.hasSuffix("/") ? root : root + "/"
      let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
      fileIssues.rows.append(.init(path: relative, category: category,
        reasons: reasons.isEmpty ? [.init(code: code, message: message)] : reasons))
    } else { fileIssues.omitted += 1 }
  }

  mutating func recordReadFailure(path: String, error: Error) {
    let message = error is ValidationError ? String(describing: error) : error.localizedDescription
    recordFileIssue(path: path, category: "unreadable", code: "survey.file.read-failed", message: message)
    unavailable("\(path): \(message)")
  }

  func fileIssueText() -> String {
    guard fileIssues.total > 0 else { return "" }
    let counts = fileIssues.counts.keys.sorted().map { "\(fileIssues.counts[$0] ?? 0) \($0)" }.joined(separator: ", ")
    var lines = ["File assessment issues: \(counts).", "Unsupported or malformed frontmatter is unavailable for metadata statistics; unreadable inputs prevent complete coverage."]
    let shown = parameters["limit"] == .integer(0) ? fileIssues.rows : Array(fileIssues.rows.prefix(3))
    for issue in shown {
      lines.append("  \(issue.path) — \(issue.category)")
      // Keep parser explanations on one readable line per example; full diagnostics remain in JSON.
      if let reason = issue.reasons.first {
        let message = reason.message.split(whereSeparator: \.isNewline).joined(separator: " ")
        lines.append("    " + String(message.prefix(240)) + (message.count > 240 ? "… (full reason in --format json)" : ""))
      }
    }
    let remaining = fileIssues.total - shown.count
    if remaining > 0 { lines.append("  \(remaining) more file issues; use --limit 0 to show all or --format json for structured details.") }
    return lines.joined(separator: "\n")
  }
}
