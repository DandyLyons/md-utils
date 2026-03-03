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
      abstract: "Convert Markdown files to other formats",
      discussion: """
        Provides format conversion for Markdown files.

        Available commands:
        - to-text: Convert Markdown to plain text
        - to-html: Convert Markdown to HTML
        - to-csv:  Convert Markdown files with frontmatter to CSV

        Future formats (planned):
        - to-rtf: Convert Markdown to RTF

        By default, processes directories recursively and outputs
        converted files with the appropriate extension.
        """,
      subcommands: [
        ToText.self,
        ToCSV.self,
        ToHTML.self,
      ]
    )
  }
}
