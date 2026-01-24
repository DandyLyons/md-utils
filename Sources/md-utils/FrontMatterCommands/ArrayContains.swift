//
//  ArrayContains.swift
//  md-utils
//
//  Check if arrays in frontmatter contain specific values
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry.FrontMatterCommands.ArrayCommands {
  struct Contains: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "contains",
      abstract: "Find files where an array contains a specific value",
      discussion: """
        Search for files whose frontmatter contains an array with a specific value.

        This command performs case-sensitive string comparison only.
        Currently, boolean, null, integer, and float values are not supported.

        Files where the key doesn't exist or the value is not an array are silently
        skipped.

        EXAMPLES:
          # Find files where tags array contains "swift"
          md-utils fm array contains --key tags --value swift posts/

          # Find files with specific alias
          md-utils fm array contains --key aliases --value Blue ./

        PIPING TO OTHER COMMANDS:
          The command outputs file paths (one per line), making it ideal for piping:

          # Bulk update: mark all posts tagged "swift" as published
          md-utils fm array contains --key tags --value swift posts/ | xargs md-utils fm set --key published --value true

          # Chain operations
          md-utils fm array contains --key tags --value tutorial . | while read -r file; do
            md-utils fm set "$file" --key featured --value true
          done

          # Find and list frontmatter
          md-utils fm array contains --key categories --value tech . | xargs md-utils fm list

        INVERT RESULTS:
          Use --invert to find files that DON'T contain the value:
          md-utils fm array contains --key tags --value deprecated --invert posts/
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .shortAndLong, help: "The frontmatter key to check (must be an array)")
    var key: String

    @Option(name: .shortAndLong, help: "The value to search for in the array (string comparison only)")
    var value: String

    @Flag(name: .long, help: "Invert results: show files that DON'T contain the value")
    var invert: Bool = false

    @Flag(name: .long, help: "Case-insensitive comparison")
    var caseInsensitive: Bool = false

    mutating func run() async throws {
      var matchingFiles: [String] = []
      let paths = try options.resolvedPaths()

      guard !paths.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      for path in paths {
        // 1. Parse file
        let content: String
        let doc: MarkdownDocument
        do {
          content = try path.read()
          doc = try MarkdownDocument(content: content)
        } catch {
          continue
        }

        // 2. Check if key exists and is an array (skip if not)
        let sequence: Yams.Node.Sequence
        do {
          sequence = try ArrayHelpers.validateArrayKey(key, in: doc, path: path)
        } catch {
          continue
        }

        // 3. Search for the value in the sequence
        let found = ArrayHelpers.containsValue(value, in: sequence, caseInsensitive: caseInsensitive)

        // 4. Apply invert logic
        let matches = invert ? !found : found

        if matches {
          matchingFiles.append(path.absolute().string)
        }
      }

      // 5. Output results
      try outputResults(matchingFiles)
    }

    private func outputResults(_ matchingFiles: [String]) throws {
      if matchingFiles.isEmpty {
        // Print to stderr so it doesn't interfere with piping
        let invertMsg = invert ? " NOT" : ""
        fputs("No files found where '\(key)' array\(invertMsg) contains '\(value)'\n", stderr)
        throw ExitCode.failure
      } else {
        print(matchingFiles.joined(separator: "\n"))
      }
    }
  }
}
