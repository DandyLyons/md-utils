//
//  FrontMatterCommands.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry {
  /// Frontmatter manipulation commands
  struct FrontMatterCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "fm",
      abstract: "Manipulate YAML frontmatter in Markdown files",
      discussion: """
        Provides CRUD operations for YAML frontmatter in Markdown files.

        Available commands:
        - get: Retrieve a frontmatter value by key
        - set: Set or update a frontmatter value
        - has: Check if a frontmatter key exists
        - remove: Delete a frontmatter key
        - rename: Rename a frontmatter key
        - list: List all frontmatter keys
        - dump: Dump entire frontmatter in specified format

        By default, processes directories recursively.
        """,
      subcommands: [
        Get.self,
        Set.self,
        Has.self,
        Remove.self,
        Rename.self,
        List.self,
        Dump.self,
      ]
    )
  }
}
