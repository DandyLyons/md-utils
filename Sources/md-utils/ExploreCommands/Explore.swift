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
          md-utils explore README.md --tree
          md-utils explore README.md --tree-section-title "Usage"
          md-utils explore README.md --tree-section-line 42,57
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
      name: .customLong("tree"),
      help: "Render a compact tree for the entire file without body contents"
    )
    var tree: Bool = false

    @Option(
      name: .customLong("tree-section-title"),
      help: "Render a compact descendant tree for sections whose heading title exactly matches this value"
    )
    var treeSectionTitles: [String] = []

    @Option(
      name: .customLong("tree-section-line"),
      help: "Render compact descendant trees for headings on these source lines; accepts repeated options or comma-separated values"
    )
    var treeSectionLineValues: [ExpandLineValue] = []

    var treeSectionLines: [Int] {
      treeSectionLineValues.flatMap(\.values)
    }

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

      let hasTreeSectionTargets = treeSectionTitles.isEmpty == false || treeSectionLines.isEmpty == false
      if (tree || hasTreeSectionTargets), format != .terminal {
        throw ValidationError("Tree output is only supported with --format terminal")
      }

      if tree, hasTreeSectionTargets {
        throw ValidationError("Use either --tree or --tree-section-title/--tree-section-line, not both")
      }

      let content: String = try path.read()
      let document = try await ExploreDocument.build(from: content)
      let renderer = ExploreRenderer(
        document: document,
        sourceName: path.lastComponent,
        expandedTitles: expandedTitles,
        expandedPaths: expandedPaths,
        expandedLines: expandedLines,
        expandedTitleContains: expandedTitleContains,
        tree: tree,
        treeSectionTitles: treeSectionTitles,
        treeSectionLines: treeSectionLines,
        expandFrontmatter: expandFrontmatter,
        expandPreamble: expandPreamble,
        recursive: recursive,
        format: format
      )

      print(renderer.render(), terminator: "")
    }
  }
}
