//
//  Dump.swift
//  md-utils
//
//  Dump entire frontmatter in various formats
//

import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit
import Yams
/// Adds Markdown document behavior to ``CLIEntry.FrontMatterCommands``.
///
/// See <doc:FrontmatterCommands> for workflow details.
extension CLIEntry.FrontMatterCommands {
  /// Dump entire frontmatter in specified format
  struct Dump: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "dump",
      abstract: "Dump entire frontmatter in specified format",
      discussion: NonMarkdownFrontMatterHelp.appendingForDump(to: """
        Outputs complete frontmatter as JSON, YAML, TOML, raw source, or plist.

        Supports multiple files and directory processing with recursive mode.

        SINGLE FILE:
          Single-file dumps output the frontmatter directly with no wrapper.
          The --format flag controls the output format.

        COLLECTION MODE:
          Directories and explicit file lists output a parseable object with three keys:
          "frontMatter" contains nonempty mappings with a "$path" key, "noFrontMatter"
          contains paths with no complete block, and "emptyFrontMatter" contains paths
          whose complete block has an empty mapping.
          The --include-delimiters flag is ignored in collection mode.

          Use --cat-headers for the legacy cat-style format (==> path <==).

        Examples:
          # Dump single file as JSON (default)
          md-utils fm dump post.md

          # Dump with YAML format
          md-utils fm dump post.md --format yaml

          # Dump with delimiters
          md-utils fm dump post.md --format yaml --include-delimiters

          # Dump multiple files as a categorized JSON object
          md-utils fm dump posts/ -r --format json

          # Dump multiple files with cat-style headers
          md-utils fm dump posts/ -r --cat-headers

          # Dump from specific directory
          md-utils fm dump posts/*.md --format yaml

        PIPING TO jq / yq:
          Collection mode outputs valid JSON or YAML, so you can pipe directly
          into jq or yq for further filtering and transformation.

          # List all titles
          md-utils fm dump posts/ -r | jq '.frontMatter[].title'

          # Find drafts
          md-utils fm dump posts/ -r | jq '[.frontMatter[] | select(.status == "draft")]'

          # Get paths of posts tagged "swift"
          md-utils fm dump posts/ -r | jq '[.frontMatter[] | select(.tags | index("swift")) | ."$path"]'

          # Same with yq (YAML output)
          md-utils fm dump posts/ -r --format yaml | yq '.frontMatter[].title'

          # Count entries
          md-utils fm dump posts/ -r | jq '.frontMatter | length'
        """),
      aliases: ["d"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .shortAndLong, help: "Output format (json, yaml, toml, raw, plist)")
    var format: OutputFormat = .json

    @Flag(name: .long, help: "Include format-appropriate delimiters in YAML/TOML/raw output")
    var includeDelimiters: Bool = false

    @Flag(name: .long, help: "Use cat-style headers (==> path <==) instead of collection output for multiple files")
    var catHeaders: Bool = false

    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      let files = try options.resolvedFrontMatterPaths(includeNonMarkdown: true)

      guard !files.isEmpty else {
        throw ValidationError("No supported files found to process")
      }

      let isSingleExplicitFile = options.paths.count == 1 && options.paths[0].isFile

      // A sole explicit file outputs directly. Directory scans and explicit file
      // lists keep the collection envelope even when only one file is selected.
      if isSingleExplicitFile {
        let file = files[0]
        do {
          let doc = try FrontMatterCLIReader.document(at: file, includeNonMarkdown: true)

          if includeDelimiters, let delimiter = outputDelimiter(for: doc) {
            Swift.print(delimiter)
          }

          try print(frontMatter: doc.frontMatter, format: format, sourceFormat: doc.frontMatterFormat)

          if includeDelimiters, let delimiter = outputDelimiter(for: doc) {
            Swift.print(delimiter)
          }
        } catch {
          CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
          throw ExitCode.failure
        }
        return
      }

      // Collection-oriented invocation
      var hasErrors = false
      if catHeaders {
        // Cat-style output with headers
        for (index, file) in files.enumerated() {
          Swift.print("==> \(file) <==")
          do {
            let doc = try FrontMatterCLIReader.document(at: file, includeNonMarkdown: true)

            if includeDelimiters, let delimiter = outputDelimiter(for: doc) {
              Swift.print(delimiter)
            }

            try print(frontMatter: doc.frontMatter, format: format, sourceFormat: doc.frontMatterFormat)

            if includeDelimiters, let delimiter = outputDelimiter(for: doc) {
              Swift.print(delimiter)
            }
          } catch {
            CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
            hasErrors = true
          }

          // Add empty line between files (except after last file)
          if index < files.count - 1 {
            Swift.print()
          }
        }
      } else {
        // Collection mode: categorize files by frontmatter state.
        var frontMatter: [[String: Any]] = []
        var noFrontMatter: [String] = []
        var emptyFrontMatter: [String] = []

        for file in files {
          do {
            let parsed = try FrontMatterCLIMutator.parsedFile(
              at: file,
              includeNonMarkdown: true
            )

            guard parsed.hasFrontMatterBlock else {
              noFrontMatter.append(file.string)
              continue
            }

            guard parsed.document.frontMatter.isEmpty == false else {
              emptyFrontMatter.append(file.string)
              continue
            }

            var dict = FrontMatterConversion.foundationValue(parsed.document.frontMatter)

            dict["$path"] = file.string
            frontMatter.append(dict)
          } catch {
            CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
            hasErrors = true
          }
        }

        let collection: [String: Any] = [
          "frontMatter": frontMatter,
          "noFrontMatter": noFrontMatter,
          "emptyFrontMatter": emptyFrontMatter,
        ]
        try printAny(collection, format: format)
      }
      if hasErrors { throw ExitCode.failure }
    }

    private func outputDelimiter(for document: MarkdownDocument) -> String? {
      switch format {
      case .yaml: FrontMatterFormat.yaml.delimiter
      case .toml: FrontMatterFormat.toml.delimiter
      case .raw: (document.frontMatterFormat ?? .yaml).delimiter
      case .json, .plist: nil
      }
    }
  }
}
