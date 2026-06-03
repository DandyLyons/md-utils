//
//  ListSections.swift
//  md-utils
//

import ArgumentParser

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

    @OptionGroup var toc: GenerateTOC

    mutating func run() async throws {
      var command: CLIEntry.GenerateTOC = toc
      try await command.run()
    }
  }
}
