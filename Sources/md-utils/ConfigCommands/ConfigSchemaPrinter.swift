//
//  ConfigSchemaPrinter.swift
//  md-utils
//

import ArgumentParser
import Foundation

enum ConfigSchemaPrinter {
  static func content() throws -> String {
    guard let url = Bundle.module.url(forResource: "md-utils.schema", withExtension: "json") else {
      throw ValidationError("Bundled md-utils config schema is missing")
    }

    return try String(contentsOf: url, encoding: .utf8)
  }

  static func printSchema() throws {
    print(try content(), terminator: "")
  }
}
