//
//  ConfigSchemaPrinter.swift
//  md-utils
//

import ArgumentParser
import Foundation
/// Defines the `ConfigSchemaPrinter` command behavior.
enum ConfigSchemaPrinter {
  /// Loads the bundled configuration schema content.
  static func content(version: String = ConfigSchemaRegistry.defaultVersion) throws -> String {
    try ConfigSchemaRegistry.schemaContent(for: version)
  }
  /// Prints the bundled configuration schema to standard output.
  static func printSchema() throws {
    print(try content(), terminator: "")
  }
}
