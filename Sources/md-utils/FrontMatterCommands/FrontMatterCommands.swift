//
//  FrontMatterCommands.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry {
  /// Frontmatter manipulation commands
  struct FrontMatterCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "frontmatter",
      abstract: "Manipulate YAML frontmatter in Markdown files",
      discussion: """
        Provides CRUD operations for YAML frontmatter in Markdown files.

        By default, processes directories recursively.
        """,
      subcommands: [
        ArrayCommands.self,
        Dump.self,
        Get.self,
        Has.self,
        List.self,
        Remove.self,
        Rename.self,
        Replace.self,
        Search.self,
        Set.self,
        SortKeys.self,
        Touch.self,
      ],
      aliases: ["fm"]
    )
  }
}
