//
//  FrontMatterCommands.swift
//  md-utils
//

import ArgumentParser
/// Adds command implementations to ``CLIEntry``.
///
/// See <doc:FrontmatterCommands> for workflow details.
extension CLIEntry {
  /// Frontmatter manipulation commands
  struct FrontMatterCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "frontmatter",
      abstract: "Manipulate YAML or TOML frontmatter in Markdown and mapped text files",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Provides CRUD operations for YAML or TOML frontmatter in Markdown files and in
        non-Markdown text files with shipped syntax mappings.

        Existing blocks preserve their format. Creation-capable commands accept
        --frontmatter-format yaml|toml and default to YAML. Comments in either
        format are not guaranteed to survive mutation.

        By default, directory and multi-file operations remain Markdown-only.
        Use --include-non-md on supported commands to include mapped files.
        """),
      subcommands: [
        ArrayCommands.self,
        Dump.self,
        Get.self,
        Has.self,
        List.self,
        Remove.self,
        RemoveFrontmatter.self,
        Rename.self,
        Replace.self,
        Search.self,
        Set.self,
        SortKeys.self,
        Touch.self,
        Unique.self,
      ],
      aliases: ["fm"]
    )
  }
}
