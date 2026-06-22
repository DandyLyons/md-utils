import MarkdownUtilities

extension ExploreRenderer {
  var hasExpansionOptions: Bool {
    expandedTitles.isEmpty == false
      || expandedPaths.isEmpty == false
      || expandedLines.isEmpty == false
      || expandedTitleContains.isEmpty == false
      || expandFrontmatter
      || expandPreamble
      || recursive
  }

  func sectionMetadata(_ section: ExploreSection) -> [String] {
    var parts = ["line \(section.headingLine)", plural(section.wordCount, "word"), plural(section.lineCount, "line")]
    if section.childSectionCount > 0 {
      parts.append(plural(section.childSectionCount, "section"))
    }
    return parts
  }

  func treeSectionMetadata(_ section: ExploreSection) -> [String] {
    ["h\(section.level)"] + sectionMetadata(section)
  }

  func frontmatterMetadata(_ frontmatter: ExploreFrontmatter) -> [String] {
    [
      lineRangeDescription(frontmatter.lineRange),
      plural(frontmatter.fieldCount, "field"),
      plural(frontmatter.lineRange.count, "line")
    ]
  }

  func preambleMetadata(_ preamble: ExplorePreamble) -> [String] {
    [
      lineRangeDescription(preamble.lineRange),
      plural(preamble.wordCount, "word"),
      plural(preamble.lineCount, "line")
    ]
  }

  func documentTreeMetadata() -> [String] {
    [plural(document.sourceLines.count, "line")]
  }

  func lineRangeDescription(_ range: ClosedRange<Int>) -> String {
    if range.lowerBound == range.upperBound {
      return "line \(range.lowerBound)"
    }
    return "lines \(range.lowerBound)-\(range.upperBound)"
  }

  func metadata(_ parts: [String]) -> String {
    "(" + parts.joined(separator: ", ") + ")"
  }

  func plural(_ count: Int, _ singular: String) -> String {
    if count == 1 {
      return "1 \(singular)"
    }

    return "\(count) \(singular)s"
  }
}
