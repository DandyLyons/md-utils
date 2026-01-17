//
//  GenerateTOC.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry {
  /// Generate a table of contents for Markdown files.
  struct GenerateTOC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "toc",
      abstract: "Generate a table of contents for Markdown files",
      discussion: """
        Generates a table of contents by extracting headings from Markdown files.
        Supports multiple output formats: Markdown, JSON, plain text, and HTML.

        By default, processes directories recursively and generates Markdown output
        with unordered links.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Minimum heading level to include (1-6, default: 1)"
    )
    var minLevel: Int = 1

    @Option(
      name: .long,
      help: "Maximum heading level to include (1-6, default: 6)"
    )
    var maxLevel: Int = 6

    @Flag(
      name: .long,
      help: "Generate flat TOC structure instead of hierarchical"
    )
    var flat: Bool = false

    @Flag(
      name: .long,
      help: "Disable slug generation for anchor links"
    )
    var noSlugs: Bool = false

    @Option(
      name: .long,
      help: "Output format: md-bullet-links, md-only-headings, tree, json, json-pretty, plain, html (default: md-only-headings)"
    )
    var format: OutputFormat = .mdOnlyHeadings

    mutating func run() async throws {
      // Validate level range
      guard minLevel >= 1 && minLevel <= 6 else {
        throw ValidationError("minLevel must be between 1 and 6")
      }
      guard maxLevel >= 1 && maxLevel <= 6 else {
        throw ValidationError("maxLevel must be between 1 and 6")
      }
      guard minLevel <= maxLevel else {
        throw ValidationError("minLevel must be <= maxLevel")
      }

      // Resolve paths
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      // Process each file
      for file in files {
        try await processFile(file, totalFiles: files.count)
      }
    }

    private func processFile(_ path: Path, totalFiles: Int) async throws {
      // Read file content
      let content: String = try path.read()

      // Parse document
      let doc = try MarkdownUtilities.MarkdownDocument(content: content)

      // Generate TOC
      let tocOptions = TOCGenerator.Options(
        minLevel: minLevel,
        maxLevel: maxLevel,
        generateSlugs: !noSlugs,
        includePositions: false,
        hierarchical: !flat
      )

      let toc = try await doc.generateTOC(options: tocOptions)

      // Render TOC
      let renderFormat = parseRenderFormat()
      let rendered = TOCRenderer.render(toc, as: renderFormat)

      // Output
      if totalFiles > 1 {
        print("# \(path)")
        print(rendered)
        print()
      } else {
        print(rendered)
      }
    }

    private func parseRenderFormat() -> TOCRenderer.Format {
      switch format {
      case .mdBulletLinks:
        return .mdBulletLinks
      case .mdOnlyHeadings:
        return .mdOnlyHeadings
      case .tree:
        return .tree
      case .json:
        return .json
      case .jsonPretty:
        return .jsonPretty
      case .plain:
        return .plain
      case .html:
        return .html
      }
    }
  }

  /// Output format for TOC rendering.
  enum OutputFormat: String, ExpressibleByArgument {
    case mdBulletLinks = "md-bullet-links"
    case mdOnlyHeadings = "md-only-headings"
    case tree
    case json
    case jsonPretty = "json-pretty"
    case plain
    case html
  }
}
