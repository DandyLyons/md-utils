//
//  ConfigSchemaPrinter.swift
//  md-utils
//

import ArgumentParser
import Foundation
/// Defines the `ConfigSchemaPrinter` command behavior.
enum ConfigSchemaPrinter {
  /// Loads the bundled configuration schema content.
  static func content() throws -> String {
    guard let url = Bundle.module.url(forResource: "md-utils.schema", withExtension: "json") else {
      throw ValidationError("Bundled md-utils config schema is missing")
    }

    return try String(contentsOf: url, encoding: .utf8)
  }
  /// Prints the bundled configuration schema to standard output.
  static func printSchema() throws {
    print(try content(), terminator: "")
  }
}
