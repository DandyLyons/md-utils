//
//  SectionCommands.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry {
  /// Section manipulation commands
  struct SectionCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "section",
      abstract: "Manipulate sections (headings + nested content) in a Markdown document.",
      discussion: """
        Provides commands for moving sections (heading + all nested content)
        within a Markdown document.

        Sections are moved among their siblings — headings at the same depth level
        under the same parent. This preserves document hierarchy.

        Available commands:
        - move-up: Move a section up by one position
        - move-down: Move a section down by one position
        - move-to: Move a section to a specific position

        Use --index to specify which heading to move (1-based indexing).
        Use --name to specify by heading text (case-insensitive by default).
        Use --in-place to modify files directly instead of outputting to stdout.
        """,
      subcommands: [
        MoveSectionUp.self,
        MoveSectionDown.self,
        MoveSectionTo.self,
      ],
      aliases: ["sect"]
    )
  }
}
