//
//  Lines.swift
//  md-utils
//
//  Extract a range of lines from a file
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry {
  struct Lines: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "lines",
      abstract: "Extract a range of lines from a file",
      discussion: """
        Extract a specific range of lines from a file by line numbers (1-indexed).

        If the ending line number exceeds the total number of lines in the file,
        the command will return all the lines up to the end of the file.

        LIMITATIONS:
        - This command is designed to work with a single file at a time.

        EXAMPLES:

        Extract lines 5-10 from a file:
          md-utils lines example.md --start 5 --end 10

        Extract lines with line numbers shown:
          md-utils lines example.md -s 1 -e 20 --numbered
        """,
      aliases: ["l"]
    )

    @Argument(
      help: "Path to the file to read"
    )
    var file: String

    @Option(
      name: .shortAndLong,
      help: "Starting line number (1-indexed)"
    )
    var start: Int

    @Option(
      name: .shortAndLong,
      help: "Ending line number (1-indexed, inclusive)"
    )
    var end: Int

    @Flag(
      name: .shortAndLong,
      help: "Show line numbers in output"
    )
    var numbered: Bool = false

    func run() throws {
      // Validate line numbers
      guard start > 0 else {
        throw ValidationError("Start line must be greater than 0")
      }

      guard end >= start else {
        throw ValidationError("End line must be greater than or equal to start line")
      }

      // Read the file
      let path = Path(file)
      guard path.exists else {
        throw ValidationError("File does not exist: \(file)")
      }

      let contents = try path.read(.utf8)
      guard let lines = contents.substring(lines: start...end) else {
        throw ValidationError("File does not have enough lines to extract the specified range")
      }

      let toBePrinted: String
      if numbered {
        toBePrinted = lines.split(separator: "\n", omittingEmptySubsequences: false)
          .enumerated()
          .map { index, line in
            let lineNumber = start + index
            return "\(lineNumber): \(line)"
          }.joined(separator: "\n")
      } else {
        toBePrinted = String(lines)
      }
      print(toBePrinted)
    }
  }
}
