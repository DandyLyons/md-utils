//
//  HeadingCommands.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry {
  /// Heading manipulation commands
  struct HeadingCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "headings",
      abstract: "Manipulate heading levels in Markdown files",
      discussion: """
        Provides commands for adjusting heading levels in Markdown files.

        Available commands:
        - promote: Decrease heading levels (e.g., H2 → H1)
        - demote: Increase heading levels (e.g., H1 → H2)

        Use --index to specify which heading to modify (1-based indexing).
        Use --target-only to modify only the specified heading without its children.
        Use --in-place to modify files directly instead of outputting to stdout.
        """,
      subcommands: [
        PromoteHeading.self,
        DemoteHeading.self,
      ]
    )
  }
}
