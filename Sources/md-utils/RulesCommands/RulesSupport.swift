//
//  RulesSupport.swift
//  md-utils
//

import ArgumentParser
import Foundation
import JMESPath
import JSONSchema
import MarkdownUtilitiesCore
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
      throw ValidationError("Project config not found: \(path.string). Run md-utils config init first.")
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
      throw ValidationError("Rule names must be unique")
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
      throw ValidationError("Rules require a non-empty name")
    }
    guard let matchObject = json["match"] as? [String: Any] else {
      throw ValidationError("Rule \"\(name)\" requires a match object")
    }

    self.name = name
    self.frontmatterRequired = json["frontmatterRequired"] as? Bool ?? true
    self.match = try RuleMatch(json: matchObject, ruleName: name)
    if configVersion == "0.1.0" {
      guard let schema = json["schema"] as? String, !schema.isEmpty else {
        throw ValidationError("Rule \"\(name)\" requires a non-empty schema")
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
/// Describes the path, metadata, frontmatter, and document conditions that select files for a rule.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleMatch {
  var paths: [String]
  var excludePaths: [String]
  var frontmatter: [String: FrontmatterMatcher]
  var frontmatterQuery: FrontmatterQueryMatcher
  var document: DocumentMatcher
  var file: FileMatcher
  /// Creates a configured instance.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  init(
    paths: [String] = [],
    excludePaths: [String] = [],
    frontmatter: [String: FrontmatterMatcher] = [:],
    frontmatterQuery: FrontmatterQueryMatcher = FrontmatterQueryMatcher(),
    document: DocumentMatcher = DocumentMatcher(),
    file: FileMatcher = FileMatcher()
  ) {
    self.paths = paths
    self.excludePaths = excludePaths
    self.frontmatter = frontmatter
    self.frontmatterQuery = frontmatterQuery
    self.document = document
    self.file = file
  }
  /// Creates a configured instance.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  init(json: [String: Any], ruleName: String) throws {
    let paths = json["paths"] as? [String] ?? []
    let excludePaths = json["excludePaths"] as? [String] ?? []
    let frontmatterObject = json["frontmatter"] as? [String: Any] ?? [:]
    let frontmatterQueryObject = json["frontmatterQuery"] as? [String: Any] ?? [:]
    let documentObject = json["document"] as? [String: Any] ?? [:]
    let fileObject = json["file"] as? [String: Any] ?? [:]
    var frontmatter: [String: FrontmatterMatcher] = [:]

    for (key, rawMatcher) in frontmatterObject {
      guard let matcherObject = rawMatcher as? [String: Any] else {
        throw ValidationError("Rule \"\(ruleName)\" has invalid frontmatter matcher for \"\(key)\"")
      }
      frontmatter[key] = try FrontmatterMatcher(json: matcherObject, key: key, ruleName: ruleName)
    }

    let frontmatterQuery = try FrontmatterQueryMatcher(json: frontmatterQueryObject, ruleName: ruleName)
    let document = try DocumentMatcher(json: documentObject, ruleName: ruleName)
    let file = try FileMatcher(json: fileObject, ruleName: ruleName)

    if paths.isEmpty && frontmatter.isEmpty && frontmatterQuery.isEmpty && document.isEmpty && file.isEmpty {
      throw ValidationError("Rule \"\(ruleName)\" must define at least one match condition")
    }

    self.paths = paths
    self.excludePaths = excludePaths
    self.frontmatter = frontmatter
    self.frontmatterQuery = frontmatterQuery
    self.document = document
    self.file = file
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
    if !frontmatterQuery.isEmpty {
      object["frontmatterQuery"] = frontmatterQuery.jsonObject
    }
    if !document.isEmpty {
      object["document"] = document.jsonObject
    }
    if !file.isEmpty {
      object["file"] = file.jsonObject
    }
    return object
  }
}

/// Describes whole-frontmatter query predicates that select files for a rule.
struct FrontmatterQueryMatcher: Equatable {
  var jmespath: String?

  var isEmpty: Bool { jmespath == nil }

  init(jmespath: String? = nil) {
    self.jmespath = jmespath
  }

  init(json: [String: Any], ruleName: String) throws {
    if let jmespath = json["jmespath"] as? String, !jmespath.isEmpty {
      _ = try compileJMESPath(jmespath, ruleName: ruleName)
      self.jmespath = jmespath
    } else if json["jmespath"] != nil {
      throw ValidationError("Rule \"\(ruleName)\" frontmatterQuery jmespath matcher requires a non-empty expression")
    } else {
      self.jmespath = nil
    }

    let supported = Set(["jmespath"])
    let unsupported = json.keys.filter { !supported.contains($0) }
    if let firstUnsupported = unsupported.sorted().first {
      throw ValidationError("Rule \"\(ruleName)\" has unsupported frontmatterQuery matcher \"\(firstUnsupported)\"")
    }
  }

  var jsonObject: [String: Any] {
    var object: [String: Any] = [:]
    if let jmespath {
      object["jmespath"] = jmespath
    }
    return object
  }
}

/// Describes Markdown document conditions that select files for a rule.
struct DocumentMatcher: Equatable {
  var hasHeading: String?
  var headingRegex: String?
  var hasHeadingAtLevel: HeadingLevelMatcher?
  var hasSection: String?
  var bodyContains: String?
  var bodyRegex: String?
  var hasWikilink: WikilinkMatcher?
  var lineCount: CountRange?
  var wordCount: CountRange?

  var isEmpty: Bool {
    hasHeading == nil && headingRegex == nil && hasHeadingAtLevel == nil && hasSection == nil
      && bodyContains == nil && bodyRegex == nil && hasWikilink == nil && lineCount == nil && wordCount == nil
  }

  init(
    hasHeading: String? = nil,
    headingRegex: String? = nil,
    hasHeadingAtLevel: HeadingLevelMatcher? = nil,
    hasSection: String? = nil,
    bodyContains: String? = nil,
    bodyRegex: String? = nil,
    hasWikilink: WikilinkMatcher? = nil,
    lineCount: CountRange? = nil,
    wordCount: CountRange? = nil
  ) {
    self.hasHeading = hasHeading
    self.headingRegex = headingRegex
    self.hasHeadingAtLevel = hasHeadingAtLevel
    self.hasSection = hasSection
    self.bodyContains = bodyContains
    self.bodyRegex = bodyRegex
    self.hasWikilink = hasWikilink
    self.lineCount = lineCount
    self.wordCount = wordCount
  }

  init(json: [String: Any], ruleName: String) throws {
    if let hasHeading = json["hasHeading"] as? String, !hasHeading.isEmpty {
      self.hasHeading = hasHeading
    } else if json["hasHeading"] != nil {
      throw ValidationError("Rule \"\(ruleName)\" document hasHeading matcher requires a non-empty heading")
    } else {
      self.hasHeading = nil
    }

    self.headingRegex = try Self.regex(json["headingRegex"], name: "headingRegex", ruleName: ruleName)
    self.hasHeadingAtLevel = try Self.headingLevel(json["hasHeadingAtLevel"], ruleName: ruleName)
    self.hasSection = try Self.nonEmptyString(json["hasSection"], name: "hasSection", ruleName: ruleName)
    self.bodyContains = try Self.nonEmptyString(json["bodyContains"], name: "bodyContains", ruleName: ruleName)
    self.bodyRegex = try Self.regex(json["bodyRegex"], name: "bodyRegex", ruleName: ruleName)
    self.hasWikilink = try Self.wikilink(json["hasWikilink"], ruleName: ruleName)
    self.lineCount = try Self.countRange(json["lineCount"], name: "lineCount", ruleName: ruleName)
    self.wordCount = try Self.countRange(json["wordCount"], name: "wordCount", ruleName: ruleName)

    let supported = Set(["hasHeading", "headingRegex", "hasHeadingAtLevel", "hasSection", "bodyContains", "bodyRegex", "hasWikilink", "lineCount", "wordCount"])
    let unsupported = json.keys.filter { !supported.contains($0) }
    if let firstUnsupported = unsupported.sorted().first {
      throw ValidationError("Rule \"\(ruleName)\" has unsupported document matcher \"\(firstUnsupported)\"")
    }
  }

  private static func nonEmptyString(_ value: Any?, name: String, ruleName: String) throws -> String? {
    guard let value else { return nil }
    guard let string = value as? String, !string.isEmpty else {
      throw ValidationError("Rule \"\(ruleName)\" document \(name) matcher requires a non-empty string")
    }
    return string
  }

  private static func regex(_ value: Any?, name: String, ruleName: String) throws -> String? {
    guard let string = try nonEmptyString(value, name: name, ruleName: ruleName) else { return nil }
    try validateRegex(string, context: "Rule \"\(ruleName)\" document \(name)")
    return string
  }

  private static func headingLevel(_ value: Any?, ruleName: String) throws -> HeadingLevelMatcher? {
    guard let value else { return nil }
    guard let object = value as? [String: Any] else {
      throw ValidationError("Rule \"\(ruleName)\" document hasHeadingAtLevel matcher requires an object")
    }
    return try HeadingLevelMatcher(json: object, ruleName: ruleName)
  }

  private static func wikilink(_ value: Any?, ruleName: String) throws -> WikilinkMatcher? {
    guard let value else { return nil }
    return try WikilinkMatcher(value: value, ruleName: ruleName)
  }

  private static func countRange(_ value: Any?, name: String, ruleName: String) throws -> CountRange? {
    guard let value else { return nil }
    guard let object = value as? [String: Any] else {
      throw ValidationError("Rule \"\(ruleName)\" document \(name) matcher requires an object")
    }
    return try CountRange(json: object, context: "Rule \"\(ruleName)\" document \(name)")
  }

  var jsonObject: [String: Any] {
    var object: [String: Any] = [:]
    if let hasHeading {
      object["hasHeading"] = hasHeading
    }
    if let headingRegex { object["headingRegex"] = headingRegex }
    if let hasHeadingAtLevel { object["hasHeadingAtLevel"] = hasHeadingAtLevel.jsonObject }
    if let hasSection { object["hasSection"] = hasSection }
    if let bodyContains { object["bodyContains"] = bodyContains }
    if let bodyRegex { object["bodyRegex"] = bodyRegex }
    if let hasWikilink { object["hasWikilink"] = hasWikilink.jsonValue }
    if let lineCount { object["lineCount"] = lineCount.jsonObject }
    if let wordCount { object["wordCount"] = wordCount.jsonObject }
    return object
  }
}
/// Describes an exact heading text at a specific Markdown heading level.
struct HeadingLevelMatcher: Equatable {
  var heading: String
  var level: Int

  init(json: [String: Any], ruleName: String) throws {
    guard let heading = json["heading"] as? String, !heading.isEmpty else {
      throw ValidationError("Rule \"\(ruleName)\" document hasHeadingAtLevel matcher requires a non-empty heading")
    }
    guard let level = json["level"] as? Int, (1...6).contains(level) else {
      throw ValidationError("Rule \"\(ruleName)\" document hasHeadingAtLevel matcher requires level 1...6")
    }
    self.heading = heading
    self.level = level
  }

  var jsonObject: [String: Any] { ["heading": heading, "level": level] }
}
/// Describes an inclusive integer range.
struct CountRange: Equatable {
  var min: Int?
  var max: Int?

  init(json: [String: Any], context: String) throws {
    let min = json["min"] as? Int
    let max = json["max"] as? Int
    guard min != nil || max != nil else { throw ValidationError("\(context) matcher requires min or max") }
    if let min, min < 0 { throw ValidationError("\(context) min must be non-negative") }
    if let max, max < 0 { throw ValidationError("\(context) max must be non-negative") }
    if let min, let max, min > max { throw ValidationError("\(context) min must be less than or equal to max") }
    self.min = min
    self.max = max
  }

  var jsonObject: [String: Any] {
    var object: [String: Any] = [:]
    if let min { object["min"] = min }
    if let max { object["max"] = max }
    return object
  }

  func contains(_ value: Int) -> Bool {
    if let min, value < min { return false }
    if let max, value > max { return false }
    return true
  }
}
/// Describes a wikilink existence or target matcher.
struct WikilinkMatcher: Equatable {
  var target: String?

  init(value: Any, ruleName: String) throws {
    if let bool = value as? Bool {
      guard bool else {
        throw ValidationError("Rule \"\(ruleName)\" document hasWikilink matcher only supports true or a target string")
      }
      self.target = nil
    } else if let string = value as? String, !string.isEmpty {
      self.target = string
    } else {
      throw ValidationError("Rule \"\(ruleName)\" document hasWikilink matcher requires true or a non-empty target string")
    }
  }

  var jsonValue: Any { target ?? true }
}
/// Describes path and file metadata conditions that select files for a rule.
struct FileMatcher: Equatable {
  var pathRegex: String?
  var filenameEquals: String?
  var extensionIn: [String]
  var modifiedAfter: DateTimeLiteral?
  var modifiedBefore: DateTimeLiteral?

  var isEmpty: Bool {
    pathRegex == nil && filenameEquals == nil && extensionIn.isEmpty && modifiedAfter == nil && modifiedBefore == nil
  }

  init(
    pathRegex: String? = nil,
    filenameEquals: String? = nil,
    extensionIn: [String] = [],
    modifiedAfter: DateTimeLiteral? = nil,
    modifiedBefore: DateTimeLiteral? = nil
  ) {
    self.pathRegex = pathRegex
    self.filenameEquals = filenameEquals
    self.extensionIn = extensionIn
    self.modifiedAfter = modifiedAfter
    self.modifiedBefore = modifiedBefore
  }

  init(json: [String: Any], ruleName: String) throws {
    if let pathRegex = json["pathRegex"] as? String, !pathRegex.isEmpty {
      try validateRegex(pathRegex, context: "Rule \"\(ruleName)\" file pathRegex")
      self.pathRegex = pathRegex
    } else if json["pathRegex"] != nil {
      throw ValidationError("Rule \"\(ruleName)\" file pathRegex matcher requires a non-empty regex")
    } else {
      self.pathRegex = nil
    }

    if let filenameEquals = json["filenameEquals"] as? String, !filenameEquals.isEmpty {
      self.filenameEquals = filenameEquals
    } else if json["filenameEquals"] != nil {
      throw ValidationError("Rule \"\(ruleName)\" file filenameEquals matcher requires a non-empty string")
    } else {
      self.filenameEquals = nil
    }

    if let extensionIn = json["extensionIn"] as? [String], !extensionIn.isEmpty {
      self.extensionIn = extensionIn.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
      if self.extensionIn.contains(where: { $0.isEmpty }) {
        throw ValidationError("Rule \"\(ruleName)\" file extensionIn matcher requires non-empty extensions")
      }
    } else if json["extensionIn"] != nil {
      throw ValidationError("Rule \"\(ruleName)\" file extensionIn matcher requires a non-empty string array")
    } else {
      self.extensionIn = []
    }

    self.modifiedAfter = try Self.dateTime(json["modifiedAfter"], name: "modifiedAfter", ruleName: ruleName)
    self.modifiedBefore = try Self.dateTime(json["modifiedBefore"], name: "modifiedBefore", ruleName: ruleName)

    let supported = Set(["pathRegex", "filenameEquals", "extensionIn", "modifiedAfter", "modifiedBefore"])
    let unsupported = json.keys.filter { !supported.contains($0) }
    if let firstUnsupported = unsupported.sorted().first {
      throw ValidationError("Rule \"\(ruleName)\" has unsupported file matcher \"\(firstUnsupported)\"")
    }
  }

  private static func dateTime(_ value: Any?, name: String, ruleName: String) throws -> DateTimeLiteral? {
    guard let value else { return nil }
    guard let string = value as? String, let literal = DateTimeLiteral(string) else {
      throw ValidationError("Rule \"\(ruleName)\" file \(name) matcher requires YYYY-MM-DD or RFC 3339 date-time")
    }
    return literal
  }

  var jsonObject: [String: Any] {
    var object: [String: Any] = [:]
    if let pathRegex { object["pathRegex"] = pathRegex }
    if let filenameEquals { object["filenameEquals"] = filenameEquals }
    if !extensionIn.isEmpty { object["extensionIn"] = extensionIn }
    if let modifiedAfter { object["modifiedAfter"] = modifiedAfter.rawValue }
    if let modifiedBefore { object["modifiedBefore"] = modifiedBefore.rawValue }
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
    let supported = Set([
      "includes", "equals", "notIncludes", "doesntEqual", "hasKey", "doesntHaveKey", "regex", "startsWith",
      "endsWith", "contains", "empty", "emptyString", "emptyArray", "emptyObject", "notEmpty", "in", "notIn",
      "greaterThan", "greaterThanOrEqual", "lessThan", "lessThanOrEqual", "after", "onOrAfter", "before",
      "onOrBefore", "between", "typeIs",
    ])
    let operators = json.filter { supported.contains($0.key) }
    guard !operators.isEmpty else {
      throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" requires a supported operator")
    }
    if let unsupported = json.keys.first(where: { !supported.contains($0) }) {
      throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" has unsupported operator \"\(unsupported)\"")
    }
    try Self.validateOperands(operators, key: key, ruleName: ruleName)
    self.operators = operators
  }

  private static func validateOperands(_ operators: [String: Any], key: String, ruleName: String) throws {
    for (operatorName, operand) in operators {
      switch operatorName {
      case "hasKey", "doesntHaveKey", "empty", "emptyString", "emptyArray", "emptyObject", "notEmpty":
        if let bool = operand as? Bool, bool == true { continue }
        throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" operator \"\(operatorName)\" requires true")
      case "regex":
        guard let pattern = operand as? String, !pattern.isEmpty else {
          throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" regex requires a non-empty string")
        }
        try validateRegex(pattern, context: "Rule \"\(ruleName)\" frontmatter \"\(key)\" regex")
      case "startsWith", "endsWith", "contains":
        guard let string = operand as? String, !string.isEmpty else {
          throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" operator \"\(operatorName)\" requires a non-empty string")
        }
      case "in", "notIn":
        guard let array = operand as? [Any], !array.isEmpty else {
          throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" operator \"\(operatorName)\" requires a non-empty array")
        }
      case "greaterThan", "greaterThanOrEqual", "lessThan", "lessThanOrEqual":
        guard numericValue(operand) != nil else {
          throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" operator \"\(operatorName)\" requires a number")
        }
      case "after", "onOrAfter", "before", "onOrBefore":
        guard let string = operand as? String, DateTimeLiteral(string) != nil else {
          throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" operator \"\(operatorName)\" requires YYYY-MM-DD or RFC 3339 date-time")
        }
      case "between":
        if let range = operand as? [String: Any], range["from"] != nil || range["to"] != nil {
          guard let fromValue = range["from"], let toValue = range["to"] else {
            throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" between requires from and to")
          }
          if let from = numericValue(fromValue), let to = numericValue(toValue) {
            if from > to { throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" between from must be less than or equal to to") }
          } else if let fromString = fromValue as? String, let toString = toValue as? String,
                    let from = DateTimeLiteral(fromString), let to = DateTimeLiteral(toString) {
            guard dateTimeCompare(from, to, precision: min(from.precision, to.precision)) != .orderedDescending else {
              throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" between from must be less than or equal to to")
            }
          } else {
            throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" between requires numeric or date/time bounds")
          }
        } else {
          throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" between requires from and to")
        }
      case "typeIs":
        guard let type = operand as? String, ["string", "boolean", "number", "array", "object", "null"].contains(type) else {
          throw ValidationError("Rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" typeIs requires string, boolean, number, array, object, or null")
        }
      default:
        continue
      }
    }
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
  static func projectDirectory(root: Path) -> Path {
    root.absolute() + projectDirectory
  }
  static func configFile(root: Path) -> Path {
    projectDirectory(root: root) + "md-utils.json"
  }
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
struct ConfigInitializationResult {
  var configFile: Path
  var configSchemaFile: Path
  var configCreated: Bool
}
/// Bootstraps the `.md-utils` project configuration files.
///
/// See <doc:RulesValidationCommands> for workflow details.
enum RulesConfigBootstrapper {
  /// Creates the project configuration directory and bundled schema file when needed.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func ensureProjectFiles(root: Path = .current) throws -> ConfigInitializationResult {
    let projectDirectory = RulesPaths.projectDirectory(root: root)
    let configFile = RulesPaths.configFile(root: root)
    let schemaDirectory = root.absolute() + Path(MdUtilsConfig.defaultSchemaDirectory)
    let typesDirectory = projectDirectory + "types"
    let configSchemaFile = projectDirectory + RulesPaths.bundledConfigSchemaFileName
    try projectDirectory.mkpath()
    try schemaDirectory.mkpath()
    try typesDirectory.mkpath()
    try copyBundledConfigSchema(to: configSchemaFile)

    let configCreated = configFile.exists == false
    if configCreated {
      try MdUtilsConfig().save(to: configFile)
    }
    return ConfigInitializationResult(
      configFile: configFile,
      configSchemaFile: configSchemaFile,
      configCreated: configCreated
    )
  }
  /// Copies the bundled md-utils configuration schema into the project directory.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  private static func copyBundledConfigSchema(to destination: Path) throws {
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
      throw ValidationError("Rule already exists: \"\(options.name)\"")
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
      throw ValidationError("Rule not found: \"\(name)\"")
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
/// Records whether one configured rule matches a specific Markdown file.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleMatchEvaluation {
  var rule: Rule
  var matched: Bool
  var reasons: [String]
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
        throw ValidationError("Rule not found: \"\(ruleName)\"")
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
      let pathMatchedRules = rules.filter {
        rulePathConditionsMatch(rule: $0, relativePath: relativePath)
          && ruleFileConditionsMatch(rule: $0, file: file, relativePath: relativePath)
      }
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
          if !rule.match.frontmatter.isEmpty || !rule.match.frontmatterQuery.isEmpty {
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
          guard frontmatterQueryConditionsMatch(rule: rule, frontmatter: parsedFrontmatter) else { continue }
        }
        guard documentConditionsMatch(rule: rule, document: document) else { continue }

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
      throw ValidationError("Rule not found: \"\(ruleName)\"")
    }

    let files = try RuleFileScanner.markdownFiles(root: root)
    var matches: [Path] = []
    for file in files {
      let relativePath = relativePath(from: root, to: file)
      guard rulePathConditionsMatch(rule: rule, relativePath: relativePath) else { continue }
      guard ruleFileConditionsMatch(rule: rule, file: file, relativePath: relativePath) else { continue }
      guard !rule.match.frontmatter.isEmpty || !rule.match.frontmatterQuery.isEmpty || !rule.match.document.isEmpty else {
        matches.append(file)
        continue
      }

      let content = try file.read(.utf8)
      let frontmatterPresence = frontmatterPresence(in: content)
      do {
        let document = try MarkdownDocument(content: content)
        if !rule.match.frontmatter.isEmpty || !rule.match.frontmatterQuery.isEmpty {
          guard frontmatterPresence.hasFrontmatter else { continue }
          let parsedFrontmatter = try YAMLConversion.safeNodeToSwiftValue(.mapping(document.frontMatter))
          guard frontmatterConditionsMatch(rule: rule, frontmatter: parsedFrontmatter) else { continue }
          guard frontmatterQueryConditionsMatch(rule: rule, frontmatter: parsedFrontmatter) else { continue }
        }
        if documentConditionsMatch(rule: rule, document: document) {
          matches.append(file)
        }
      } catch {
        continue
      }
    }
    return matches
  }

  static func rulesMatching(
    fileName: String,
    root: Path = .current,
    configPath: Path = RulesPaths.configFile
  ) throws -> [RuleMatchEvaluation] {
    let config = try MdUtilsConfig.load(from: configPath)
    let file = Path(fileName)
    guard file.exists else {
      throw ValidationError("Markdown file not found: \(fileName)")
    }

    let relativePath = relativePath(from: root, to: file)
    return try config.schemaRules.map { rule in
      try evaluateRuleMatch(rule: rule, file: file, relativePath: relativePath)
    }
  }

  private static func evaluateRuleMatch(rule: Rule, file: Path, relativePath: String) throws -> RuleMatchEvaluation {
    var reasons: [String] = []

    if let excluded = rule.match.excludePaths.first(where: { matchesGlob(relativePath, glob: $0) }) {
      return RuleMatchEvaluation(
        rule: rule,
        matched: false,
        reasons: ["path \"\(relativePath)\" is excluded by \"\(excluded)\""]
      )
    }

    if rule.match.paths.isEmpty {
      reasons.append("no path patterns configured")
    } else if let matchedPath = rule.match.paths.first(where: { matchesGlob(relativePath, glob: $0) }) {
      reasons.append("path \"\(relativePath)\" matched \"\(matchedPath)\"")
    } else {
      return RuleMatchEvaluation(
        rule: rule,
        matched: false,
        reasons: ["path \"\(relativePath)\" did not match any configured path pattern"]
      )
    }

    guard ruleFileConditionsMatch(rule: rule, file: file, relativePath: relativePath) else {
      return RuleMatchEvaluation(rule: rule, matched: false, reasons: reasons + ["file metadata did not match"])
    }

    guard !rule.match.frontmatter.isEmpty || !rule.match.frontmatterQuery.isEmpty || !rule.match.document.isEmpty else {
      return RuleMatchEvaluation(rule: rule, matched: true, reasons: reasons)
    }

    let content = try file.read(.utf8)
    let frontmatterPresence = frontmatterPresence(in: content)
    let document: MarkdownDocument
    do {
      document = try MarkdownDocument(content: content)
    } catch {
      reasons.append("document invalid: \(error.localizedDescription)")
      return RuleMatchEvaluation(rule: rule, matched: false, reasons: reasons)
    }

    if !rule.match.frontmatter.isEmpty || !rule.match.frontmatterQuery.isEmpty {
      guard frontmatterPresence.hasFrontmatter else {
        reasons.append("frontmatter not present")
        return RuleMatchEvaluation(rule: rule, matched: false, reasons: reasons)
      }

      let parsedFrontmatter: Any
      do {
        parsedFrontmatter = try YAMLConversion.safeNodeToSwiftValue(.mapping(document.frontMatter))
      } catch {
        reasons.append("frontmatter invalid: \(error.localizedDescription)")
        return RuleMatchEvaluation(rule: rule, matched: false, reasons: reasons)
      }

      guard let object = parsedFrontmatter as? [String: Any] else {
        reasons.append("frontmatter is not an object")
        return RuleMatchEvaluation(rule: rule, matched: false, reasons: reasons)
      }

      for (key, matcher) in rule.match.frontmatter.sorted(by: { $0.key < $1.key }) {
        guard frontmatterValue(object[key], matches: matcher, keyExists: object.keys.contains(key)) else {
          if object[key] == nil {
            reasons.append("frontmatter \"\(key)\" is missing")
          } else {
            reasons.append("frontmatter \"\(key)\" did not match \(frontmatterMatcherDescription(matcher))")
          }
          return RuleMatchEvaluation(rule: rule, matched: false, reasons: reasons)
        }
        reasons.append("frontmatter \"\(key)\" matched \(frontmatterMatcherDescription(matcher))")
      }

      guard frontmatterQueryConditionsMatch(rule: rule, frontmatter: parsedFrontmatter) else {
        reasons.append("frontmatterQuery did not match")
        return RuleMatchEvaluation(rule: rule, matched: false, reasons: reasons)
      }
      if !rule.match.frontmatterQuery.isEmpty {
        reasons.append("frontmatterQuery matched")
      }
    }

    guard documentConditionsMatch(rule: rule, document: document) else {
      reasons.append("document predicates did not match")
      return RuleMatchEvaluation(rule: rule, matched: false, reasons: reasons)
    }

    return RuleMatchEvaluation(rule: rule, matched: true, reasons: reasons)
  }

  /// Returns whether file metadata satisfies a rule file condition.
  private static func ruleFileConditionsMatch(rule: Rule, file: Path, relativePath: String) -> Bool {
    let matcher = rule.match.file
    guard !matcher.isEmpty else { return true }

    if let pathRegex = matcher.pathRegex, !regexMatches(relativePath, pattern: pathRegex) { return false }
    if let filenameEquals = matcher.filenameEquals, file.lastComponent != filenameEquals { return false }
    if !matcher.extensionIn.isEmpty {
      guard let ext = file.extension?.lowercased(), matcher.extensionIn.contains(ext) else { return false }
    }
    if matcher.modifiedAfter != nil || matcher.modifiedBefore != nil {
      guard let modified = fileModificationDate(file) else { return false }
      let literal = DateTimeLiteral(date: modified, precision: .dateTime)
      if let modifiedAfter = matcher.modifiedAfter,
         dateTimeCompare(literal, modifiedAfter, precision: modifiedAfter.precision) != .orderedDescending {
        return false
      }
      if let modifiedBefore = matcher.modifiedBefore,
         dateTimeCompare(literal, modifiedBefore, precision: modifiedBefore.precision) != .orderedAscending {
        return false
      }
    }
    return true
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
      if !frontmatterValue(object[key], matches: matcher, keyExists: object.keys.contains(key)) {
        return false
      }
    }
    return true
  }

  private static func frontmatterQueryConditionsMatch(rule: Rule, frontmatter: Any) -> Bool {
    guard let query = rule.match.frontmatterQuery.jmespath else { return true }
    guard let expression = try? compileJMESPath(query, ruleName: rule.name) else { return false }
    guard let result = try? expression.search(object: frontmatter) else { return false }
    return isTruthy(result)
  }

  private static func documentConditionsMatch(rule: Rule, document: MarkdownDocument?) -> Bool {
    let matcher = rule.match.document
    let body = document?.body ?? ""
    let headings = parsedHeadings(in: body)
    if let hasHeading = matcher.hasHeading {
      guard headings.contains(where: { $0.text == hasHeading }) else { return false }
    }
    if let headingRegex = matcher.headingRegex {
      guard headings.contains(where: { regexMatches($0.text, pattern: headingRegex) }) else { return false }
    }
    if let hasHeadingAtLevel = matcher.hasHeadingAtLevel {
      guard headings.contains(where: { $0.text == hasHeadingAtLevel.heading && $0.level == hasHeadingAtLevel.level }) else { return false }
    }
    if let hasSection = matcher.hasSection {
      guard sectionExists(heading: hasSection, in: body) else { return false }
    }
    if let bodyContains = matcher.bodyContains {
      guard body.contains(bodyContains) else { return false }
    }
    if let bodyRegex = matcher.bodyRegex {
      guard regexMatches(body, pattern: bodyRegex) else { return false }
    }
    if let hasWikilink = matcher.hasWikilink {
      guard wikilinkMatches(body: body, matcher: hasWikilink) else { return false }
    }
    if let lineCount = matcher.lineCount {
      guard lineCount.contains(bodyLineCount(body)) else { return false }
    }
    if let wordCount = matcher.wordCount {
      guard wordCount.contains(bodyWordCount(body)) else { return false }
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
    var portableChecks: [MarkdownUtilitiesCore.MarkdownRuleCheck] = []
    for (index, check) in rule.checks.enumerated() {
      switch check {
      case .frontmatterSchema(let schemaFilename, _):
        guard parsedFrontmatter != nil else { continue }
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

        portableChecks.append(.frontmatterSchema(
          id: "\(rule.name).check[\(index)]",
          schema: try JSONValue(any: schema)
        ))
      case .requiredHeading(let heading):
        portableChecks.append(.requiredHeading(
          id: "\(rule.name).check[\(index)]",
          heading: heading
        ))
      case .maxBodyLines(let max):
        portableChecks.append(.maxBodyLines(
          id: "\(rule.name).check[\(index)]",
          maximum: max
        ))
      case .maxBodyWords(let max):
        portableChecks.append(.maxBodyWords(
          id: "\(rule.name).check[\(index)]",
          maximum: max
        ))
      }
    }
    let frontmatter = try parsedFrontmatter.map { try JSONValue(any: jsonCompatibleValue($0)) }
    let diagnostics = try MarkdownRuleCheckEvaluator.evaluate(
      portableChecks,
      input: MarkdownRuleCheckInput(
        frontmatter: frontmatter,
        body: document?.body ?? ""
      )
    )
    return diagnostics.map { diagnostic in
      RuleValidationErrorDetail(path: diagnostic.location, message: diagnostic.message)
    }
  }

  private static func hasOnlyOptionalFrontmatterSchemaChecks(_ rule: Rule) -> Bool {
    !rule.checks.isEmpty && rule.checks.allSatisfy { check in
      if case .frontmatterSchema(_, let frontmatterRequired) = check {
        return !frontmatterRequired
      }
      return false
    }
  }

  private static func frontmatterValue(_ value: Any?, matches matcher: FrontmatterMatcher, keyExists: Bool = true) -> Bool {
    for (operatorName, operand) in matcher.operators {
      switch operatorName {
      case "hasKey":
        guard keyExists else { return false }
      case "doesntHaveKey":
        guard !keyExists else { return false }
      default:
        guard keyExists, let value else { return false }
        if !frontmatterExistingValue(value, matches: operatorName, operand: operand) { return false }
      }
    }
    return true
  }

  private static func frontmatterExistingValue(_ value: Any, matches operatorName: String, operand: Any) -> Bool {
    switch operatorName {
      case "includes":
        guard let array = value as? [Any], array.contains(where: { jsonValuesEqual($0, operand) }) else { return false }
      case "notIncludes":
        guard let array = value as? [Any], !array.contains(where: { jsonValuesEqual($0, operand) }) else { return false }
      case "equals":
        guard jsonValuesEqual(value, operand) else { return false }
      case "doesntEqual":
        guard !jsonValuesEqual(value, operand) else { return false }
      case "regex":
        guard let string = value as? String, let pattern = operand as? String, regexMatches(string, pattern: pattern) else { return false }
      case "startsWith":
        guard let string = value as? String, let prefix = operand as? String, string.hasPrefix(prefix) else { return false }
      case "endsWith":
        guard let string = value as? String, let suffix = operand as? String, string.hasSuffix(suffix) else { return false }
      case "contains":
        guard let string = value as? String, let substring = operand as? String, string.contains(substring) else { return false }
      case "empty":
        guard isEmptyValue(value) else { return false }
      case "emptyString":
        guard let string = value as? String, string.isEmpty else { return false }
      case "emptyArray":
        guard let array = value as? [Any], array.isEmpty else { return false }
      case "emptyObject":
        guard let object = value as? [String: Any], object.isEmpty else { return false }
      case "notEmpty":
        guard !isEmptyValue(value) else { return false }
      case "in":
        guard let array = operand as? [Any], array.contains(where: { jsonValuesEqual(value, $0) }) else { return false }
      case "notIn":
        guard let array = operand as? [Any], !array.contains(where: { jsonValuesEqual(value, $0) }) else { return false }
      case "greaterThan":
        guard compareNumbers(value, operand) == .orderedDescending else { return false }
      case "greaterThanOrEqual":
        let comparison = compareNumbers(value, operand)
        guard comparison == .orderedDescending || comparison == .orderedSame else { return false }
      case "lessThan":
        guard compareNumbers(value, operand) == .orderedAscending else { return false }
      case "lessThanOrEqual":
        let comparison = compareNumbers(value, operand)
        guard comparison == .orderedAscending || comparison == .orderedSame else { return false }
      case "after":
        guard compareDateTime(value, operand: operand) == .orderedDescending else { return false }
      case "onOrAfter":
        let comparison = compareDateTime(value, operand: operand)
        guard comparison == .orderedDescending || comparison == .orderedSame else { return false }
      case "before":
        guard compareDateTime(value, operand: operand) == .orderedAscending else { return false }
      case "onOrBefore":
        let comparison = compareDateTime(value, operand: operand)
        guard comparison == .orderedAscending || comparison == .orderedSame else { return false }
      case "between":
        guard betweenMatches(value: value, range: operand) else { return false }
      case "typeIs":
        guard let expectedType = operand as? String, jsonTypeName(value) == expectedType else { return false }
      case "hasKey", "doesntHaveKey":
        break
      default:
        return false
      }
    return true
  }

  private static func frontmatterMatcherDescription(_ matcher: FrontmatterMatcher) -> String {
    matcher.operators.sorted(by: { $0.key < $1.key }).map { operatorName, operand in
      "\(operatorName) \(jsonValueDescription(operand))"
    }.joined(separator: ", ")
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
/// Returns a compact display representation for JSON-compatible values.
func jsonValueDescription(_ value: Any) -> String {
  let normalized = jsonCompatibleValue(value)
  if JSONSerialization.isValidJSONObject([normalized]),
     let data = try? JSONSerialization.data(withJSONObject: [normalized], options: [.sortedKeys]),
     let json = String(data: data, encoding: .utf8),
     json.hasPrefix("["), json.hasSuffix("]") {
    let start = json.index(after: json.startIndex)
    let end = json.index(before: json.endIndex)
    return String(json[start..<end])
  }
  return String(describing: normalized)
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
/// Date/time precision used by rules predicates.
enum DateTimePrecision: Comparable {
  case date
  case dateTime
}

/// Parsed date or date-time literal for precision-aware comparisons.
struct DateTimeLiteral: Equatable {
  var rawValue: String
  var date: Date
  var precision: DateTimePrecision

  init?(_ rawValue: String) {
    if let date = Self.dateOnlyFormatter.date(from: rawValue) {
      self.rawValue = rawValue
      self.date = date
      self.precision = .date
      return
    }

    if let date = Self.isoFormatter().date(from: rawValue) ?? Self.isoFormatterWithoutFractionalSeconds().date(from: rawValue) {
      self.rawValue = rawValue
      self.date = date
      self.precision = .dateTime
      return
    }

    return nil
  }

  init(date: Date, precision: DateTimePrecision = .date) {
    self.rawValue = Self.isoFormatterWithoutFractionalSeconds().string(from: date)
    self.date = date
    self.precision = precision
  }

  private static let dateOnlyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static func isoFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  private static func isoFormatterWithoutFractionalSeconds() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }

  private static func dateOnlyComponents(_ date: Date) -> DateComponents {
    Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0) ?? .gmt, from: date)
  }

  var dateKey: String {
    let components = Self.dateOnlyComponents(date)
    let year = components.year ?? 0
    let month = components.month ?? 0
    let day = components.day ?? 0
    return String(format: "%04d-%02d-%02d", year, month, day)
  }
}

extension DateTimeLiteral {
  static func parse(_ value: Any) -> DateTimeLiteral? {
    if let string = value as? String {
      return DateTimeLiteral(string)
    }
    if let date = value as? Date {
      return DateTimeLiteral(date: date)
    }
    return nil
  }
}

extension TimeZone {
  fileprivate static var gmt: TimeZone {
    TimeZone(secondsFromGMT: 0) ?? TimeZone.current
  }
}

/// Returns whether a string matches a configured regular expression.
func regexMatches(_ value: String, pattern: String) -> Bool {
  guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
  let range = NSRange(value.startIndex..., in: value)
  return expression.firstMatch(in: value, range: range) != nil
}

/// Validates a regular expression at config load time.
func validateRegex(_ pattern: String, context: String) throws {
  do {
    _ = try NSRegularExpression(pattern: pattern)
  } catch {
    throw ValidationError("\(context) regex is invalid: \(error.localizedDescription)")
  }
}

/// Compiles a JMESPath expression and wraps parser errors with rule context.
func compileJMESPath(_ query: String, ruleName: String) throws -> JMESExpression {
  do {
    return try JMESExpression.compile(query)
  } catch {
    throw ValidationError("Rule \"\(ruleName)\" frontmatterQuery jmespath expression is invalid: \(error.localizedDescription)")
  }
}

/// Returns truthiness using the same rules as `fm search`.
func isTruthy(_ value: Any?) -> Bool {
  guard let value else { return false }
  if let bool = value as? Bool { return bool }
  if let string = value as? String { return !string.isEmpty }
  if let array = value as? [Any] { return !array.isEmpty }
  if let dict = value as? [String: Any] { return !dict.isEmpty }
  return true
}

/// Returns a numeric value for JSON/YAML scalar comparisons.
func numericValue(_ value: Any) -> Double? {
  if let int = value as? Int { return Double(int) }
  if let double = value as? Double { return double }
  if let float = value as? Float { return Double(float) }
  if let number = value as? NSNumber { return number.doubleValue }
  return nil
}

/// Compares two numeric values.
func compareNumbers(_ lhs: Any, _ rhs: Any) -> ComparisonResult? {
  guard let left = numericValue(lhs), let right = numericValue(rhs) else { return nil }
  if left < right { return .orderedAscending }
  if left > right { return .orderedDescending }
  return .orderedSame
}

/// Compares two date/time literals at the requested precision.
func dateTimeCompare(_ lhs: DateTimeLiteral, _ rhs: DateTimeLiteral, precision: DateTimePrecision) -> ComparisonResult {
  switch precision {
  case .date:
    return lhs.dateKey.compare(rhs.dateKey)
  case .dateTime:
    return lhs.date.compare(rhs.date)
  }
}

/// Compares a frontmatter value against a date/time predicate operand.
func compareDateTime(_ value: Any, operand: Any) -> ComparisonResult? {
  guard let left = DateTimeLiteral.parse(value), let right = DateTimeLiteral.parse(operand) else { return nil }
  guard left.precision >= right.precision else { return nil }
  return dateTimeCompare(left, right, precision: right.precision)
}

/// Returns whether a value falls inside an inclusive numeric or date/time range.
func betweenMatches(value: Any, range: Any) -> Bool {
  guard let range = range as? [String: Any], let from = range["from"], let to = range["to"] else { return false }
  if let valueNumber = numericValue(value), let fromNumber = numericValue(from), let toNumber = numericValue(to) {
    return valueNumber >= fromNumber && valueNumber <= toNumber
  }
  guard let valueDate = DateTimeLiteral.parse(value), let fromDate = DateTimeLiteral.parse(from), let toDate = DateTimeLiteral.parse(to) else {
    return false
  }
  let precision = min(fromDate.precision, toDate.precision)
  guard valueDate.precision >= precision else { return false }
  return dateTimeCompare(valueDate, fromDate, precision: precision) != .orderedAscending
    && dateTimeCompare(valueDate, toDate, precision: precision) != .orderedDescending
}

/// Returns whether a JSON/YAML value is one of the supported empty values.
func isEmptyValue(_ value: Any) -> Bool {
  if let string = value as? String { return string.isEmpty }
  if let array = value as? [Any] { return array.isEmpty }
  if let object = value as? [String: Any] { return object.isEmpty }
  return false
}

/// Returns a JSON/YAML type name for predicate matching.
func jsonTypeName(_ value: Any) -> String {
  if value is NSNull { return "null" }
  if value is Bool { return "boolean" }
  if numericValue(value) != nil { return "number" }
  if value is String { return "string" }
  if value is [Any] { return "array" }
  if value is [String: Any] { return "object" }
  return "object"
}

/// Returns a file modification date when available.
func fileModificationDate(_ path: Path) -> Date? {
  let attributes = try? FileManager.default.attributesOfItem(atPath: path.string)
  return attributes?[.modificationDate] as? Date
}

/// Extracts ATX headings and their levels from Markdown body.
func parsedHeadings(in body: String) -> [(level: Int, text: String)] {
  body.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("#") else { return nil }
    let hashes = trimmed.prefix { $0 == "#" }
    guard (1...6).contains(hashes.count) else { return nil }
    let afterHashes = trimmed.dropFirst(hashes.count)
    guard afterHashes.first == " " else { return nil }
    return (hashes.count, String(afterHashes.dropFirst()).trimmingCharacters(in: .whitespaces))
  }
}

/// Returns whether a heading starts a non-empty section.
func sectionExists(heading: String, in body: String) -> Bool {
  let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  var inSection = false
  var sectionLevel = 0
  for line in lines {
    if let parsed = parsedHeadings(in: line).first {
      if inSection && parsed.level <= sectionLevel { return false }
      if parsed.text == heading {
        inSection = true
        sectionLevel = parsed.level
        continue
      }
    }
    if inSection && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return true
    }
  }
  return false
}

/// Returns whether raw Markdown body has any wikilink or a specific wikilink target.
func wikilinkMatches(body: String, matcher: WikilinkMatcher) -> Bool {
  guard let expression = try? NSRegularExpression(pattern: #"\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]"#) else { return false }
  let range = NSRange(body.startIndex..., in: body)
  let matches = expression.matches(in: body, range: range)
  guard let target = matcher.target else { return !matches.isEmpty }
  return matches.contains { match in
    guard let targetRange = Range(match.range(at: 1), in: body) else { return false }
    return String(body[targetRange]) == target
  }
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
