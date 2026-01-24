//
//  ArrayCommands.swift
//  md-utils
//
//  Parent command for array manipulation operations
//

import ArgumentParser

extension CLIEntry.FrontMatterCommands {
  struct ArrayCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "array",
      abstract: "Array manipulation commands for frontmatter",
      discussion: """
        Manipulate arrays in YAML frontmatter with various subcommands.

        SUBCOMMANDS:
          contains   Check if arrays contain specific values
          append     Add values to end of arrays
          prepend    Add values to beginning of arrays
          remove     Remove values from arrays

        All subcommands support:
          - Multiple file processing
          - Recursive directory traversal (enabled by default)
          - Case-insensitive comparison options

        EXAMPLES:
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
        """,
      subcommands: [Contains.self, Append.self, Prepend.self, Remove.self]
    )
  }
}
