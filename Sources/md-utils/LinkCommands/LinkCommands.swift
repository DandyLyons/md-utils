//
//  LinkCommands.swift
//  md-utils
//

import ArgumentParser
/// Adds command implementations to ``CLIEntry``.
///
/// See <doc:WikilinkCommands> for workflow details.
extension CLIEntry {
  /// Wikilink analysis commands
  struct LinkCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "links",
      abstract: "List/check wikilinks, find backlinks, or preview style/type conversion",
      discussion: """
        [BETA] This feature is in beta. Results may be incomplete or incorrect.

        Provides commands for analyzing Obsidian-flavored wikilinks in Markdown \
        files. While wikilink syntax originated in Obsidian, these commands work \
        with any Markdown files that use [[wikilink]] syntax.

        Available commands:
        - list: List all wikilinks found in files with resolution status
        - check: Check for broken or ambiguous wikilinks
        - backlinks: Find files that link to a given target
        - convert: Preview styles (--to) or declared frontmatter repairs (--type)

        Use --root to specify the vault root directory for link resolution.
        convert requires --root and exactly one of --to or --type; add --in-place
        to write. list/check/backlinks default --root to the working directory.
        These commands read source files directly, without using the SQLite index.
        Use --json for machine-readable JSON output.

        NOTE: If you use Obsidian, the Obsidian CLI (https://help.obsidian.md/cli) \
        may provide more reliable results for vault-specific operations. md-utils \
        is intended for general Markdown workflows beyond Obsidian.
        """,
      subcommands: [
        ListLinks.self,
        Check.self,
        Backlinks.self,
        ConvertLinks.self,
      ],
      aliases: ["ln"]
    )
  }
}
