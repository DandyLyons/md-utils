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
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "The frontmatter key to retrieve")
    var key: String

    mutating func run() async throws {
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false

      for file in files {
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
        let stringValue = formatNodeValue(value)
        if files.count > 1 {
          print("\(file): \(stringValue)")
        } else {
          print(stringValue)
        }
      }

      // Exit with error code if any keys were missing
      if hasErrors {
        throw ExitCode.failure
      }
    }

    /// Format a Yams.Node value for display
    private func formatNodeValue(_ node: Yams.Node) -> String {
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
        let items = sequence.map { formatNodeValue($0) }
        return "[\(items.joined(separator: ", "))]"
      }

      // Handle mappings/objects
      if let mapping = node.mapping {
        let pairs = mapping.map { key, value in
          "\(formatNodeValue(key)): \(formatNodeValue(value))"
        }
        return "{\(pairs.joined(separator: ", "))}"
      }

      // Fallback
      return String(describing: node)
    }
  }
}
