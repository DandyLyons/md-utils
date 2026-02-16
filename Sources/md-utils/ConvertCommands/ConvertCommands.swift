//
//  ConvertCommands.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry {
  /// Format conversion commands
  struct ConvertCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "convert",
      abstract: "Convert Markdown files to and from other formats",
      discussion: """
        Provides format conversion for Markdown files.

        Available commands:
        - to-text: Convert Markdown to plain text
        - to-csv: Convert Markdown files to CSV
        - to-rtf: Convert Markdown to RTF
        - from-rtf: Convert RTF to Markdown

        By default, processes directories recursively and outputs
        converted files with the appropriate extension.
        """,
      subcommands: [
        ToText.self,
        ToCSV.self,
        ToRTF.self,
        FromRTF.self,
      ]
    )
  }
}
