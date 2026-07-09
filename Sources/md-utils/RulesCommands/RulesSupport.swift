//
//  RulesSupport.swift
//  md-utils
//

import ArgumentParser
import Foundation
import JSONSchema
import MarkdownUtilities
import PathKit
import Yams
/// Stores project-level md-utils rules validation configuration.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct MdUtilsConfig {
  static let defaultConfigVersion = ConfigSchemaRegistry.defaultVersion
  static let defaultSchemaDirectory = ".md-utils/schemas/"

  var configVersion: String
  var schemaReference: String?
  var schemaDirectory: String
  var schemaRules: [Rule]
  /// Creates a configured instance.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  init(
    configVersion: String = Self.defaultConfigVersion,
    schemaReference: String? = ConfigSchemaRegistry.publicSchemaURL(for: ConfigSchemaRegistry.defaultVersion),
    schemaDirectory: String = Self.defaultSchemaDirectory,
    schemaRules: [Rule] = []
  ) {
    self.configVersion = configVersion
    self.schemaReference = schemaReference
    self.schemaDirectory = schemaDirectory
    self.schemaRules = schemaRules
  }
  /// Loads the requested data from disk.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func load(from path: Path = RulesPaths.configFile) throws -> MdUtilsConfig {
    guard path.exists else {
      throw ValidationError("Project config not found: \(path.string). Run md-utils rules init first.")
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path.string))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ValidationError("Project config must be a JSON object: \(path.string)")
    }

    let configVersion = try ConfigSchemaRegistry.detectVersion(in: object, path: path)
    let validationObject = ConfigSchemaRegistry.configObjectForValidation(object, configVersion: configVersion)
    let configSchema = try ConfigSchemaRegistry.schema(for: configVersion)
    let validationResult = try JSONSchema.validate(validationObject, schema: configSchema)
    if !validationResult.valid {
      let message = validationResult.errors?.map(\.description).joined(separator: "; ") ?? "does not match bundled schema"
      throw ValidationError("Project config is invalid for configVersion \"\(configVersion)\": \(message)")
    }

    let schemaReference = object["$schema"] as? String
    let schemaDirectory = object["schemaDirectory"] as? String ?? Self.defaultSchemaDirectory
    let rawRules = if configVersion == "0.1.0" {
      object["schemaRules"] as? [[String: Any]] ?? []
    } else {
      object["rules"] as? [[String: Any]] ?? []
    }
    let rules = try rawRules.map { try Rule(json: $0, configVersion: configVersion) }
    let names = rules.map(\.name)
    if Set(names).count != names.count {
      throw ValidationError("Schema rule names must be unique")
    }

    return MdUtilsConfig(
      configVersion: configVersion,
      schemaReference: schemaReference,
      schemaDirectory: schemaDirectory,
      schemaRules: rules
    )
  }
  /// Saves the current data to disk.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  func save(to path: Path = RulesPaths.configFile) throws {
    var object: [String: Any] = [
      "configVersion": configVersion,
      "schemaDirectory": schemaDirectory,
    ]
    if configVersion == "0.1.0" {
      object["schemaRules"] = schemaRules.map { $0.legacyJsonObject }
    } else {
      object["rules"] = schemaRules.map { $0.jsonObject }
    }
    if let schemaReference {
      object["$schema"] = schemaReference
    }

    let data = try JSONSerialization.data(
      withJSONObject: object,
      options: [.prettyPrinted, .sortedKeys]
    )
    guard let json = String(data: data, encoding: .utf8) else {
      throw ValidationError("Failed to encode md-utils config")
    }
    try path.write(json + "\n")
  }
}

/// Selects bundled md-utils config schemas by config schema version.
enum ConfigSchemaRegistry {
  static let defaultVersion = "0.2.0"
  static let legacyVersion = "0.1.0"
  static let supportedVersions = ["0.1.0", "0.2.0"]

  static func detectVersion(in object: [String: Any], path: Path) throws -> String {
    guard let rawVersion = object["configVersion"] else {
      return legacyVersion
    }
    guard let version = rawVersion as? String, !version.isEmpty else {
      throw ValidationError("Project config configVersion must be a non-empty string: \(path.string)")
    }
    guard supportedVersions.contains(version) else {
      throw ValidationError(
        "Unsupported md-utils configVersion \"\(version)\". This md-utils release supports: \(supportedVersions.joined(separator: ", ")). Upgrade md-utils or migrate the config."
      )
    }
    return version
  }

  static func configObjectForValidation(_ object: [String: Any], configVersion: String) -> [String: Any] {
    var validationObject = object
    validationObject["configVersion"] = configVersion
    return validationObject
  }

  static func publicSchemaURL(for version: String) -> String {
    "https://dandylyons.github.io/md-utils/schemas/\(version)/md-utils.schema.json"
  }

  static func schemaContent(for version: String = defaultVersion) throws -> String {
    guard supportedVersions.contains(version) else {
      throw ValidationError("Unsupported md-utils configVersion \"\(version)\"")
    }
    guard let url = Bundle.module.url(forResource: resourceBaseName(for: version), withExtension: "json") else {
      throw ValidationError("Bundled md-utils config schema is missing for configVersion \"\(version)\"")
    }

    return try String(contentsOf: url, encoding: .utf8)
  }

  static func schema(for version: String) throws -> [String: Any] {
    let content = try schemaContent(for: version)
    guard let data = content.data(using: .utf8) else {
      throw ValidationError("Bundled md-utils config schema is not UTF-8 for configVersion \"\(version)\"")
    }
    guard let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ValidationError("Bundled md-utils config schema must be a JSON object for configVersion \"\(version)\"")
    }
    return schema
  }

  private static func resourceBaseName(for version: String) -> String {
    "\(version)_md-utils.schema"
  }
}

enum ConfigInfoFormatter {
  static func renderText() -> String {
    """
    You are using md-utils CLI version \(CLIEntry.configuration.version)

    Supported md-utils config schema versions:
    \(ConfigSchemaRegistry.supportedVersions.reversed().map { "  \($0)" }.joined(separator: "\n"))

    Default generated config schema version: \(ConfigSchemaRegistry.defaultVersion)
    """
  }

  static func renderJSON() throws -> String {
    let object: [String: Any] = [
      "cliVersion": CLIEntry.configuration.version,
      "defaultConfigVersion": ConfigSchemaRegistry.defaultVersion,
      "supportedConfigVersions": ConfigSchemaRegistry.supportedVersions,
    ]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    guard let json = String(data: data, encoding: .utf8) else {
      throw ValidationError("Failed to encode config schema versions")
    }
    return json + "\n"
  }
}
/// Defines one named rule from the project configuration.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct Rule {
  var name: String
  var schema: String
  var frontmatterRequired: Bool
  var match: RuleMatch
  var checks: [RuleCheck]
  /// Creates a configured instance.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  init(name: String, schema: String, frontmatterRequired: Bool = true, match: RuleMatch, checks: [RuleCheck]? = nil) {
    self.name = name
    self.schema = schema
    self.frontmatterRequired = frontmatterRequired
    self.match = match
    self.checks = checks ?? [.frontmatterSchema(schema: schema, frontmatterRequired: frontmatterRequired)]
  }
  /// Creates a configured instance.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  init(json: [String: Any], configVersion: String = ConfigSchemaRegistry.defaultVersion) throws {
    guard let name = json["name"] as? String, !name.isEmpty else {
      throw ValidationError("Schema rules require a non-empty name")
    }
    guard let matchObject = json["match"] as? [String: Any] else {
      throw ValidationError("Schema rule \"\(name)\" requires a match object")
    }

    self.name = name
    self.frontmatterRequired = json["frontmatterRequired"] as? Bool ?? true
    self.match = try RuleMatch(json: matchObject, ruleName: name)
    if configVersion == "0.1.0" {
      guard let schema = json["schema"] as? String, !schema.isEmpty else {
        throw ValidationError("Schema rule \"\(name)\" requires a non-empty schema")
      }
      self.schema = schema
      self.checks = [.frontmatterSchema(schema: schema, frontmatterRequired: self.frontmatterRequired)]
    } else {
      let rawChecks = json["checks"] as? [[String: Any]] ?? []
      guard !rawChecks.isEmpty else {
        throw ValidationError("Rule \"\(name)\" requires at least one check")
      }
      self.checks = try rawChecks.map { try RuleCheck(json: $0, ruleName: name) }
      self.schema = self.checks.compactMap(\.schema).first ?? ""
    }
  }

  var jsonObject: [String: Any] {
    [
      "name": name,
      "match": match.jsonObject,
      "checks": checks.map(\.jsonObject),
    ]
  }

  var legacyJsonObject: [String: Any] {
    [
      "name": name,
      "schema": schema,
      "frontmatterRequired": frontmatterRequired,
      "match": match.jsonObject,
    ]
  }
}
enum RuleCheck: Equatable {
  case frontmatterSchema(schema: String, frontmatterRequired: Bool)
  case requiredHeading(String)
  case maxBodyLines(Int)
  case maxBodyWords(Int)

  init(json: [String: Any], ruleName: String) throws {
    guard let type = json["type"] as? String else {
      throw ValidationError("Rule \"\(ruleName)\" check requires a type")
    }
    switch type {
    case "frontmatterSchema":
      guard let schema = json["schema"] as? String, !schema.isEmpty else {
        throw ValidationError("Rule \"\(ruleName)\" frontmatterSchema check requires a schema")
      }
      self = .frontmatterSchema(schema: schema, frontmatterRequired: json["frontmatterRequired"] as? Bool ?? true)
    case "requiredHeading":
      guard let heading = json["heading"] as? String, !heading.isEmpty else {
        throw ValidationError("Rule \"\(ruleName)\" requiredHeading check requires a heading")
      }
      self = .requiredHeading(heading)
    case "maxBodyLines":
      guard let max = json["max"] as? Int, max >= 0 else {
        throw ValidationError("Rule \"\(ruleName)\" maxBodyLines check requires a non-negative max")
      }
      self = .maxBodyLines(max)
    case "maxBodyWords":
      guard let max = json["max"] as? Int, max >= 0 else {
        throw ValidationError("Rule \"\(ruleName)\" maxBodyWords check requires a non-negative max")
      }
      self = .maxBodyWords(max)
    default:
      throw ValidationError("Rule \"\(ruleName)\" has unsupported check type \"\(type)\"")
    }
  }

  var schema: String? {
    if case .frontmatterSchema(let schema, _) = self { return schema }
    return nil
  }

  var jsonObject: [String: Any] {
    switch self {
    case .frontmatterSchema(let schema, let frontmatterRequired):
      return ["type": "frontmatterSchema", "schema": schema, "frontmatterRequired": frontmatterRequired]
    case .requiredHeading(let heading):
      return ["type": "requiredHeading", "heading": heading]
    case .maxBodyLines(let max):
      return ["type": "maxBodyLines", "max": max]
    case .maxBodyWords(let max):
      return ["type": "maxBodyWords", "max": max]
    }
  }

  var requiresFrontmatter: Bool {
    if case .frontmatterSchema(_, let frontmatterRequired) = self {
      return frontmatterRequired
    }
    return false
  }

  var isOptionalFrontmatterSchema: Bool {
    if case .frontmatterSchema(_, let frontmatterRequired) = self {
      return !frontmatterRequired
    }
    return false
  }
}
/// Describes the path and frontmatter conditions that select files for a rule.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleMatch {
  var paths: [String]
  var excludePaths: [String]
  var frontmatter: [String: FrontmatterMatcher]
  /// Creates a configured instance.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  init(paths: [String] = [], excludePaths: [String] = [], frontmatter: [String: FrontmatterMatcher] = [:]) {
    self.paths = paths
    self.excludePaths = excludePaths
    self.frontmatter = frontmatter
  }
  /// Creates a configured instance.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  init(json: [String: Any], ruleName: String) throws {
    let paths = json["paths"] as? [String] ?? []
    let excludePaths = json["excludePaths"] as? [String] ?? []
    let frontmatterObject = json["frontmatter"] as? [String: Any] ?? [:]
    var frontmatter: [String: FrontmatterMatcher] = [:]

    for (key, rawMatcher) in frontmatterObject {
      guard let matcherObject = rawMatcher as? [String: Any] else {
        throw ValidationError("Schema rule \"\(ruleName)\" has invalid frontmatter matcher for \"\(key)\"")
      }
      frontmatter[key] = try FrontmatterMatcher(json: matcherObject, key: key, ruleName: ruleName)
    }

    if paths.isEmpty && frontmatter.isEmpty {
      throw ValidationError("Schema rule \"\(ruleName)\" must define at least one match condition")
    }

    self.paths = paths
    self.excludePaths = excludePaths
    self.frontmatter = frontmatter
  }

  var jsonObject: [String: Any] {
    var object: [String: Any] = [:]
    if !paths.isEmpty {
      object["paths"] = paths
    }
    if !excludePaths.isEmpty {
      object["excludePaths"] = excludePaths
    }
    if !frontmatter.isEmpty {
      object["frontmatter"] = frontmatter.mapValues { $0.jsonObject }
    }
    return object
  }
}
/// Describes a frontmatter matcher that requires an array to include a value.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct FrontmatterMatcher {
  var operators: [String: Any]
  /// Creates a configured instance.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  init(includes: Any) {
    self.operators = ["includes": includes]
  }
  /// Creates a configured instance.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  init(json: [String: Any], key: String, ruleName: String) throws {
    let supported = Set(["includes", "equals", "notIncludes", "after", "between"])
    let operators = json.filter { supported.contains($0.key) }
    guard !operators.isEmpty else {
      throw ValidationError("Schema rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" requires a supported operator")
    }
    self.operators = operators
  }

  var jsonObject: [String: Any] {
    operators
  }

  var includes: Any? { operators["includes"] }
}
/// Centralizes project configuration and schema file paths.
///
/// See <doc:RulesValidationCommands> for workflow details.
enum RulesPaths {
  static var projectDirectory: Path { Path(".md-utils") }
  static var configFile: Path { projectDirectory + "md-utils.json" }
  static let bundledConfigSchemaFileName = "md-utils.schema.json"
  /// Returns the directory that stores md-utils project configuration.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func schemaDirectory(for config: MdUtilsConfig) -> Path {
    Path(config.schemaDirectory)
  }
  /// Returns the schema file path for a configured rule.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func schemaFile(rule: Rule, config: MdUtilsConfig) -> Path {
    let schemaPath = Path(rule.schema)
    if schemaPath.isAbsolute {
      return schemaPath
    }
    return schemaDirectory(for: config) + rule.schema
  }
  /// Returns the schema file path for a configured rule relative to an explicit root.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func schemaFile(rule: Rule, config: MdUtilsConfig, root: Path) -> Path {
    let schemaPath = Path(rule.schema)
    if schemaPath.isAbsolute {
      return schemaPath
    }
    let directory = schemaDirectory(for: config)
    if directory.isAbsolute {
      return directory + rule.schema
    }
    return root + directory + rule.schema
  }
}
/// Bootstraps the `.md-utils` project configuration files.
///
/// See <doc:RulesValidationCommands> for workflow details.
enum RulesConfigBootstrapper {
  /// Creates the project configuration directory and bundled schema file when needed.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func ensureProjectFiles() throws {
    try RulesPaths.projectDirectory.mkpath()
    try Path(MdUtilsConfig.defaultSchemaDirectory).mkpath()
    try copyBundledConfigSchema()

    if !RulesPaths.configFile.exists {
      try MdUtilsConfig().save()
    }
  }
  /// Copies the bundled md-utils configuration schema into the project directory.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  private static func copyBundledConfigSchema() throws {
    let destination = RulesPaths.projectDirectory + RulesPaths.bundledConfigSchemaFileName
    try destination.write(try ConfigSchemaRegistry.schemaContent())
  }
}
/// Captures options used to create or initialize a rule.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleOptions {
  var name: String
  var schema: String?
  var path: String
  var tag: String?
  var frontmatterRequired: Bool
}
/// Adds and removes rules from the project configuration.
///
/// See <doc:RulesValidationCommands> for workflow details.
enum RuleManager {
  /// Adds a rule to the project configuration.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func addRule(_ options: RuleOptions) throws -> Path {
    var config = try MdUtilsConfig.load()
    if config.schemaRules.contains(where: { $0.name == options.name }) {
      throw ValidationError("Schema rule already exists: \"\(options.name)\"")
    }

    let schemaFilename = options.schema ?? "\(options.name).schema.json"
    let schemaDirectory = RulesPaths.schemaDirectory(for: config)
    try schemaDirectory.mkpath()
    let schemaFile = schemaDirectory + schemaFilename
    if !schemaFile.exists {
      try schemaFile.write(starterSchema(title: options.name))
    }

    var frontmatterMatchers: [String: FrontmatterMatcher] = [:]
    if let tag = options.tag {
      frontmatterMatchers["tags"] = FrontmatterMatcher(includes: tag)
    }

    let rule = Rule(
      name: options.name,
      schema: schemaFilename,
      frontmatterRequired: options.frontmatterRequired,
      match: RuleMatch(paths: [options.path], frontmatter: frontmatterMatchers)
    )
    config.schemaRules.append(rule)
    try config.save()
    return schemaFile
  }
  /// Removes a rule from the project configuration.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func removeRule(named name: String, deleteSchema: Bool) throws -> (removed: Rule, deletedSchema: Bool, schemaPath: Path) {
    var config = try MdUtilsConfig.load()
    guard let index = config.schemaRules.firstIndex(where: { $0.name == name }) else {
      throw ValidationError("Schema rule not found: \"\(name)\"")
    }

    let removed = config.schemaRules.remove(at: index)
    let schemaPath = RulesPaths.schemaFile(rule: removed, config: config)
    var deletedSchema = false

    if deleteSchema {
      let isStillReferenced = config.schemaRules.contains { $0.schema == removed.schema }
      if !isStillReferenced && !Path(removed.schema).isAbsolute && schemaPath.exists {
        try schemaPath.delete()
        deletedSchema = true
      }
    }

    try config.save()
    return (removed, deletedSchema, schemaPath)
  }
  /// Builds starter JSON Schema content for a new frontmatter rule.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func starterSchema(title: String) -> String {
    """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "title": "\(title)",
      "type": "object",
      "additionalProperties": true,
      "properties": {
        "title": {
          "type": "string"
        },
        "tags": {
          "type": "array",
          "items": {
            "type": "string"
          }
        }
      }
    }

    """
  }
}
/// Loads JSON Schema documents from disk.
///
/// See <doc:RulesValidationCommands> for workflow details.
enum SchemaDocumentLoader {
  /// Loads a JSON Schema object from disk.
  static func load(path: Path) throws -> [String: Any] {
    guard path.exists else {
      throw ValidationError("Schema file not found: \(path.string)")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path.string))
    guard let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ValidationError("Schema file must contain a JSON object: \(path.string)")
    }
    return schema
  }
}
/// Finds Markdown files that can participate in rules validation.
///
/// See <doc:RulesValidationCommands> for workflow details.
enum RuleFileScanner {
  /// Finds Markdown files below the project root for rules validation.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func markdownFiles(root: Path = .current) throws -> [Path] {
    let manager = FileManager.default
    let rootURL = URL(fileURLWithPath: root.absolute().string)
    guard let enumerator = manager.enumerator(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var files: [Path] = []
    for case let url as URL in enumerator {
      let path = Path(url.path)
      guard !path.isDirectory else { continue }
      guard let ext = path.extension?.lowercased(), ["md", "markdown"].contains(ext) else { continue }
      files.append(path)
    }
    files.sort { $0.string < $1.string }
    return files
  }
}
/// Describes one JSON Schema validation issue for a Markdown file.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleValidationErrorDetail {
  var path: String
  var message: String
}
/// Records the validation status for one file and one rule.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleValidationResult {
  /// Indicates whether a file-rule validation passed, failed, or was skipped.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  enum Status {
    case ok
    case error
    case skipped
  }

  var ruleName: String
  var schemaPath: String
  var filePath: String
  var status: Status
  var errors: [RuleValidationErrorDetail]
}
/// Aggregates rule validation results for command output and exit status.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleValidationSummary {
  var results: [RuleValidationResult]
  var totalMarkdownFiles: Int

  var errors: Int {
    results.reduce(0) { count, result in
      count + (result.status == .error ? max(result.errors.count, 1) : 0)
    }
  }

  var skipped: Int {
    results.filter { $0.status == .skipped }.count
  }

  var matchedFiles: Int {
    Set(results.map(\.filePath)).count
  }

  var fileRuleMatches: Int {
    results.count
  }

  var hasFailures: Bool {
    results.contains { $0.status == .error }
  }
}
/// Runs project rules validation and returns a structured summary.
///
/// See <doc:RulesValidationCommands> for workflow details.
enum RulesValidatorRunner {
  /// Validates the input and returns validation results.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func validate(
    ruleName: String? = nil,
    root: Path = .current,
    configPath: Path = RulesPaths.configFile
  ) throws -> RuleValidationSummary {
    let config = try MdUtilsConfig.load(from: configPath)
    let rules: [Rule]
    if let ruleName {
      guard let rule = config.schemaRules.first(where: { $0.name == ruleName }) else {
        throw ValidationError("Schema rule not found: \"\(ruleName)\"")
      }
      rules = [rule]
    } else {
      rules = config.schemaRules
    }

    let files = try RuleFileScanner.markdownFiles(root: root)
    var results: [RuleValidationResult] = []
    var loadedSchemas: [String: [String: Any]] = [:]

    for file in files {
      let relativePath = relativePath(from: root, to: file)
      let pathMatchedRules = rules.filter { rulePathConditionsMatch(rule: $0, relativePath: relativePath) }
      guard !pathMatchedRules.isEmpty else { continue }

      let content = try file.read(.utf8)
      let frontmatterPresence = frontmatterPresence(in: content)
      var parsedFrontmatter: Any?
      var yamlError: Error?

      if frontmatterPresence.hasFrontmatter {
        do {
          let document = try MarkdownDocument(content: content)
          parsedFrontmatter = try YAMLConversion.safeNodeToSwiftValue(.mapping(document.frontMatter))
        } catch {
          yamlError = error
        }
      }

      let document = try? MarkdownDocument(content: content)

      for rule in pathMatchedRules {
        if let yamlError {
          results.append(errorResult(
            rule: rule,
            schemaPath: "",
            filePath: relativePath,
            path: "frontmatter",
            message: "invalid YAML: \(yamlError.localizedDescription)"
          ))
          continue
        }

        if !frontmatterPresence.hasFrontmatter {
          if !rule.match.frontmatter.isEmpty {
            continue
          } else if rule.checks.contains(where: { $0.requiresFrontmatter }) {
            results.append(errorResult(
              rule: rule,
              schemaPath: "",
              filePath: relativePath,
              path: "frontmatter",
              message: "required by rule \"\(rule.name)\""
            ))
            continue
          } else if hasOnlyOptionalFrontmatterSchemaChecks(rule) {
            results.append(RuleValidationResult(
              ruleName: rule.name,
              schemaPath: rule.schema.isEmpty ? "" : RulesPaths.schemaFile(rule: rule, config: config, root: root).string,
              filePath: relativePath,
              status: .skipped,
              errors: [RuleValidationErrorDetail(path: "frontmatter", message: "not present")]
            ))
            continue
          }
        }

        if frontmatterPresence.hasFrontmatter {
          guard let parsedFrontmatter else { continue }
          guard frontmatterConditionsMatch(rule: rule, frontmatter: parsedFrontmatter) else { continue }
        }

        let checkErrors = try validateChecks(
          rule: rule,
          config: config,
          root: root,
          parsedFrontmatter: parsedFrontmatter,
          document: document,
          loadedSchemas: &loadedSchemas
        )
        if checkErrors.isEmpty {
          results.append(RuleValidationResult(
            ruleName: rule.name,
            schemaPath: rule.schema.isEmpty ? "" : RulesPaths.schemaFile(rule: rule, config: config, root: root).string,
            filePath: relativePath,
            status: .ok,
            errors: []
          ))
        } else {
          results.append(RuleValidationResult(
            ruleName: rule.name,
            schemaPath: rule.schema.isEmpty ? "" : RulesPaths.schemaFile(rule: rule, config: config, root: root).string,
            filePath: relativePath,
            status: .error,
            errors: checkErrors
          ))
        }
      }
    }

    return RuleValidationSummary(results: results, totalMarkdownFiles: files.count)
  }

  static func filesMatching(
    ruleName: String,
    root: Path = .current,
    configPath: Path = RulesPaths.configFile
  ) throws -> [Path] {
    let config = try MdUtilsConfig.load(from: configPath)
    guard let rule = config.schemaRules.first(where: { $0.name == ruleName }) else {
      throw ValidationError("Schema rule not found: \"\(ruleName)\"")
    }

    let files = try RuleFileScanner.markdownFiles(root: root)
    var matches: [Path] = []
    for file in files {
      let relativePath = relativePath(from: root, to: file)
      guard rulePathConditionsMatch(rule: rule, relativePath: relativePath) else { continue }
      guard !rule.match.frontmatter.isEmpty else {
        matches.append(file)
        continue
      }

      let content = try file.read(.utf8)
      let frontmatterPresence = frontmatterPresence(in: content)
      guard frontmatterPresence.hasFrontmatter else { continue }
      do {
        let document = try MarkdownDocument(content: content)
        let parsedFrontmatter = try YAMLConversion.safeNodeToSwiftValue(.mapping(document.frontMatter))
        if frontmatterConditionsMatch(rule: rule, frontmatter: parsedFrontmatter) {
          matches.append(file)
        }
      } catch {
        continue
      }
    }
    return matches
  }

  /// Returns whether a project-relative path matches a rule path condition.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  private static func rulePathConditionsMatch(rule: Rule, relativePath: String) -> Bool {
    if rule.match.excludePaths.contains(where: { matchesGlob(relativePath, glob: $0) }) {
      return false
    }
    if rule.match.paths.isEmpty {
      return true
    }
    return rule.match.paths.contains { matchesGlob(relativePath, glob: $0) }
  }
  /// Returns whether parsed frontmatter satisfies a rule frontmatter condition.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  private static func frontmatterConditionsMatch(rule: Rule, frontmatter: Any) -> Bool {
    guard !rule.match.frontmatter.isEmpty else { return true }
    guard let object = frontmatter as? [String: Any] else { return false }

    for (key, matcher) in rule.match.frontmatter {
      guard let value = object[key] else { return false }
      if !frontmatterValue(value, matches: matcher) {
        return false
      }
    }
    return true
  }

  private static func validateChecks(
    rule: Rule,
    config: MdUtilsConfig,
    root: Path,
    parsedFrontmatter: Any?,
    document: MarkdownDocument?,
    loadedSchemas: inout [String: [String: Any]]
  ) throws -> [RuleValidationErrorDetail] {
    var errors: [RuleValidationErrorDetail] = []
    for check in rule.checks {
      switch check {
      case .frontmatterSchema(let schemaFilename, _):
        guard let parsedFrontmatter else { continue }
        let schemaRule = Rule(name: rule.name, schema: schemaFilename, match: rule.match)
        let schemaPath = RulesPaths.schemaFile(rule: schemaRule, config: config, root: root)
        let schemaKey = schemaPath.absolute().string
        let schema: [String: Any]
        if let loaded = loadedSchemas[schemaKey] {
          schema = loaded
        } else {
          schema = try SchemaDocumentLoader.load(path: schemaPath)
          loadedSchemas[schemaKey] = schema
        }

        let validationResult = try JSONSchema.validate(jsonCompatibleValue(parsedFrontmatter), schema: schema)
        if !validationResult.valid {
          errors.append(contentsOf: validationResult.errors?.map { error in
            RuleValidationErrorDetail(path: pointerDisplayPath(error.instanceLocation.path), message: error.description)
          } ?? [RuleValidationErrorDetail(path: "frontmatter", message: "schema validation failed")])
        }
      case .requiredHeading(let heading):
        let headings = headingTexts(in: document?.body ?? "")
        if !headings.contains(heading) {
          errors.append(RuleValidationErrorDetail(path: "heading", message: "required heading \"\(heading)\" not found"))
        }
      case .maxBodyLines(let max):
        let count = bodyLineCount(document?.body ?? "")
        if count > max {
          errors.append(RuleValidationErrorDetail(path: "body.lines", message: "line count \(count) exceeds maximum \(max)"))
        }
      case .maxBodyWords(let max):
        let count = bodyWordCount(document?.body ?? "")
        if count > max {
          errors.append(RuleValidationErrorDetail(path: "body.words", message: "word count \(count) exceeds maximum \(max)"))
        }
      }
    }
    return errors
  }

  private static func hasOnlyOptionalFrontmatterSchemaChecks(_ rule: Rule) -> Bool {
    !rule.checks.isEmpty && rule.checks.allSatisfy { check in
      if case .frontmatterSchema(_, let frontmatterRequired) = check {
        return !frontmatterRequired
      }
      return false
    }
  }

  private static func frontmatterValue(_ value: Any, matches matcher: FrontmatterMatcher) -> Bool {
    for (operatorName, operand) in matcher.operators {
      switch operatorName {
      case "includes":
        guard let array = value as? [Any], array.contains(where: { jsonValuesEqual($0, operand) }) else { return false }
      case "notIncludes":
        guard let array = value as? [Any], !array.contains(where: { jsonValuesEqual($0, operand) }) else { return false }
      case "equals":
        guard jsonValuesEqual(value, operand) else { return false }
      case "after":
        guard let left = comparableDateString(value), let right = comparableDateString(operand), left > right else { return false }
      case "between":
        guard
          let range = operand as? [String: Any],
          let from = range["from"].flatMap(comparableDateString),
          let to = range["to"].flatMap(comparableDateString),
          let value = comparableDateString(value),
          value >= from && value <= to
        else { return false }
      default:
        return false
      }
    }
    return true
  }
  /// Builds a validation result for an error that prevents rule validation.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  private static func errorResult(
    rule: Rule,
    schemaPath: String,
    filePath: String,
    path: String,
    message: String
  ) -> RuleValidationResult {
    RuleValidationResult(
      ruleName: rule.name,
      schemaPath: schemaPath,
      filePath: filePath,
      status: .error,
      errors: [RuleValidationErrorDetail(path: path, message: message)]
    )
  }
}
/// Detects whether Markdown content contains a frontmatter block and returns its raw YAML.
///
/// See <doc:RulesValidationCommands> for workflow details.
func frontmatterPresence(in content: String) -> (hasFrontmatter: Bool, raw: String?) {
  guard content.hasPrefix("---\n") else {
    return (false, nil)
  }
  let searchStart = content.index(content.startIndex, offsetBy: 4)
  if content[searchStart...].hasPrefix("---") {
    return (true, "")
  }
  guard let closingRange = content.range(of: "\n---", range: searchStart..<content.endIndex) else {
    return (false, nil)
  }
  return (true, String(content[searchStart..<closingRange.lowerBound]))
}
/// Returns a normalized project-relative path for matching and reporting.
///
/// See <doc:RulesValidationCommands> for workflow details.
func projectRelativePath(_ path: Path) -> String {
  let root = Path.current.absolute().string
  let absolute = path.absolute().string
  let normalizedRoot = root.hasSuffix("/") ? root : root + "/"
  if absolute.hasPrefix(normalizedRoot) {
    return String(absolute.dropFirst(normalizedRoot.count))
  }
  return path.string
}
/// Returns whether a value matches a simple glob pattern.
///
/// See <doc:RulesValidationCommands> for workflow details.
func matchesGlob(_ value: String, glob: String) -> Bool {
  let regex = globToRegex(glob)
  guard let expression = try? NSRegularExpression(pattern: regex) else {
    return false
  }
  let range = NSRange(value.startIndex..., in: value)
  return expression.firstMatch(in: value, range: range) != nil
}
/// Converts a simple glob pattern into a regular expression string.
///
/// See <doc:RulesValidationCommands> for workflow details.
func globToRegex(_ glob: String) -> String {
  var result = "^"
  var index = glob.startIndex

  while index < glob.endIndex {
    let character = glob[index]
    let nextIndex = glob.index(after: index)

    switch character {
    case "*":
      if nextIndex < glob.endIndex && glob[nextIndex] == "*" {
        let afterStars = glob.index(after: nextIndex)
        if afterStars < glob.endIndex && glob[afterStars] == "/" {
          result += "([^/]+/)*"
          index = glob.index(after: afterStars)
        } else {
          result += ".*"
          index = afterStars
        }
      } else {
        result += "[^/]*"
        index = nextIndex
      }
    case "?":
      result += "[^/]"
      index = nextIndex
    default:
      result += NSRegularExpression.escapedPattern(for: String(character))
      index = nextIndex
    }
  }

  return result + "$"
}
/// Compares two JSON-compatible values for semantic equality.
///
/// See <doc:RulesValidationCommands> for workflow details.
func jsonValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
  let left = jsonCompatibleValue(lhs)
  let right = jsonCompatibleValue(rhs)

  switch (left, right) {
  case (let left as String, let right as String):
    return left == right
  case (let left as Bool, let right as Bool):
    return left == right
  case (let left as Int, let right as Int):
    return left == right
  case (let left as Double, let right as Double):
    return left == right
  case (let left as NSNumber, let right as NSNumber):
    return left == right
  case (_ as NSNull, _ as NSNull):
    return true
  default:
    return false
  }
}
/// Normalizes a value into a JSON-compatible representation for comparison.
///
/// See <doc:RulesValidationCommands> for workflow details.
func jsonCompatibleValue(_ value: Any) -> Any {
  if let dict = value as? [String: Any] {
    return dict.mapValues { jsonCompatibleValue($0) }
  }
  if let dict = value as? [AnyHashable: Any] {
    return dict.reduce(into: [String: Any]()) { result, pair in
      result[String(describing: pair.key)] = jsonCompatibleValue(pair.value)
    }
  }
  if let array = value as? [Any] {
    return array.map { jsonCompatibleValue($0) }
  }
  if let date = value as? Date {
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: date)
  }
  return value
}
/// Returns a normalized YYYY-MM-DD date string when a value can participate in date comparisons.
func comparableDateString(_ value: Any) -> String? {
  if let string = value as? String {
    return string.count >= 10 ? String(string.prefix(10)) : nil
  }
  if let date = value as? Date {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
  return nil
}
/// Extracts ATX heading text from Markdown body without requiring a full AST parse.
func headingTexts(in body: String) -> [String] {
  body.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("#") else { return nil }
    let hashes = trimmed.prefix { $0 == "#" }
    guard (1...6).contains(hashes.count) else { return nil }
    let afterHashes = trimmed.dropFirst(hashes.count)
    guard afterHashes.first == " " else { return nil }
    return String(afterHashes.dropFirst()).trimmingCharacters(in: .whitespaces)
  }
}
/// Counts body lines, treating an empty body as zero lines.
func bodyLineCount(_ body: String) -> Int {
  guard !body.isEmpty else { return 0 }
  return body.split(separator: "\n", omittingEmptySubsequences: false).count
}
/// Counts whitespace-delimited words in Markdown body content.
func bodyWordCount(_ body: String) -> Int {
  body.split(whereSeparator: { $0.isWhitespace }).count
}
/// Converts a JSON Pointer into a user-facing display path.
///
/// See <doc:RulesValidationCommands> for workflow details.
func pointerDisplayPath(_ pointer: String) -> String {
  if pointer.isEmpty || pointer == "/" {
    return "frontmatter"
  }
  let trimmed = pointer.hasPrefix("/") ? String(pointer.dropFirst()) : pointer
  return trimmed.replacingOccurrences(of: "/", with: ".")
}
