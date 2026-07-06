//
//  RulesRemove.swift
//  md-utils
//

import ArgumentParser
import PathKit
/// Adds Markdown document behavior to ``CLIEntry.RulesCommands``.
///
/// See <doc:RulesValidationCommands> for workflow details.
extension CLIEntry.RulesCommands {
  /// Defines the `rules remove` command behavior.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "remove",
      abstract: "Remove a rule from project configuration"
    )

    @Argument(help: "Rule name to remove")
    var name: String

    @Flag(name: .long, help: "Delete the removed rule's schema file when it is safe")
    var deleteSchema: Bool = false
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:RulesValidationCommands> for workflow details.
    mutating func run() async throws {
      let result = try RuleManager.removeRule(named: name, deleteSchema: deleteSchema)

      print("\(CLIStyle.success("Removed rule")) \"\(result.removed.name)\"")
      if deleteSchema {
        if result.deletedSchema {
          print("\(CLIStyle.success("Deleted schema:")) \(CLIStyle.path(result.schemaPath.string))")
        } else if Path(result.removed.schema).isAbsolute {
          print("\(CLIStyle.metadata("Schema not deleted because it is an absolute path:")) \(CLIStyle.path(result.schemaPath.string))")
        } else if result.schemaPath.exists {
          print("\(CLIStyle.metadata("Schema not deleted because it is still referenced:")) \(CLIStyle.path(result.schemaPath.string))")
        } else {
          print("\(CLIStyle.warning("Schema file not found:")) \(CLIStyle.path(result.schemaPath.string))")
        }
      }
    }
  }
}
