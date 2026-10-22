//
//  ConvertCommands.swift
//  md-utils
//

import ArgumentParser
/// Adds command implementations to ``CLIEntry``.
///
/// See <doc:ConversionCommands> for workflow details.
extension CLIEntry {
  /// Format conversion commands
  struct ConvertCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "convert",
      abstract: "Convert Markdown files to other formats",
      discussion: """
        Provides format conversion for Markdown files.

        Available commands:
        - to-text: Convert Markdown to plain text
        - to-csv: Combine YAML/TOML frontmatter and optional bodies into one CSV file

        Directories are processed recursively by default. to-text writes one
        file or stdin to stdout; batches require --output ./output/ or --in-place.
        to-csv writes a CSV file, not stdout. See each subcommand's --help.
        """,
      subcommands: [
        ToText.self,
        ToCSV.self,
      ]
    )
  }
}
