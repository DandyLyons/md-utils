//
//  ListSections.swift
//  md-utils
//

import ArgumentParser
/// Adds command implementations to ``CLIEntry``.
///
/// See <doc:ContentSelectionCommands> for workflow details.
extension CLIEntry {
  /// List sections/headings from a Markdown document.
  struct ListSections: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List sections/headings in a Markdown document",
      discussion: """
        Lists document sections by extracting Markdown headings in document order.

        EXAMPLES:
          md-utils section list document.md
          md-utils section list document.md --min-level 2 --max-level 4
          md-utils section list document.md --format plain

        This command is the same as `md-utils toc <file>`.
        """,
      aliases: ["ls"]
    )
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:ContentSelectionCommands> for workflow details.
    @OptionGroup var toc: GenerateTOC

    mutating func run() async throws {
      var command: CLIEntry.GenerateTOC = toc
      try await command.run()
    }
  }
}
