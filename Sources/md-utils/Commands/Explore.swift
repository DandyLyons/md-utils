//
//  Explore.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

/// Adds command implementations to ``CLIEntry``.
extension CLIEntry {
  /// Progressively disclose a Markdown document by heading sections.
  struct Explore: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "explore",
      abstract: "Progressively disclose a Markdown document by heading sections",
      discussion: """
        Examples:
          md-utils explore README.md
          md-utils explore README.md --expand "Usage"
          md-utils explore README.md --expand-path "Usage/Examples"
          md-utils explore README.md --expand-line 42
          md-utils explore README.md --expand-line 42,57,81
          md-utils explore README.md --expand "Usage" --recursive
          md-utils explore README.md --expand-title-contains "Chapter 7"
          md-utils explore README.md --expand-frontmatter --expand-preamble
          md-utils explore README.md --format markdown-no-stubs --expand "Usage"
        """
    )

    @Argument(
      help: "Path to one Markdown file to explore",
      completion: .file(),
      transform: { Path($0) }
    )
    var path: Path

    @Option(
      name: [.customShort("e"), .customLong("expand")],
      help: "Expand all sections whose heading title exactly matches this value"
    )
    var expandedTitles: [String] = []

    @Option(
      name: [.customShort("P"), .customLong("expand-path")],
      help: "Expand all sections exactly matching a slash-separated heading path"
    )
    var expandedPaths: [String] = []

    @Option(
      name: [.customShort("l"), .customLong("expand-line")],
      help: "Expand sections whose headings start on these source lines; accepts repeated options or comma-separated values"
    )
    var expandedLineValues: [ExpandLineValue] = []

    var expandedLines: [Int] {
      expandedLineValues.flatMap(\.values)
    }

    @Option(
      name: [.customShort("C"), .customLong("expand-title-contains")],
      help: "Expand all sections whose heading title contains this value, case-insensitively"
    )
    var expandedTitleContains: [String] = []

    @Flag(
      name: [.customShort("F"), .customLong("expand-frontmatter")],
      help: "Expand YAML frontmatter when present"
    )
    var expandFrontmatter: Bool = false

    @Flag(
      name: [.customShort("p"), .customLong("expand-preamble")],
      help: "Expand content before the first heading when present"
    )
    var expandPreamble: Bool = false

    @Flag(
      name: [.customShort("r"), .customLong("recursive")],
      help: "Expand selected sections recursively"
    )
    var recursive: Bool = false

    @Option(
      name: [.customShort("f"), .customLong("format")],
      help: "Output format: terminal, markdown, or markdown-no-stubs"
    )
    var format: ExploreFormat = .terminal

    mutating func run() async throws {
      guard path.exists else {
        throw ValidationError("Path does not exist: \(path)")
      }

      guard path.isDirectory == false else {
        throw ValidationError("Explore requires one Markdown file; directories are not supported")
      }

      let content: String = try path.read()
      let document = try await ExploreDocument.build(from: content)
      let renderer = ExploreRenderer(
        document: document,
        expandedTitles: expandedTitles,
        expandedPaths: expandedPaths,
        expandedLines: expandedLines,
        expandedTitleContains: expandedTitleContains,
        expandFrontmatter: expandFrontmatter,
        expandPreamble: expandPreamble,
        recursive: recursive,
        format: format
      )

      print(renderer.render(), terminator: "")
    }
  }

  /// Output format for the explore command.
  enum ExploreFormat: String, ExpressibleByArgument {
    case terminal
    case markdown
    case markdownNoStubs = "markdown-no-stubs"
  }
}

struct ExploreRenderer {
  let document: ExploreDocument
  let expandedTitles: [String]
  let expandedPaths: [String]
  let expandedLines: [Int]
  let expandedTitleContains: [String]
  let expandFrontmatter: Bool
  let expandPreamble: Bool
  let recursive: Bool
  let format: CLIEntry.ExploreFormat

  func render() -> String {
    switch format {
    case .terminal:
      return renderTerminal()
    case .markdown:
      return renderMarkdown(includeCollapsedStubs: true)
    case .markdownNoStubs:
      return renderMarkdown(includeCollapsedStubs: false)
    }
  }

  private func renderTerminal() -> String {
    let expansion = makeExpansion()
    var lines = [CLIStyle.hint("Hint: expand by title (-e), title contains (-C), path (-P), line (-l), frontmatter (-F), or preamble (-p).")]
    lines.append(contentsOf: expansion.warnings)

    if let frontmatter = document.frontmatter {
      if expandFrontmatter {
        lines.append("▼ \(CLIStyle.exploreLabel("Frontmatter"))")
        lines.append(document.sourceText(in: frontmatter.lineRange))
      } else {
        let frontmatterMetadata = CLIStyle.muted(metadata([plural(frontmatter.fieldCount, "field")]))
        lines.append("► \(CLIStyle.exploreLabel("Frontmatter")) \(frontmatterMetadata)")
      }
    }

    if let preamble = document.preamble {
      if expandPreamble {
        lines.append("▼ \(CLIStyle.exploreLabel("Preamble"))")
        lines.append(document.sourceText(in: preamble.lineRange))
      } else {
        let preambleMetadata = CLIStyle.muted(
          metadata([plural(preamble.wordCount, "word"), plural(preamble.lineCount, "line")])
        )
        lines.append("► \(CLIStyle.exploreLabel("Preamble")) \(preambleMetadata)")
      }
    }

    for section in document.sections {
      renderTerminalSection(section, topLevel: nil, expansion: expansion, into: &lines)
    }

    return lines.joined(separator: "\n") + "\n"
  }

  private func renderMarkdown(includeCollapsedStubs: Bool) -> String {
    let expansion = makeExpansion()
    var blocks: [String] = []

    if expandFrontmatter, let frontmatter = document.frontmatter {
      blocks.append(document.sourceText(in: frontmatter.lineRange))
    }

    if expandPreamble, let preamble = document.preamble {
      blocks.append(document.sourceText(in: preamble.lineRange))
    }

    for section in document.sections {
      renderMarkdownSection(
        section,
        topLevel: nil,
        expansion: expansion,
        includeCollapsedStubs: includeCollapsedStubs,
        into: &blocks
      )
    }

    return blocks.joined(separator: "\n") + (blocks.isEmpty ? "" : "\n")
  }

  private func renderTerminalSection(
    _ section: ExploreSection,
    topLevel: Int?,
    expansion: Expansion,
    into lines: inout [String]
  ) {
    guard shouldRender(section, topLevel: topLevel, expansion: expansion) else {
      return
    }

    if expansion.expandedIds.contains(section.id) || expansion.ancestorIds.contains(section.id) {
      lines.append("▼ \(styledHeading(section)) \(CLIStyle.muted(metadata(["line \(section.headingLine)"])))")
      if expansion.expandedIds.contains(section.id), let bodyLineRange = section.bodyLineRange {
        let body = document.sourceText(in: bodyLineRange)
        if body.isEmpty == false {
          lines.append(body)
        }
      }

      for child in section.children {
        renderTerminalSection(child, topLevel: child.level, expansion: expansion, into: &lines)
      }
    } else {
      let collapsedMetadata = CLIStyle.muted(metadata(sectionMetadata(section)))
      lines.append("► \(styledHeading(section)) \(collapsedMetadata)")
    }
  }

  private func styledHeading(_ section: ExploreSection) -> String {
    CLIStyle.markdownHeading(section.headingMarkdown, level: section.level)
  }

  private func renderMarkdownSection(
    _ section: ExploreSection,
    topLevel: Int?,
    expansion: Expansion,
    includeCollapsedStubs: Bool,
    into blocks: inout [String]
  ) {
    guard shouldRender(section, topLevel: topLevel, expansion: expansion) else {
      return
    }

    let isExpanded = expansion.expandedIds.contains(section.id)
    let isAncestor = expansion.ancestorIds.contains(section.id)
    guard includeCollapsedStubs || isExpanded || isAncestor else {
      return
    }

    blocks.append(section.headingMarkdown)
    if isExpanded || isAncestor {
      if let bodyLineRange = section.bodyLineRange {
        if isExpanded {
          let body = document.sourceText(in: bodyLineRange)
          if body.isEmpty == false {
            blocks.append(body)
          }
        }
      }

      for child in section.children {
        renderMarkdownSection(
          child,
          topLevel: child.level,
          expansion: expansion,
          includeCollapsedStubs: includeCollapsedStubs,
          into: &blocks
        )
      }
    }
  }

  private func shouldRender(_ section: ExploreSection, topLevel: Int?, expansion: Expansion) -> Bool {
    topLevel == nil
      || section.level == topLevel
      || expansion.expandedIds.contains(section.id)
      || expansion.ancestorIds.contains(section.id)
  }

  private func makeExpansion() -> Expansion {
    let allSections = document.allSections
    var explicitIds: Set<Int> = []
    var warnings: [String] = []

    for title in expandedTitles {
      let matches = allSections.filter { $0.title == title }
      if matches.isEmpty {
        warnings.append(contentsOf: warningLines(
          option: "--expand",
          value: title,
          suggestion: suggestedTitle(for: title, in: allSections)
        ))
      }
      explicitIds.formUnion(matches.map(\.id))
    }

    for path in expandedPaths {
      let matches = allSections.filter { $0.path.joined(separator: "/") == path }
      if matches.isEmpty {
        warnings.append(contentsOf: warningLines(
          option: "--expand-path",
          value: path,
          suggestion: suggestedPath(for: path, in: allSections)
        ))
      }
      explicitIds.formUnion(matches.map(\.id))
    }

    for line in expandedLines {
      let matches = allSections.filter { $0.headingLine == line }
      if matches.isEmpty {
        warnings.append("Warning: no heading matched --expand-line \(line)")
      }
      explicitIds.formUnion(matches.map(\.id))
    }

    for titleSubstring in expandedTitleContains {
      let normalizedSubstring = titleSubstring.lowercased()
      let matches = allSections.filter { $0.title.lowercased().contains(normalizedSubstring) }
      if matches.isEmpty {
        warnings.append("Warning: no heading matched --expand-title-contains \"\(titleSubstring)\"")
      }
      explicitIds.formUnion(matches.map(\.id))
    }

    var expandedIds = explicitIds
    if recursive {
      for section in allSections where explicitIds.contains(section.id) {
        expandedIds.formUnion(section.descendants.map(\.id))
      }
    }

    var ancestorIds: Set<Int> = []
    for targetId in expandedIds {
      ancestorIds.formUnion(ancestorIdsForSection(id: targetId, in: document.sections))
    }

    return Expansion(expandedIds: expandedIds, ancestorIds: ancestorIds, warnings: warnings)
  }

  private func warningLines(option: String, value: String, suggestion: String?) -> [String] {
    var lines = ["Warning: no heading matched \(option) \"\(value)\""]
    if let suggestion {
      lines.append("Did you mean: \(suggestion)")
    }
    return lines
  }

  private func suggestedTitle(for target: String, in sections: [ExploreSection]) -> String? {
    suggestedValue(for: target, candidates: sections.map(\.title))
  }

  private func suggestedPath(for target: String, in sections: [ExploreSection]) -> String? {
    suggestedValue(for: target, candidates: sections.map { $0.path.joined(separator: "/") })
  }

  private func suggestedValue(for target: String, candidates: [String]) -> String? {
    let normalizedTarget = target.lowercased()
    if let exact = candidates.first(where: { $0.lowercased() == normalizedTarget }) {
      return exact
    }
    if let prefix = candidates.first(where: { $0.lowercased().hasPrefix(normalizedTarget) }) {
      return prefix
    }
    return candidates.first(where: { $0.lowercased().contains(normalizedTarget) })
  }

  private func ancestorIdsForSection(id: Int, in sections: [ExploreSection]) -> Set<Int> {
    for section in sections {
      if section.id == id {
        return []
      }

      let childAncestors = ancestorIdsForSection(id: id, in: section.children)
      if childAncestors.isEmpty == false || section.children.contains(where: { $0.id == id }) {
        return childAncestors.union([section.id])
      }
    }

    return []
  }

  private func sectionMetadata(_ section: ExploreSection) -> [String] {
    var parts = ["line \(section.headingLine)", plural(section.wordCount, "word"), plural(section.lineCount, "line")]
    if section.childSectionCount > 0 {
      parts.append(plural(section.childSectionCount, "section"))
    }
    return parts
  }

  private func metadata(_ parts: [String]) -> String {
    "(" + parts.joined(separator: ", ") + ")"
  }

  private func plural(_ count: Int, _ singular: String) -> String {
    if count == 1 {
      return "1 \(singular)"
    }

    return "\(count) \(singular)s"
  }
}

private struct Expansion {
  let expandedIds: Set<Int>
  let ancestorIds: Set<Int>
  let warnings: [String]
}

struct ExpandLineValue: ExpressibleByArgument, Equatable {
  let values: [Int]

  init?(argument: String) {
    guard argument.contains(" ") == false else {
      return nil
    }

    let parts = argument.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.isEmpty == false else {
      return nil
    }

    var parsedValues: [Int] = []
    for part in parts {
      guard let value = Int(part), value > 0 else {
        return nil
      }
      parsedValues.append(value)
    }

    self.values = parsedValues
  }
}
