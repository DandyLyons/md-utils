//
//  Dump.swift
//  md-utils
//
//  Dump entire frontmatter in various formats
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry.FrontMatterCommands {
  /// Dump entire frontmatter in specified format
  struct Dump: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "dump",
      abstract: "Dump entire frontmatter in specified format",
      discussion: """
        Outputs the complete frontmatter from files in various formats: JSON, YAML, raw, or plist.

        Supports multiple files and directory processing with recursive mode.

        SINGLE FILE:
          Single-file dumps output the frontmatter directly with no wrapper.
          The --format flag controls the output format.

        MULTIPLE FILES:
          By default, multiple files output a single parseable collection (JSON array,
          YAML sequence, or plist array) with a "$path" key injected into each entry.
          The --include-delimiters flag is ignored in collection mode.

          Use --cat-headers for the legacy cat-style header format (==> path <==).

        Examples:
          # Dump single file as JSON (default)
          md-utils fm dump post.md

          # Dump with YAML format
          md-utils fm dump post.md --format yaml

          # Dump with delimiters
          md-utils fm dump post.md --format yaml --include-delimiters

          # Dump multiple files as JSON array with $path
          md-utils fm dump posts/ -r --format json

          # Dump multiple files with cat-style headers
          md-utils fm dump posts/ -r --cat-headers

          # Dump from specific directory
          md-utils fm dump posts/*.md --format yaml

        PIPING TO jq / yq:
          Collection mode outputs valid JSON or YAML, so you can pipe directly
          into jq or yq for further filtering and transformation.

          # List all titles
          md-utils fm dump posts/ -r | jq '.[].title'

          # Find drafts
          md-utils fm dump posts/ -r | jq '[.[] | select(.status == "draft")]'

          # Get paths of posts tagged "swift"
          md-utils fm dump posts/ -r | jq '[.[] | select(.tags | index("swift")) | ."$path"]'

          # Same with yq (YAML output)
          md-utils fm dump posts/ -r --format yaml | yq '.[].title'

          # Count entries
          md-utils fm dump posts/ -r | jq 'length'
        """,
      aliases: ["d"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .shortAndLong, help: "Output format (json, yaml, raw, plist)")
    var format: OutputFormat = .json

    @Flag(name: .long, help: "Include --- delimiters in YAML/raw output")
    var includeDelimiters: Bool = false

    @Flag(name: .long, help: "Use cat-style headers (==> path <==) instead of collection output for multiple files")
    var catHeaders: Bool = false

    mutating func run() async throws {
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      let isMultipleFiles = files.count > 1

      // Single file: output directly
      if !isMultipleFiles {
        let file = files[0]
        let content: String = try file.read()
        let doc = try MarkdownDocument(content: content)

        if includeDelimiters && (format == .yaml || format == .raw) {
          Swift.print("---")
        }

        try print(node: .mapping(doc.frontMatter), format: format)

        if includeDelimiters && (format == .yaml || format == .raw) {
          Swift.print("---")
        }
        return
      }

      // Multiple files
      if catHeaders {
        // Cat-style output with headers
        for (index, file) in files.enumerated() {
          Swift.print("==> \(file) <==")

          let content: String = try file.read()
          let doc = try MarkdownDocument(content: content)

          if includeDelimiters && (format == .yaml || format == .raw) {
            Swift.print("---")
          }

          try print(node: .mapping(doc.frontMatter), format: format)

          if includeDelimiters && (format == .yaml || format == .raw) {
            Swift.print("---")
          }

          // Add empty line between files (except after last file)
          if index < files.count - 1 {
            Swift.print()
          }
        }
      } else {
        // Collection mode: single parseable document with $path metadata
        let constructor = Yams.Constructor.default
        var collection: [[String: Any]] = []

        for file in files {
          let content: String = try file.read()
          let doc = try MarkdownDocument(content: content)
          let node = Yams.Node.mapping(doc.frontMatter)

          guard var dict = constructor.any(from: node) as? [String: Any] else {
            continue
          }

          dict["$path"] = file.string
          collection.append(dict)
        }

        try printAny(collection, format: format)
      }
    }
  }
}
