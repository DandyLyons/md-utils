//
//  Get.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry.FrontMatterCommands {
  /// Retrieve a frontmatter value by key
  struct Get: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "get",
      abstract: "Get a frontmatter value by key",
      discussion: """
        Retrieves the value of a specified key from YAML frontmatter.

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
          md-utils fm get --key title posts/ | jq '.[] | select(has("value")) | .value'
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The frontmatter key to retrieve")
    var key: String

    @Option(name: .long, help: "Output format (json, inline, bullets, numbered-list); json is the default")
    var format: OutputFormat = .json

    enum OutputFormat: String, ExpressibleByArgument {
      case json
      case inline
      case bullets
      case numberedList = "numbered-list"
    }

    mutating func run() async throws {
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false

      if format == .json {
        var results: [[String: Any]] = []
        for file in files {
          do {
            let content: String = try file.read()
            let doc = try MarkdownDocument(content: content)

            if let value = doc.getValue(forKey: key) {
              // Key found — include "value" (NSNull if YAML value is null)
              let jsonValue = try YAMLConversion.safeNodeToSwiftValue(value)
              results.append(["path": file.string, "value": jsonValue])
            } else {
              // Key missing — omit "value" key; absence is the signal
              results.append(["path": file.string])
              hasErrors = true
            }
          } catch {
            fputs("error: \(file): \(error.localizedDescription)\n", stderr)
            hasErrors = true
          }
        }
        let jsonString = try YAMLConversion.anyToJSON(results, options: [.prettyPrinted])
        print(jsonString)
        if hasErrors { throw ExitCode.failure }
        return
      }

      for file in files {
        do {
          let content: String = try file.read()
          let doc = try MarkdownDocument(content: content)

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
          fputs("error: \(file): \(error.localizedDescription)\n", stderr)
          hasErrors = true
          continue
        }
      }

      // Exit with error code if any keys were missing or files had invalid YAML
      if hasErrors {
        throw ExitCode.failure
      }
    }

    /// Format a Yams.Node value for display
    private func formatNodeValue(_ node: Yams.Node, format: OutputFormat) -> String {
      // Handle scalar values
      if let string = node.string {
        return string
      }

      // Handle numbers
      if let int = node.int {
        return String(int)
      }

      if let float = node.float {
        return String(float)
      }

      // Handle booleans
      if let bool = node.bool {
        return String(bool)
      }

      // Handle arrays
      if let sequence = node.sequence {
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
      }

      // Handle mappings/objects
      if let mapping = node.mapping {
        let pairs = mapping.map { key, value in
          "\(formatNodeValue(key, format: .inline)): \(formatNodeValue(value, format: .inline))"
        }
        return "{\(pairs.joined(separator: ", "))}"
      }

      // Fallback
      return String(describing: node)
    }
  }
}
