//
//  ConfigMigrate.swift
//  md-utils
//

import ArgumentParser
import Foundation
import PathKit

/// Adds config migration support to ``CLIEntry.ConfigCommands``.
extension CLIEntry.ConfigCommands {
  /// Migrates md-utils project configuration between supported schema versions.
  struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "migrate",
      abstract: "Migrate md-utils project configuration to another schema version"
    )

    @Option(name: .long, help: "Expected source config schema version")
    var from: String?

    @Option(name: .long, help: "Target config schema version")
    var to: String

    @Option(name: .long, help: "Path to md-utils config file")
    var config: String = RulesPaths.configFile.string

    @Flag(name: .long, help: "Preview the migration without writing files")
    var dryRun = false

    @Option(name: .long, help: "Output format: text or json")
    var format: ConfigMigrateOutputFormat = .text

    mutating func run() async throws {
      let result = try ConfigMigrator.migrate(
        configPath: Path(config),
        from: from,
        to: to,
        dryRun: dryRun
      )

      switch format {
      case .text:
        print(ConfigMigrateFormatter.renderText(result))
      case .json:
        print(try ConfigMigrateFormatter.renderJSON(result), terminator: "")
      }
    }
  }
}

enum ConfigMigrateOutputFormat: String, ExpressibleByArgument {
  case text
  case json
}

struct ConfigMigrationResult {
  var configPath: String
  var from: String
  var to: String
  var changed: Bool
  var dryRun: Bool
  var updatedSchemaReference: Bool
  var updatedLocalSchema: Bool
}

enum ConfigMigrator {
  static func migrate(
    configPath: Path = RulesPaths.configFile,
    from expectedFrom: String? = nil,
    to targetVersion: String,
    dryRun: Bool = false
  ) throws -> ConfigMigrationResult {
    guard ConfigSchemaRegistry.supportedVersions.contains(targetVersion) else {
      throw ValidationError("Unsupported target md-utils configVersion \"\(targetVersion)\"")
    }
    if let expectedFrom, !ConfigSchemaRegistry.supportedVersions.contains(expectedFrom) {
      throw ValidationError("Unsupported source md-utils configVersion \"\(expectedFrom)\"")
    }

    var config = try MdUtilsConfig.load(from: configPath)
    let sourceVersion = config.configVersion
    if let expectedFrom, expectedFrom != sourceVersion {
      throw ValidationError("Expected source configVersion \"\(expectedFrom)\", found \"\(sourceVersion)\"")
    }

    guard sourceVersion != targetVersion else {
      return ConfigMigrationResult(
        configPath: configPath.string,
        from: sourceVersion,
        to: targetVersion,
        changed: false,
        dryRun: dryRun,
        updatedSchemaReference: false,
        updatedLocalSchema: false
      )
    }

    guard sourceVersion == ConfigSchemaRegistry.legacyVersion && targetVersion == ConfigSchemaRegistry.defaultVersion else {
      throw ValidationError("Unsupported config migration path: \(sourceVersion) -> \(targetVersion)")
    }

    let localSchemaPath = localSchemaPath(for: configPath)
    let updatedLocalSchema = shouldUpdateLocalSchema(configPath: configPath, localSchemaPath: localSchemaPath)
    if !dryRun {
      config.configVersion = targetVersion
      config.schemaReference = ConfigSchemaRegistry.publicSchemaURL(for: targetVersion)
      try config.save(to: configPath)
      if updatedLocalSchema {
        try localSchemaPath.parent().mkpath()
        try localSchemaPath
          .write(try ConfigSchemaRegistry.schemaContent(for: targetVersion))
      }
    }

    return ConfigMigrationResult(
      configPath: configPath.string,
      from: sourceVersion,
      to: targetVersion,
      changed: true,
      dryRun: dryRun,
      updatedSchemaReference: true,
      updatedLocalSchema: updatedLocalSchema
    )
  }

  static func localSchemaPath(for configPath: Path) -> Path {
    configPath.parent() + RulesPaths.bundledConfigSchemaFileName
  }

  private static func shouldUpdateLocalSchema(configPath: Path, localSchemaPath: Path) -> Bool {
    configPath == RulesPaths.configFile || localSchemaPath.exists
  }
}

enum ConfigMigrateFormatter {
  static func renderText(_ result: ConfigMigrationResult) -> String {
    if !result.changed {
      return "Config \(result.configPath) is already at \(result.to)."
    }

    let prefix = result.dryRun ? "Would migrate" : "Migrated"
    var lines = ["\(prefix) config \(result.configPath) from \(result.from) to \(result.to)."]
    let schemaPrefix = result.dryRun ? "Would update" : "Updated"
    if result.updatedSchemaReference {
      lines.append("\(schemaPrefix) schema reference to \(ConfigSchemaRegistry.publicSchemaURL(for: result.to)).")
    }
    if result.updatedLocalSchema {
      lines.append("\(schemaPrefix) local schema \(ConfigMigrator.localSchemaPath(for: Path(result.configPath)).string).")
    }
    return lines.joined(separator: "\n")
  }

  static func renderJSON(_ result: ConfigMigrationResult) throws -> String {
    let object: [String: Any] = [
      "changed": result.changed,
      "configPath": result.configPath,
      "dryRun": result.dryRun,
      "from": result.from,
      "to": result.to,
      "updatedLocalSchema": result.updatedLocalSchema,
      "updatedSchemaReference": result.updatedSchemaReference,
    ]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    guard let json = String(data: data, encoding: .utf8) else {
      throw ValidationError("Failed to encode config migration result")
    }
    return json + "\n"
  }
}
