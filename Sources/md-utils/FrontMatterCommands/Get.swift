//
//  Get.swift
//  md-utils
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
  /// Retrieve a frontmatter value by key
  struct Get: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "get",
      abstract: "Get a frontmatter value by key",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Retrieves the value of a specified key from YAML or TOML frontmatter.

        If the key doesn't exist, the command exits with an error code.
        When processing multiple files, the filename is included in the output.

        JSON OUTPUT (default)
        Returns an array of objects, one per file:

          [
            { "path": "/path/to/file.md", "value": "hello" },
            { "path": "/path/to/null.md",  "value": null   },
            { "path": "/path/to/other.md"                  }
          ]

        "value" present  → key was found; typed JSON value (string, number, bool, array, object)
        "value": null    → key exists with a YAML null value
        "value" absent   → key not present in frontmatter

        Pipe to jq for filtering:
          md-utils fm get --key title posts/ | jq 'map(select(has("value")))'
          md-utils fm get --key title posts/ | jq 'map(select(.value != null))'
        """)
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var lineCommentOptions: LineCommentFrontMatterOptions

    @Option(name: .long, help: "The frontmatter key to retrieve")
    var key: String

    @Option(name: .long, help: "Output format (json, inline, bullets, numbered-list); json is the default")
    var format: OutputFormat = .json

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false
    /// Defines the `Get` command behavior.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    enum OutputFormat: String, ExpressibleByArgument {
      case json
      case inline
      case bullets
      case numberedList = "numbered-list"
    }
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      let timer = CommandTimer()
      let files = try options.resolvedFrontMatterPaths(
        includeNonMarkdown: includeNonMD,
        lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
      )

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false
      var processedCount = 0

      if format == .json {
        var results: [[String: Any]] = []
        for file in files {
          do {
            let doc = try FrontMatterCLIReader.document(
              at: file,
              includeNonMarkdown: includeNonMD,
              lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
            )

            if let value = doc.getValue(forKey: key) {
              // Key found — include "value" (NSNull if YAML value is null)
              let jsonValue = FrontMatterConversion.foundationValue(value)
              results.append(["path": file.string, "value": jsonValue])
            } else {
              // Key missing — omit "value" key; absence is the signal
              results.append(["path": file.string])
              hasErrors = true
            }
            processedCount += 1
          } catch {
            CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
            hasErrors = true
          }
        }
        let jsonString = try YAMLConversion.anyToJSON(results, options: [.prettyPrinted])
        print(jsonString)
        timer.writeStatus("Read frontmatter key \"\(key)\" from \(processedCount) file(s)")
        if hasErrors { throw ExitCode.failure }
        return
      }

      for file in files {
        do {
          let doc = try FrontMatterCLIReader.document(
            at: file,
            includeNonMarkdown: includeNonMD,
            lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
          )
          processedCount += 1

          guard let value = doc.getValue(forKey: key) else {
            if files.count > 1 {
              print("\(file): <missing>")
            }
            hasErrors = true
            continue
          }

          // Print value (use .string for scalars, format for complex types)
          let stringValue = formatNodeValue(value, format: format)
          if files.count > 1 {
            print("\(file): \(stringValue)")
          } else {
            print(stringValue)
          }
        } catch {
          CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
          hasErrors = true
          continue
        }
      }

      timer.writeStatus("Read frontmatter key \"\(key)\" from \(processedCount) file(s)")
      // Exit with error code if any keys were missing or files had invalid YAML
      if hasErrors {
        throw ExitCode.failure
      }
    }

    /// Formats a frontmatter value for display.
    private func formatNodeValue(_ node: FrontMatterValue, format: OutputFormat) -> String {
      switch node {
      case .null:
        return "null"
      case .string(let value):
        return value
      case .integer(let value):
        return String(value)
      case .number(let value):
        return String(value)
      case .boolean(let value):
        return String(value)
      case .offsetDateTime, .localDateTime, .localDate, .localTime:
        return String(describing: FrontMatterConversion.foundationValue(node))
      case .array(let sequence):
        let items = sequence.map { formatNodeValue($0, format: .inline) }

        switch format {
        case .json, .inline:
          return "[\(items.joined(separator: ", "))]"
        case .bullets:
          return items.map { "- \($0)" }.joined(separator: "\n")
        case .numberedList:
          return items.enumerated().map { index, item in
            "\(index + 1). \(item)"
          }.joined(separator: "\n")
        }
      case .object(let mapping):
        let pairs = mapping.map { key, value in
          "\(key): \(formatNodeValue(value, format: .inline))"
        }
        return "{\(pairs.joined(separator: ", "))}"
      }
    }
  }
}
