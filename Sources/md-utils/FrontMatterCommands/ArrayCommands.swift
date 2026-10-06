//
//  ArrayCommands.swift
//  md-utils
//
//  Parent command for array manipulation operations
//

import ArgumentParser
/// Adds Markdown document behavior to ``CLIEntry.FrontMatterCommands``.
///
/// See <doc:FrontmatterCommands> for workflow details.
extension CLIEntry.FrontMatterCommands {
  /// Defines the `Array commands` command behavior.
  ///
  /// See <doc:FrontmatterCommands> for workflow details.
  struct ArrayCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "array",
      abstract: "Array manipulation commands for frontmatter",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Manipulate arrays in YAML or TOML frontmatter with various subcommands.

        SUBCOMMANDS:
          init       Create an empty array if the key is missing or null
          clear      Empty an existing array while retaining its key
          contains   Check if arrays contain specific values
          append     Add values to end of arrays
          prepend    Add values to beginning of arrays
          remove     Remove values from arrays

        All subcommands support:
          - Multiple file processing
          - Recursive directory traversal (enabled by default)

        Value comparison subcommands also support case-insensitive options.

        EXAMPLES:
          # Initialize missing or null tags while preserving existing arrays
          md-utils fm array init --key tags posts/

          # Empty an array while retaining the key
          md-utils fm array clear --key tags post.md

          # Check if files contain a tag
          md-utils fm array contains --key tags --value swift posts/

          # Add a tag to all files
          md-utils fm array append --key tags --value tutorial posts/*.md

          # Add a tag to the front of the array
          md-utils fm array prepend --key tags --value featured posts/*.md

          # Remove a tag from files
          md-utils fm array remove --key tags --value draft posts/*.md

        PIPING:
          Array commands work great with piping for bulk operations:

          # Find files and update them
          md-utils fm array contains --key tags --value swift . | xargs md-utils fm set --key published --value true
        """),
      subcommands: [Initialize.self, Clear.self, Contains.self, Append.self, Prepend.self, Remove.self],
    )
  }
}
