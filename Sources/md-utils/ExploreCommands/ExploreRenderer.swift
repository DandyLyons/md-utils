import MarkdownUtilitiesCore

struct ExploreRenderer {
  let document: ExploreDocument
  let sourceName: String?
  let expandedTitles: [String]
  let expandedPaths: [String]
  let expandedLines: [Int]
  let expandedTitleContains: [String]
  let tree: Bool
  let treeSectionTitles: [String]
  let treeSectionLines: [Int]
  let expandFrontmatter: Bool
  let expandPreamble: Bool
  let recursive: Bool
  let format: CLIEntry.ExploreFormat

  func render() -> String {
    switch format {
    case .terminal:
      renderTerminal()
    case .markdown:
      renderMarkdown(includeCollapsedStubs: true)
    case .markdownNoStubs:
      renderMarkdown(includeCollapsedStubs: false)
    }
  }
}
