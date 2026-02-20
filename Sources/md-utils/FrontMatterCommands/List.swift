//
//  List.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry.FrontMatterCommands {
  /// List all keys in frontmatter
  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List all keys in frontmatter",
      discussion: """
        Lists all keys present in the YAML frontmatter of Markdown files.

        When processing multiple files, each file's keys are prefixed with the filename.
        Keys are listed one per line in alphabetical order.
        """,
      aliases: ["ls"]
    )

    @OptionGroup var options: GlobalOptions

    mutating func run() async throws {
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false

      for file in files {
        do {
          let content: String = try file.read()
          let doc = try MarkdownDocument(content: content)

          // Extract keys from frontmatter
          let keys = Array(doc.frontMatter.keys)
            .compactMap { $0.string }
            .sorted()

          // Print keys
          if keys.isEmpty {
            print("  (no frontmatter keys)")
            return
          }
          if files.count > 1 {
            // Multiple files: prefix with filename
            print("======================")
            print("\(file):")
            for key in keys {
              print("  \(key)")
            }
          } else {
            // Single file: just list keys
            for key in keys {
              print(key)
            }
          }
        } catch {
          fputs("error: \(file): \(error.localizedDescription)\n", stderr)
          hasErrors = true
          continue
        }
      }

      if hasErrors { throw ExitCode.failure }
    }
  }
}
