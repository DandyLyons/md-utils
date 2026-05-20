//
//  SchemaRemove.swift
//  md-utils
//

import ArgumentParser
import PathKit

extension CLIEntry.SchemaCommands {
  struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "remove",
      abstract: "Remove a schema rule from project configuration"
    )

    @Argument(help: "Rule name to remove")
    var name: String

    @Flag(name: .long, help: "Delete the removed rule's schema file when it is safe")
    var deleteSchema: Bool = false

    mutating func run() async throws {
      let result = try SchemaRuleManager.removeRule(named: name, deleteSchema: deleteSchema)

      print("Removed schema rule \"\(result.removed.name)\"")
      if deleteSchema {
        if result.deletedSchema {
          print("Deleted schema: \(result.schemaPath.string)")
        } else if Path(result.removed.schema).isAbsolute {
          print("Schema not deleted because it is an absolute path: \(result.schemaPath.string)")
        } else if result.schemaPath.exists {
          print("Schema not deleted because it is still referenced: \(result.schemaPath.string)")
        } else {
          print("Schema file not found: \(result.schemaPath.string)")
        }
      }
    }
  }
}
