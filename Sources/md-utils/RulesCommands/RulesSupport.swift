//
//  RulesSupport.swift
//  md-utils
//

import ArgumentParser
import Foundation
import JMESPath
import JSONSchema
import MarkdownUtilities
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
  private var normalizedRules: [MarkdownRuleDefinition]?
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
    self.normalizedRules = nil
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

    let normalized = try MarkdownRuleConfigurationDecoder.decode(
      String(decoding: data, as: UTF8.self)
    )
    let rules = try normalized.rules.map { definition in
      let object = try MarkdownRuleConfigurationEncoder.ruleObject(definition)
      return try Rule(json: object, configVersion: MarkdownRuleConfigurationSchemaVersion.current)
    }

    var config = MdUtilsConfig(
      configVersion: normalized.configVersion,
      schemaReference: normalized.schemaReference,
      schemaDirectory: normalized.schemaDirectory,
      schemaRules: rules
    )
    config.normalizedRules = normalized.rules
    return config
  }
  /// Saves the current data to disk.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  func save(to path: Path = RulesPaths.configFile) throws {
    let definitions = try schemaRules.map { try $0.normalizedDefinition() }
    let configuration = MarkdownRuleConfiguration(
      configVersion: configVersion,
      schemaReference: schemaReference,
      schemaDirectory: schemaDirectory,
      rules: definitions
    )
    try path.write(try MarkdownRuleConfigurationEncoder.encode(configuration))
  }
}

extension MdUtilsConfig {
  /// Compiles the normalized project rules for the native CLI runtime.
  func compiledRuleRegistry(root: Path) throws -> MarkdownRuleRegistry {
    let absoluteRoot = root.absolute().normalize()
    let schemaDirectoryPath = Path(schemaDirectory).isAbsolute
      ? Path(schemaDirectory)
      : absoluteRoot + Path(schemaDirectory)
    let source = URL(
      fileURLWithPath: (schemaDirectoryPath + "__md-utils-rule-source.json").string
    ).absoluteString
    let definitions = try (normalizedRules ?? schemaRules.map { try $0.normalizedDefinition() })
      .map { definition in
        var definition = definition
        definition.source = source
        return definition
      }
    let typesDirectory = absoluteRoot + Path(MarkdownTypeFileRegistryLoader.relativeTypesDirectory)
    let typeRegistry = typesDirectory.exists
      ? try MarkdownTypeFileRegistryLoader.load(projectRoot: absoluteRoot)
      : try MarkdownTypeRegistry(definitions: [])
    let queryProvider = JMESPathRuleCapabilityProvider()
    return try MarkdownRuleCompiler(
      capabilities: [.modificationDate, .frontmatterJMESPath],
      typeRegistry: typeRegistry,
      schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: absoluteRoot),
      queryProvider: queryProvider
    ).compile(definitions)
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

extension Rule {
  /// Normalizes the project configuration DTO into the shared Core rule model.
  func normalizedDefinition(source: String? = nil) throws -> MarkdownRuleDefinition {
    var requirements: [MarkdownRuleRequirement] = []
    for (key, matcher) in match.frontmatter.sorted(by: { $0.key < $1.key }) {
      for (operatorName, operand) in matcher.operators.sorted(by: { $0.key < $1.key }) {
        requirements.append(MarkdownRuleRequirement(
          id: "\(name).match.frontmatter.\(key).\(operatorName)",
          predicate: .frontmatterField(
            key: key,
            operation: try normalizedFrontmatterOperation(operatorName, operand: operand)
          )
        ))
      }
    }
    if let expression = match.frontmatterQuery.jmespath {
      requirements.append(MarkdownRuleRequirement(
        id: "\(name).match.frontmatterQuery.jmespath",
        predicate: .frontmatterJMESPath(expression)
      ))
    }
    requirements.append(contentsOf: normalizedDocumentRequirements())
    requirements.append(contentsOf: try normalizedFileRequirements())

    let normalizedChecks = checks.enumerated().map { index, check in
      let id = "\(name).check[\(index)]"
      switch check {
      case .frontmatterSchema(let schema, let required):
        return MarkdownRuleCheck(
          id: id,
          predicate: .frontmatterSchema(
            source: .reference(schema),
            presence: required ? .required : .optional
          )
        )
      case .requiredHeading(let heading):
        return MarkdownRuleCheck(
          id: id,
          predicate: .markdown(.heading(MarkdownHeadingPredicate(text: heading)))
        )
      case .maxBodyLines(let maximum):
        return MarkdownRuleCheck(id: id, predicate: .markdown(.maxBodyLines(maximum)))
      case .maxBodyWords(let maximum):
        return MarkdownRuleCheck(id: id, predicate: .markdown(.maxBodyWords(maximum)))
      }
    }
    return MarkdownRuleDefinition(
      name: name,
      applicability: MarkdownRuleApplicability(
        paths: match.paths,
        excludePaths: match.excludePaths,
        requirements: requirements
      ),
      checks: normalizedChecks,
      source: source
    )
  }

  private func normalizedDocumentRequirements() -> [MarkdownRuleRequirement] {
    var requirements: [MarkdownRuleRequirement] = []
    func append(_ key: String, _ predicate: MarkdownRulePredicate) {
      requirements.append(MarkdownRuleRequirement(
        id: "\(name).match.document.\(key)",
        predicate: predicate
      ))
    }
    if let value = match.document.hasHeading {
      append("hasHeading", .heading(MarkdownHeadingPredicate(text: value)))
    }
    if let value = match.document.headingRegex { append("headingRegex", .headingRegularExpression(value)) }
    if let value = match.document.hasHeadingAtLevel {
      append("hasHeadingAtLevel", .heading(MarkdownHeadingPredicate(text: value.heading, level: value.level)))
    }
    if let value = match.document.hasSection { append("hasSection", .section(value)) }
    if let value = match.document.bodyContains { append("bodyContains", .bodyContains(value)) }
    if let value = match.document.bodyRegex { append("bodyRegex", .bodyRegularExpression(value)) }
    if let value = match.document.hasWikilink { append("hasWikilink", .wikilink(target: value.target)) }
    if let value = match.document.lineCount {
      append("lineCount", .bodyLineCount(MarkdownRuleIntegerRange(minimum: value.min, maximum: value.max)))
    }
    if let value = match.document.wordCount {
      append("wordCount", .bodyWordCount(MarkdownRuleIntegerRange(minimum: value.min, maximum: value.max)))
    }
    return requirements
  }

  private func normalizedFileRequirements() throws -> [MarkdownRuleRequirement] {
    var requirements: [MarkdownRuleRequirement] = []
    func append(_ key: String, _ predicate: MarkdownRulePredicate) {
      requirements.append(MarkdownRuleRequirement(
        id: "\(name).match.file.\(key)",
        predicate: predicate
      ))
    }
    if let value = match.file.pathRegex { append("pathRegex", .pathRegularExpression(value)) }
    if let value = match.file.filenameEquals { append("filenameEquals", .filenameEquals(value)) }
    if match.file.extensionIn.isEmpty == false { append("extensionIn", .extensionIn(match.file.extensionIn)) }
    if let value = match.file.modifiedAfter {
      guard let literal = MarkdownRuleDateTimeLiteral(value.rawValue) else {
        throw ValidationError("Invalid modifiedAfter date/time \"\(value.rawValue)\"")
      }
      append("modifiedAfter", .modifiedAfter(literal))
    }
    if let value = match.file.modifiedBefore {
      guard let literal = MarkdownRuleDateTimeLiteral(value.rawValue) else {
        throw ValidationError("Invalid modifiedBefore date/time \"\(value.rawValue)\"")
      }
      append("modifiedBefore", .modifiedBefore(literal))
    }
    return requirements
  }

  private func normalizedFrontmatterOperation(
    _ name: String,
    operand: Any
  ) throws -> MarkdownFrontmatterRuleOperator {
    switch name {
    case "equals": return .equals(try JSONValue(any: jsonCompatibleValue(operand)))
    case "doesntEqual": return .doesNotEqual(try JSONValue(any: jsonCompatibleValue(operand)))
    case "includes": return .includes(try JSONValue(any: jsonCompatibleValue(operand)))
    case "notIncludes": return .doesNotInclude(try JSONValue(any: jsonCompatibleValue(operand)))
    case "hasKey": return .hasKey
    case "doesntHaveKey": return .doesNotHaveKey
    case "regex": return .regularExpression(try normalizedString(operand, name: name))
    case "startsWith": return .startsWith(try normalizedString(operand, name: name))
    case "endsWith": return .endsWith(try normalizedString(operand, name: name))
    case "contains": return .contains(try normalizedString(operand, name: name))
    case "empty": return .empty
    case "emptyString": return .emptyString
    case "emptyArray": return .emptyArray
    case "emptyObject": return .emptyObject
    case "notEmpty": return .notEmpty
    case "in": return .isIn(try normalizedArray(operand, name: name))
    case "notIn": return .isNotIn(try normalizedArray(operand, name: name))
    case "greaterThan": return .greaterThan(try normalizedNumber(operand, name: name))
    case "greaterThanOrEqual": return .greaterThanOrEqual(try normalizedNumber(operand, name: name))
    case "lessThan": return .lessThan(try normalizedNumber(operand, name: name))
    case "lessThanOrEqual": return .lessThanOrEqual(try normalizedNumber(operand, name: name))
    case "after": return .after(try normalizedDate(operand, name: name))
    case "onOrAfter": return .onOrAfter(try normalizedDate(operand, name: name))
    case "before": return .before(try normalizedDate(operand, name: name))
    case "onOrBefore": return .onOrBefore(try normalizedDate(operand, name: name))
    case "between":
      guard let object = operand as? [String: Any], let from = object["from"], let to = object["to"] else {
        throw ValidationError("between requires from and to")
      }
      if let fromNumber = numericValue(from), let toNumber = numericValue(to) {
        return .between(.number(from: fromNumber, through: toNumber))
      }
      return .between(.dateTime(
        from: try normalizedDate(from, name: "between.from"),
        through: try normalizedDate(to, name: "between.to")
      ))
    case "typeIs":
      let value = try normalizedString(operand, name: name)
      guard let type = MarkdownRuleJSONType(rawValue: value) else {
        throw ValidationError("Unsupported JSON type \"\(value)\"")
      }
      return .typeIs(type)
    default: throw ValidationError("Unsupported frontmatter operator \"\(name)\"")
    }
  }

  private func normalizedString(_ value: Any, name: String) throws -> String {
    guard let value = value as? String else { throw ValidationError("\(name) requires a string") }
    return value
  }

  private func normalizedArray(_ value: Any, name: String) throws -> [JSONValue] {
    guard let values = value as? [Any] else { throw ValidationError("\(name) requires an array") }
    return try values.map { try JSONValue(any: jsonCompatibleValue($0)) }
  }

  private func normalizedNumber(_ value: Any, name: String) throws -> Double {
    guard let value = numericValue(value) else { throw ValidationError("\(name) requires a number") }
    return value
  }

  private func normalizedDate(_ value: Any, name: String) throws -> MarkdownRuleDateTimeLiteral {
    guard let value = value as? String, let literal = MarkdownRuleDateTimeLiteral(value) else {
      throw ValidationError("\(name) requires a date or date-time")
    }
    return literal
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

/// Shared generated-help content for rules commands that can opt into host files.
enum RulesNonMarkdownHelp {
  static func appending(to discussion: String) -> String {
    discussion + "\n\n" + section
  }

  private static let section = """
    NON-MARKDOWN FILES
      Rules scan only .md and .markdown files by default. Use --include-non-md
      to include other files selected by configured rule paths. An explicit file
      passed to rules matching is selected automatically, except .txt, which
      requires --include-non-md.

      Mapped extensions use shipped wrapped-frontmatter syntax. Plain .txt uses
      ordinary leading --- frontmatter. Unmapped files support file and raw-text
      predicates, but frontmatter evaluation reports that no syntax mapping exists.
      Markdown headings, sections, and wikilinks are unsupported in non-Markdown
      files.
    """
}
/// Finds files that can participate in rules validation.
///
/// See <doc:RulesValidationCommands> for workflow details.
enum RuleFileScanner {
  /// Finds eligible files below the project root for rules validation.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  static func files(root: Path = .current, includeNonMarkdown: Bool = false) throws -> [Path] {
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
      if includeNonMarkdown == false {
        guard let ext = path.extension?.lowercased(), ["md", "markdown"].contains(ext) else { continue }
      }
      files.append(path)
    }
    files.sort { $0.string < $1.string }
    return files
  }
}
/// Describes one validation issue for a file.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleValidationErrorDetail: Sendable {
  var path: String
  var message: String
}
/// Records the validation status for one file and one rule.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleValidationResult: Sendable {
  /// Indicates whether a file-rule validation passed, failed, or was skipped.
  ///
  /// See <doc:RulesValidationCommands> for workflow details.
  enum Status: Sendable {
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

private struct RuleValidationJob: Sendable {
  var file: String
  var rules: [CompiledMarkdownRule]
  var analysisRequirements: MarkdownRecordAnalysisRequirements
}

private func boundedConcurrentMap<Input: Sendable, Output: Sendable>(
  _ inputs: [Input],
  maximumConcurrency: Int = min(ProcessInfo.processInfo.activeProcessorCount, 8),
  transform: @escaping @Sendable (Input) async throws -> Output
) async throws -> [Output] {
  guard inputs.isEmpty == false else { return [] }
  let limit = max(1, min(maximumConcurrency, inputs.count))
  return try await withThrowingTaskGroup(
    of: (Int, Output).self,
    returning: [Output].self
  ) { group in
    var nextIndex = 0
    for _ in 0..<limit {
      let index = nextIndex
      let input = inputs[index]
      group.addTask { (index, try await transform(input)) }
      nextIndex += 1
    }

    var completed: [(Int, Output)] = []
    completed.reserveCapacity(inputs.count)
    while let result = try await group.next() {
      completed.append(result)
      if nextIndex < inputs.count {
        let index = nextIndex
        let input = inputs[index]
        group.addTask { (index, try await transform(input)) }
        nextIndex += 1
      }
    }
    return completed.sorted { $0.0 < $1.0 }.map(\.1)
  }
}
/// Records whether one configured rule matches a specific file.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleMatchEvaluation {
  var rule: Rule
  var matched: Bool
  var reasons: [String]
  var diagnostics: [String] = []
}
/// Aggregates rule validation results for command output and exit status.
///
/// See <doc:RulesValidationCommands> for workflow details.
struct RuleValidationSummary {
  var results: [RuleValidationResult]
  var totalFiles: Int

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
    includeNonMarkdown: Bool = false,
    root: Path = .current,
    configPath: Path = RulesPaths.configFile
  ) async throws -> RuleValidationSummary {
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

    let registry = try config.compiledRuleRegistry(root: root)
    let checker = MarkdownRuleChecker(registry: registry)
    let compiledRules: [(rule: Rule, compiled: CompiledMarkdownRule)] = rules.compactMap { rule in
      guard let compiled = registry.rule(named: rule.name) else { return nil }
      return (rule, compiled)
    }
    let files = try RuleFileScanner.files(root: root, includeNonMarkdown: includeNonMarkdown)
    let rootString = root.absolute().normalize().string
    let schemaPaths = Dictionary(uniqueKeysWithValues: rules.map { rule in
      (
        rule.name,
        rule.schema.isEmpty
          ? ""
          : RulesPaths.schemaFile(rule: rule, config: config, root: root).string
      )
    })
    var jobs: [RuleValidationJob] = []
    jobs.reserveCapacity(files.count)

    for file in files {
      let logicalPath = try MarkdownRecordPath(relativePath(from: root, to: file))
      let candidates = compiledRules.filter {
        checker.isPathCandidate(logicalPath, for: $0.compiled)
      }
      guard candidates.isEmpty == false else { continue }
      let analysisRequirements = candidates.reduce(
        into: MarkdownRecordAnalysisRequirements(rawValue: 0)
      ) { requirements, candidate in
        requirements.formUnion(checker.analysisRequirements(for: candidate.compiled))
      }
      jobs.append(RuleValidationJob(
        file: file.string,
        rules: candidates.map(\.compiled),
        analysisRequirements: analysisRequirements
      ))
    }

    let groupedResults = try await boundedConcurrentMap(jobs) { job in
      let file = Path(job.file)
      let projectRoot = Path(rootString)
      let record = try MarkdownRecordFileAdapter.read(file, projectRoot: projectRoot)
      let analyzed = await MarkdownRecordAnalyzer.analyze(
        record,
        requirements: job.analysisRequirements,
        contentKind: recordContentKind(for: file)
      )
      var results: [RuleValidationResult] = []
      for compiled in job.rules {
        let assessment = try checker.assess(analyzed, against: compiled)
        guard assessment.status != .notApplicable else { continue }
        let ruleName = compiled.definition.name
        let errors = (assessment.applicabilityDiagnostics + assessment.diagnostics).map { diagnostic in
          RuleValidationErrorDetail(
            path: diagnostic.location,
            message: {
              switch diagnostic.code {
              case "record.frontmatter.invalid-yaml":
                return diagnostic.message.replacingOccurrences(of: "Invalid YAML:", with: "invalid YAML:")
              case "record.frontmatter.invalid-toml":
                return diagnostic.message.replacingOccurrences(of: "Invalid TOML:", with: "invalid TOML:")
              default:
                return diagnostic.message
              }
            }()
          )
        }
        let status: RuleValidationResult.Status
        switch assessment.status {
        case .notApplicable: continue
        case .skipped: status = .skipped
        case .passed: status = .ok
        case .failed: status = .error
        }
        results.append(RuleValidationResult(
          ruleName: ruleName,
          schemaPath: schemaPaths[ruleName] ?? "",
          filePath: record.context.path?.rawValue ?? relativePath(from: projectRoot, to: file),
          status: status,
          errors: assessment.status == .skipped
            ? [RuleValidationErrorDetail(path: "frontmatter", message: "not present")]
            : errors
        ))
      }
      return results
    }
    return RuleValidationSummary(
      results: groupedResults.flatMap { $0 },
      totalFiles: files.count
    )
  }

  static func filesMatching(
    ruleName: String,
    includeNonMarkdown: Bool = false,
    root: Path = .current,
    configPath: Path = RulesPaths.configFile
  ) async throws -> [Path] {
    let config = try MdUtilsConfig.load(from: configPath)
    guard config.schemaRules.contains(where: { $0.name == ruleName }) else {
      throw ValidationError("Rule not found: \"\(ruleName)\"")
    }

    let registry = try config.compiledRuleRegistry(root: root)
    guard let compiled = registry.rule(named: ruleName) else { return [] }
    let checker = MarkdownRuleChecker(registry: registry)
    let files = try RuleFileScanner.files(root: root, includeNonMarkdown: includeNonMarkdown)
    let rootString = root.absolute().normalize().string
    let candidates = try files.compactMap { file -> String? in
      let logicalPath = try MarkdownRecordPath(relativePath(from: root, to: file))
      return checker.isPathCandidate(logicalPath, for: compiled) ? file.string : nil
    }
    let matches = try await boundedConcurrentMap(candidates) { fileString -> String? in
      let file = Path(fileString)
      let record = try MarkdownRecordFileAdapter.read(file, projectRoot: Path(rootString))
      let analyzed = await MarkdownRecordAnalyzer.analyze(
        record,
        requirements: checker.analysisRequirements(for: compiled),
        contentKind: recordContentKind(for: file)
      )
      let assessment = try checker.assess(analyzed, against: compiled)
      if let diagnostic = assessment.applicabilityDiagnostics.first {
        throw ValidationError(diagnostic.message)
      }
      return assessment.status != .notApplicable ? fileString : nil
    }
    return matches.compactMap { path in
      path.map { Path($0) }
    }
  }

  static func rulesMatching(
    fileName: String,
    includeNonMarkdown: Bool = false,
    root: Path = .current,
    configPath: Path = RulesPaths.configFile
  ) async throws -> [RuleMatchEvaluation] {
    let config = try MdUtilsConfig.load(from: configPath)
    let file = Path(fileName)
    guard file.exists else {
      throw ValidationError("File not found: \(fileName)")
    }
    let fileExtension = file.extension?.lowercased() ?? ""
    if fileExtension == "txt" && includeNonMarkdown == false {
      throw ValidationError("Plain .txt files require --include-non-md.")
    }

    let registry = try config.compiledRuleRegistry(root: root)
    let checker = MarkdownRuleChecker(registry: registry)
    let record = try MarkdownRecordFileAdapter.read(file, projectRoot: root)
    let analysisRequirements = config.schemaRules.reduce(
      into: MarkdownRecordAnalysisRequirements(rawValue: 0)
    ) { requirements, rule in
      guard let compiled = registry.rule(named: rule.name) else { return }
      requirements.formUnion(checker.analysisRequirements(for: compiled))
    }
    let analyzed = await MarkdownRecordAnalyzer.analyze(
      record,
      requirements: analysisRequirements,
      contentKind: recordContentKind(for: file)
    )
    return try config.schemaRules.map { rule in
      guard let compiled = registry.rule(named: rule.name) else {
        return RuleMatchEvaluation(rule: rule, matched: false, reasons: ["compiled rule is unavailable"])
      }
      let assessment = try checker.assess(analyzed, against: compiled)
      let pathCandidate = checker.isPathCandidate(record.context.path, for: compiled)
      return RuleMatchEvaluation(
        rule: rule,
        matched: assessment.status != .notApplicable && assessment.applicabilityDiagnostics.isEmpty,
        reasons: assessment.evidence.map(\.message)
          + assessment.applicabilityDiagnostics.map(\.message),
        diagnostics: pathCandidate ? assessment.applicabilityDiagnostics.map(\.message) : []
      )
    }
  }

  private static func recordContentKind(for file: Path) -> MarkdownRecordContentKind {
    MarkdownRecordContentKind.rulesKind(
      forFileName: file.lastComponent,
      fileExtension: file.extension
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


/// Returns a numeric value for JSON/YAML scalar comparisons.
func numericValue(_ value: Any) -> Double? {
  if let int = value as? Int { return Double(int) }
  if let double = value as? Double { return double }
  if let float = value as? Float { return Double(float) }
  if let number = value as? NSNumber { return number.doubleValue }
  return nil
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
