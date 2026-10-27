import Foundation

extension SurveyReport {
  /// Apply shared terminal styles after layout, so ANSI bytes never affect column widths.
  /// JSON and the plain renderer remain independent of presentation and color detection.
  func coloredText(overview: Bool = false) -> String {
    let explanations = Set(hints.map(\.explanation))
    var inTable = false
    return text(overview: overview).components(separatedBy: "\n").map { line in
      let indent = String(line.prefix { $0 == " " })
      let content = String(line.dropFirst(indent.count))
      if content.isEmpty { inTable = false; return line }
      if content.hasPrefix("Survey: ") {
        return CLIStyle.schemaDescribeHeading("Survey:") + " " + CLIStyle.path(String(content.dropFirst(8)))
      }
      if content.hasPrefix("Error: ") {
        return indent + CLIStyle.error("Error:") + String(content.dropFirst("Error:".count))
      }
      if content.hasPrefix("Incomplete:") || content.hasPrefix("Incomplete metrics:") {
        return indent + CLIStyle.hint(content)
      }
      if explanations.contains(content) || content.hasPrefix("md-utils ") || content.contains("is an upcoming feature") {
        return indent + CLIStyle.hint(content)
      }
      if ["Scope:", "Scope note:", "Hidden entries", "Source:", "Skipped:", "Unreadable:"].contains(where: content.hasPrefix) {
        return indent + CLIStyle.metadata(content)
      }
      if ["Markdown Other text", "Rule  ", "Type  ", "Count  "].contains(where: content.hasPrefix) {
        inTable = true
        return indent + CLIStyle.schemaDescribeHeading(content)
      }
      if inTable, let separator = content.range(of: "  ") {
        let label = String(content[..<separator.lowerBound])
        let remaining = String(content[separator.lowerBound...])
        return indent + CLIStyle.exploreLabel(label) + remaining
      }
      if content.hasSuffix(":") {
        return indent + CLIStyle.schemaDescribeHeading(content)
      }
      if let separator = content.range(of: " — ") ?? content.range(of: " → ") {
        return indent + CLIStyle.path(String(content[..<separator.lowerBound])) + content[separator.lowerBound...]
      }
      if let separator = content.range(of: ": ") {
        let label = String(content[..<separator.lowerBound])
        let rest = String(content[separator.upperBound...])
        return indent + CLIStyle.exploreLabel(label + ":") + " " + Self.colorLeadingCount(rest)
      }
      return indent + Self.colorLeadingCount(content)
    }.joined(separator: "\n")
  }

  private static func colorLeadingCount(_ text: String) -> String {
    let number = text.prefix { $0.isNumber || $0 == "," || $0 == "." || $0 == "%" }
    guard number.first?.isNumber == true else { return text }
    return CLIStyle.exploreLabel(String(number)) + text.dropFirst(number.count)
  }
}
