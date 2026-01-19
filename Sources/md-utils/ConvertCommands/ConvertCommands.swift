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

        Future formats (planned):
        - to-html: Convert Markdown to HTML
        - to-rtf: Convert Markdown to RTF

        By default, processes directories recursively and outputs
        converted files with the appropriate extension.
        """,
      subcommands: [
        ToText.self,
      ]
    )
  }
}
