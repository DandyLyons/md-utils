import Foundation
import MarkdownUtilitiesCore

enum RelationshipQueryRenderer {
  static func render(_ result: MarkdownCollectionQueryResult) -> String {
    var lines: [String] = []
    for path in result.selected {
      lines.append(CLIStyle.heading(path))
      var count = 0
      for (label, triples) in [("Relationships", result.relationships), ("Ordinary links", result.links)] {
        let visible = triples.filter {
          ($0.subject == path && result.direction != .incoming) || ($0.object == path && result.direction != .outgoing)
            || ($0.subject == path && $0.object == path)
        }
        guard !visible.isEmpty else { continue }
        lines.append("  " + CLIStyle.heading(label))
        for triple in visible {
          let direction = triple.subject == triple.object ? "self" : (triple.subject == path ? "out" : "in")
          let repeated = triple.occurrenceCount > 1 ? " (\(triple.occurrenceCount) occurrences)" : ""
          lines.append("    \(CLIStyle.metadata(direction))  \(CLIStyle.path(triple.subject)) —\(triple.predicate)→ \(CLIStyle.path(triple.object))\(repeated)")
          count += 1
        }
      }
      if count == 0 {
        let qualifier = result.notices.contains { $0.code == "query.incomplete" } ? "in the inspected scope" : "in this scope"
        let direction = result.direction == .both ? "" : result.direction.rawValue + " "
        lines.append(CLIStyle.muted("  No \(direction)relationships or ordinary links found \(qualifier)."))
      }
    }
    if result.selected.isEmpty { lines.append(CLIStyle.muted("No documents selected in this scope.")) }
    for notice in result.notices {
      lines.append(CLIStyle.warning(notice.message) + (result.detail == .summary ? " " + CLIStyle.hint(notice.hint ?? "") : ""))
    }
    if let coverage = result.coverage {
      lines.append(CLIStyle.metadata("Coverage: selection \(coverage.selection), sources \(coverage.sources), candidates \(coverage.candidates), interpretations \(coverage.interpretations)."))
      lines += coverage.limitations.map { "  " + CLIStyle.warning($0) }
    }
    for path in result.skipped ?? [] { lines.append(CLIStyle.muted("JMESPath skipped TOML: \(path)")) }
    for explanation in result.explanations ?? [] {
      lines.append("  \(CLIStyle.path(explanation.source)) \(explanation.predicate): \(explanation.outcome.rawValue)")
      lines.append("    \(explanation.location.propertyPath ?? [])")
      lines += explanation.applicability.map { "    \($0.kind)\($0.rule.map { " (\($0))" } ?? "")" }
      lines += explanation.diagnostics.map { "    \($0.code): \($0.message)" }
    }
    for item in result.diagnostics ?? [] {
      lines.append("  \(CLIStyle.path(item.source)) \(item.type) \(item.diagnostic.code): \(item.diagnostic.message)")
    }
    if result.detail == .evidence {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      if let data = try? encoder.encode(result), let text = String(data: data, encoding: .utf8) {
        lines.append(CLIStyle.heading("Full evidence")); lines.append(CLIStyle.metadata(text))
      }
    }
    return lines.joined(separator: "\n")
  }
}
