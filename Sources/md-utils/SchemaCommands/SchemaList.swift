//
//  List.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry.SchemaCommands {
  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List configured schema rules"
    )

    mutating func run() async throws {
      let config = try MdUtilsConfig.load()
      if config.schemaRules.isEmpty {
        print("No schema rules configured.")
        return
      }

      for rule in config.schemaRules {
        let schemaPath = SchemaPaths.schemaFile(rule: rule, config: config)
        print(rule.name)
        print("  schema: \(schemaPath.string)")
        print("  frontmatterRequired: \(rule.frontmatterRequired)")
        if !rule.match.paths.isEmpty {
          print("  paths: \(rule.match.paths.joined(separator: ", "))")
        }
        if !rule.match.frontmatter.isEmpty {
          print("  \(rule.name) rule will run when:")
          for key in rule.match.frontmatter.keys.sorted() {
            if let matcher = rule.match.frontmatter[key] {
              print("    frontmatter key \(key) includes \(matcher.includes)")
            }
          }
        }
      }
    }
  }
}
