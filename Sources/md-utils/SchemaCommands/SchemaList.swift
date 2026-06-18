//
//  List.swift
//  md-utils
//

import ArgumentParser
/// Adds Markdown document behavior to ``CLIEntry.SchemaCommands``.
///
/// See <doc:SchemaValidationCommands> for workflow details.
extension CLIEntry.SchemaCommands {
  /// Defines the `SchemaList` command behavior.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List configured schema rules"
    )
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:SchemaValidationCommands> for workflow details.
    mutating func run() async throws {
      let config = try MdUtilsConfig.load()
      if config.schemaRules.isEmpty {
        print(CLIStyle.muted("No schema rules configured."))
        return
      }

      for rule in config.schemaRules {
        let schemaPath = SchemaPaths.schemaFile(rule: rule, config: config)
        print(CLIStyle.heading(rule.name))
        print("  \(CLIStyle.metadata("schema:")) \(CLIStyle.path(schemaPath.string))")
        print("  \(CLIStyle.metadata("frontmatterRequired:")) \(rule.frontmatterRequired)")
        if !rule.match.paths.isEmpty {
          print("  \(CLIStyle.metadata("paths:")) \(rule.match.paths.joined(separator: ", "))")
        }
        if !rule.match.frontmatter.isEmpty {
          print("  \(CLIStyle.metadata("\(rule.name) rule will run when:"))")
          for key in rule.match.frontmatter.keys.sorted() {
            if let matcher = rule.match.frontmatter[key] {
              print("    \(CLIStyle.metadata("frontmatter key")) \(key) \(CLIStyle.metadata("includes")) \(matcher.includes)")
            }
          }
        }
      }
    }
  }
}
