import Foundation
import MarkdownUtilitiesCore

extension SurveyReport {
  /// Present orientation first while retaining complete, bounded evidence in JSON.
  func focusedSummary(_ metric: String) -> String {
    let value = metrics[metric]?.objectValue ?? [:]
    func number(_ value: JSONValue?) -> Int {
      if case .integer(let count) = value { return count }
      return 0
    }
    func rows(_ value: JSONValue?) -> [JSONValue] {
      if case .array(let values) = value?.objectValue?["rows"] { return values }
      return []
    }
    func total(_ value: JSONValue?) -> Int { number(value?.objectValue?["total"]) }
    func table(_ headings: [String], _ body: [[String]]) -> [String] {
      let widths = headings.indices.map { index in
        ([headings[index].count] + body.map { $0[index].count }).max() ?? 0
      }
      return ([headings] + body).map { cells in
        cells.indices.map { index in
          index == cells.count - 1 ? cells[index]
            : cells[index].padding(toLength: widths[index] + 2, withPad: " ", startingAt: 0)
        }.joined()
      }
    }
    var lines = ["Survey: " + paths.joined(separator: ", ")]
    let all = parameters["limit"] == .integer(0)
    // Samples are presentation-only: scan coverage and machine evidence are unchanged.
    func sample(_ evidence: JSONValue?, label: String, render: (JSONValue) -> String) {
      let available = rows(evidence)
      let shown = all ? available : Array(available.prefix(3))
      if !shown.isEmpty {
        lines.append("\n" + label)
        lines += shown.map { "  " + render($0) }
      }
      let remaining = total(evidence) - shown.count
      if remaining > 0 { lines.append("  \(remaining) more; use --format json for evidence or --limit 0 to show all.") }
    }
    func omitted(_ evidence: JSONValue?) {
      let count = number(evidence?.objectValue?["omitted"])
      if count > 0 { lines.append("\(count) rows omitted; use --limit 0 to show all.") }
    }
    switch metric {
    case "types":
      lines += ["\(total(metrics[metric])) type definitions. Inventory does not establish document conformance.", ""]
      let body = rows(metrics[metric]).map { row -> [String] in
        let fields = row.objectValue ?? [:]
        let relevance = fields["referencedByApplicableRule"] == .boolean(true)
          ? "Referenced by a matching or uncertain rule"
          : (fields["discoveredInScope"] == .boolean(true) ? "Definition found in surveyed files" : "Other configured definition")
        return [fields["name"]?.stringValue ?? "", relevance]
      }
      lines += table(["Type", "Relevance"], body)
      omitted(metrics[metric])
    case "type-matches":
      lines += ["Types assessed: \(total(metrics[metric])). Structural matches do not establish intended usage.", ""]
      let body = rows(metrics[metric]).map { row -> [String] in
        let outcomes = row.objectValue?["outcomes"]?.objectValue ?? [:]
        let pass = total(outcomes["pass"]), fail = total(outcomes["fail"]), unavailable = total(outcomes["unavailable"])
        return [row.objectValue?["type"]?.stringValue ?? "", String(pass + fail), String(pass), String(fail), String(unavailable)]
      }
      lines += table(["Type", "Assessed", "Pass", "Fail", "Unavailable"], body)
      omitted(metrics[metric])
      // One representative type keeps large inventories concise; filtering narrows investigation.
      for row in (all ? rows(metrics[metric]) : Array(rows(metrics[metric]).prefix(1))) {
        let name = row.objectValue?["type"]?.stringValue ?? ""
        for outcome in ["pass", "fail", "unavailable"] {
          sample(row.objectValue?["outcomes"]?.objectValue?[outcome], label: "\(name) — \(outcome) examples:") { $0.stringValue ?? "" }
        }
        if !all { lines.append("Refine with --type \(Self.quote(name)); add --format json for file evidence.") }
      }
    case "uncovered":
      lines.append("Confirmed unselected files: \(total(value["files"])); uncertain files: \(total(value["unknown"])).")
      lines.append("Configured rules: \(number(value["configuredRules"])).")
      if number(value["configuredRules"]) == 0 { lines.append("No rules are configured; lack of coverage is not a validation failure.") }
      sample(value["files"], label: "Unselected files:") { $0.stringValue ?? "" }
      sample(value["unknown"], label: "Uncertain files (not confirmed uncovered):") { $0.stringValue ?? "" }
    case "overlaps":
      lines.append("\(total(metrics[metric])) files selected by multiple rules. Overlap can be intentional.")
      sample(metrics[metric], label: "Overlapping selections:") { row in
        let fields = row.objectValue ?? [:]
        let names: [String]
        if case .array(let values) = fields["rules"] { names = values.compactMap(\.stringValue) } else { names = [] }
        return (fields["path"]?.stringValue ?? "") + " — " + names.joined(separator: ", ")
          + (fields["additionalMatchesUnknown"] == .boolean(true) ? " (additional matches uncertain)" : "")
      }
    case "relationships":
      lines.append("\(total(value["ordinaryLinks"])) distinct ordinary links (excluding self-links).")
      let resolution = value["resolution"]?.objectValue ?? [:]
      lines.append("Link occurrences: " + (resolution.isEmpty ? "0" : resolution.keys.sorted().map { "\(number(resolution[$0])) \($0)" }.joined(separator: ", ")))
      lines.append("Resolved occurrences: \(number(value["targetsInsideSelection"])) inside selection; \(number(value["targetsOutsideSelection"])) outside; \(number(value["selfLinks"])) self-links.")
      lines.append("Sources: selected Markdown files. Resolution namespace: full project.")
      lines.append("\(total(value["namedRelationships"])) named relationship groups" + (metricComplete[metric] == false ? " observed under incomplete evidence." : "."))
      let body = rows(value["namedRelationships"]).map { row -> [String] in
        let fields = row.objectValue ?? [:]
        return [fields["type"]?.stringValue ?? "", fields["relationship"]?.stringValue ?? "", String(number(fields["documents"])), String(number(fields["assertions"]))]
      }
      if !body.isEmpty { lines += [""] + table(["Type", "Relationship", "Documents", "Assertions"], body) }
      omitted(value["namedRelationships"])
      sample(value["ordinaryLinks"], label: "Example links:") { row in
        let fields = row.objectValue ?? [:]
        return (fields["subject"]?.stringValue ?? "") + " → " + (fields["object"]?.stringValue ?? "")
      }
      if total(value["notices"]) > 0 { lines.append("\(total(value["notices"])) interpretation notices; inspect --format json for diagnostic evidence.") }
    default: break
    }
    lines += limitations.map { "Incomplete: " + $0 }
    lines += ["\nScope: \(coverage.files) text files; \(coverage.skippedBinary) non-text files skipped. Source: \(source)."]
    lines += scopeNotes
    for hint in hints {
      lines += ["\n" + hint.explanation, "  " + hint.argv.map(Self.quote).joined(separator: " ")]
    }
    return lines.joined(separator: "\n")
  }
}
