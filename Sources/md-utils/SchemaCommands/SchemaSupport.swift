//
//  SchemaSupport.swift
//  md-utils
//

import ArgumentParser
import Foundation
import JSONSchema
import MarkdownUtilities
import PathKit
import Yams
/// Stores project-level md-utils schema validation configuration.
///
/// See <doc:SchemaValidationCommands> for workflow details.
struct MdUtilsConfig {
  static let defaultSchemaDirectory = ".md-utils/schemas"

  var schemaReference: String?
  var schemaDirectory: String
  var schemaRules: [SchemaRule]
  /// Creates a configured instance.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  init(
    schemaReference: String? = "md-utils.schema.json",
    schemaDirectory: String = Self.defaultSchemaDirectory,
    schemaRules: [SchemaRule] = []
  ) {
    self.schemaReference = schemaReference
    self.schemaDirectory = schemaDirectory
    self.schemaRules = schemaRules
  }
  /// Loads the requested data from disk.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  static func load(from path: Path = SchemaPaths.configFile) throws -> MdUtilsConfig {
    guard path.exists else {
      throw ValidationError("Project config not found: \(path.string). Run md-utils schema init first.")
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path.string))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ValidationError("Project config must be a JSON object: \(path.string)")
    }

    let schemaReference = object["$schema"] as? String
    let schemaDirectory = object["schemaDirectory"] as? String ?? Self.defaultSchemaDirectory
    let rawRules = object["schemaRules"] as? [[String: Any]] ?? []
    let rules = try rawRules.map { try SchemaRule(json: $0) }
    let names = rules.map(\.name)
    if Set(names).count != names.count {
      throw ValidationError("Schema rule names must be unique")
    }

    return MdUtilsConfig(
      schemaReference: schemaReference,
      schemaDirectory: schemaDirectory,
      schemaRules: rules
    )
  }
  /// Saves the current data to disk.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  func save(to path: Path = SchemaPaths.configFile) throws {
    var object: [String: Any] = [
      "schemaDirectory": schemaDirectory,
      "schemaRules": schemaRules.map { $0.jsonObject },
    ]
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
/// Defines one named frontmatter schema rule from the project configuration.
///
/// See <doc:SchemaValidationCommands> for workflow details.
struct SchemaRule {
  var name: String
  var schema: String
  var frontmatterRequired: Bool
  var match: SchemaRuleMatch
  /// Creates a configured instance.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  init(name: String, schema: String, frontmatterRequired: Bool = true, match: SchemaRuleMatch) {
    self.name = name
    self.schema = schema
    self.frontmatterRequired = frontmatterRequired
    self.match = match
  }
  /// Creates a configured instance.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  init(json: [String: Any]) throws {
    guard let name = json["name"] as? String, !name.isEmpty else {
      throw ValidationError("Schema rules require a non-empty name")
    }
    guard let schema = json["schema"] as? String, !schema.isEmpty else {
      throw ValidationError("Schema rule \"\(name)\" requires a non-empty schema")
    }
    guard let matchObject = json["match"] as? [String: Any] else {
      throw ValidationError("Schema rule \"\(name)\" requires a match object")
    }

    self.name = name
    self.schema = schema
    self.frontmatterRequired = json["frontmatterRequired"] as? Bool ?? true
    self.match = try SchemaRuleMatch(json: matchObject, ruleName: name)
  }

  var jsonObject: [String: Any] {
    [
      "name": name,
      "schema": schema,
      "frontmatterRequired": frontmatterRequired,
      "match": match.jsonObject,
    ]
  }
}
/// Describes the path and frontmatter conditions that select files for a schema rule.
///
/// See <doc:SchemaValidationCommands> for workflow details.
struct SchemaRuleMatch {
  var paths: [String]
  var frontmatter: [String: FrontmatterMatcher]
  /// Creates a configured instance.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  init(paths: [String] = [], frontmatter: [String: FrontmatterMatcher] = [:]) {
    self.paths = paths
    self.frontmatter = frontmatter
  }
  /// Creates a configured instance.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  init(json: [String: Any], ruleName: String) throws {
    let paths = json["paths"] as? [String] ?? []
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
    self.frontmatter = frontmatter
  }

  var jsonObject: [String: Any] {
    var object: [String: Any] = [:]
    if !paths.isEmpty {
      object["paths"] = paths
    }
    if !frontmatter.isEmpty {
      object["frontmatter"] = frontmatter.mapValues { $0.jsonObject }
    }
    return object
  }
}
/// Describes a frontmatter matcher that requires an array to include a value.
///
/// See <doc:SchemaValidationCommands> for workflow details.
struct FrontmatterMatcher {
  var includes: Any
  /// Creates a configured instance.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  init(includes: Any) {
    self.includes = includes
  }
  /// Creates a configured instance.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  init(json: [String: Any], key: String, ruleName: String) throws {
    guard let includes = json["includes"] else {
      throw ValidationError("Schema rule \"\(ruleName)\" frontmatter matcher for \"\(key)\" requires includes")
    }
    self.includes = includes
  }

  var jsonObject: [String: Any] {
    ["includes": includes]
  }
}
/// Centralizes project configuration and schema file paths.
///
/// See <doc:SchemaValidationCommands> for workflow details.
enum SchemaPaths {
  static var projectDirectory: Path { Path(".md-utils") }
  static var configFile: Path { projectDirectory + "md-utils.json" }
  static let bundledConfigSchemaFileName = "md-utils.schema.json"
  /// Returns the directory that stores md-utils project configuration.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  static func schemaDirectory(for config: MdUtilsConfig) -> Path {
    Path(config.schemaDirectory)
  }
  /// Returns the schema file path for a configured schema rule.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  static func schemaFile(rule: SchemaRule, config: MdUtilsConfig) -> Path {
    let schemaPath = Path(rule.schema)
    if schemaPath.isAbsolute {
      return schemaPath
    }
    return schemaDirectory(for: config) + rule.schema
  }
}
/// Bootstraps the `.md-utils` project configuration files.
///
/// See <doc:SchemaValidationCommands> for workflow details.
enum SchemaConfigBootstrapper {
  /// Creates the project configuration directory and bundled schema file when needed.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  static func ensureProjectFiles() throws {
    try SchemaPaths.projectDirectory.mkpath()
    try Path(MdUtilsConfig.defaultSchemaDirectory).mkpath()
    try copyBundledConfigSchema()

    if !SchemaPaths.configFile.exists {
      try MdUtilsConfig().save()
    }
  }
  /// Copies the bundled md-utils configuration schema into the project directory.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  private static func copyBundledConfigSchema() throws {
    guard let resourceURL = Bundle.module.url(
      forResource: "md-utils.schema",
      withExtension: "json"
    ) else {
      throw ValidationError("Bundled md-utils config schema is missing")
    }

    let destination = SchemaPaths.projectDirectory + SchemaPaths.bundledConfigSchemaFileName
    let data = try Data(contentsOf: resourceURL)
    try data.write(to: URL(fileURLWithPath: destination.string))
  }
}
/// Captures options used to create or initialize a schema rule.
///
/// See <doc:SchemaValidationCommands> for workflow details.
struct SchemaRuleOptions {
  var name: String
  var schema: String?
  var path: String
  var tag: String?
  var frontmatterRequired: Bool
}
/// Adds and removes schema rules from the project configuration.
///
/// See <doc:SchemaValidationCommands> for workflow details.
enum SchemaRuleManager {
  /// Adds a schema validation rule to the project configuration.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  static func addRule(_ options: SchemaRuleOptions) throws -> Path {
    var config = try MdUtilsConfig.load()
    if config.schemaRules.contains(where: { $0.name == options.name }) {
      throw ValidationError("Schema rule already exists: \"\(options.name)\"")
    }

    let schemaFilename = options.schema ?? "\(options.name).schema.json"
    let schemaDirectory = SchemaPaths.schemaDirectory(for: config)
    try schemaDirectory.mkpath()
    let schemaFile = schemaDirectory + schemaFilename
    if !schemaFile.exists {
      try schemaFile.write(starterSchema(title: options.name))
    }

    var frontmatterMatchers: [String: FrontmatterMatcher] = [:]
    if let tag = options.tag {
      frontmatterMatchers["tags"] = FrontmatterMatcher(includes: tag)
    }

    let rule = SchemaRule(
      name: options.name,
      schema: schemaFilename,
      frontmatterRequired: options.frontmatterRequired,
      match: SchemaRuleMatch(paths: [options.path], frontmatter: frontmatterMatchers)
    )
    config.schemaRules.append(rule)
    try config.save()
    return schemaFile
  }
  /// Removes a schema validation rule from the project configuration.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  static func removeRule(named name: String, deleteSchema: Bool) throws -> (removed: SchemaRule, deletedSchema: Bool, schemaPath: Path) {
    var config = try MdUtilsConfig.load()
    guard let index = config.schemaRules.firstIndex(where: { $0.name == name }) else {
      throw ValidationError("Schema rule not found: \"\(name)\"")
    }

    let removed = config.schemaRules.remove(at: index)
    let schemaPath = SchemaPaths.schemaFile(rule: removed, config: config)
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
  /// See <doc:SchemaValidationCommands> for workflow details.
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
/// Finds Markdown files that can participate in schema validation.
///
/// See <doc:SchemaValidationCommands> for workflow details.
enum SchemaFileScanner {
  /// Finds Markdown files below the project root for schema validation.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
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
/// See <doc:SchemaValidationCommands> for workflow details.
struct SchemaValidationErrorDetail {
  var path: String
  var message: String
}
/// Records the validation status for one file and one schema rule.
///
/// See <doc:SchemaValidationCommands> for workflow details.
struct SchemaValidationResult {
  /// Indicates whether a file-rule validation passed, failed, or was skipped.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  enum Status {
    case ok
    case error
    case skipped
  }

  var ruleName: String
  var schemaPath: String
  var filePath: String
  var status: Status
  var errors: [SchemaValidationErrorDetail]
}
/// Aggregates schema validation results for command output and exit status.
///
/// See <doc:SchemaValidationCommands> for workflow details.
struct SchemaValidationSummary {
  var results: [SchemaValidationResult]
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
/// Runs project schema validation and returns a structured summary.
///
/// See <doc:SchemaValidationCommands> for workflow details.
enum SchemaValidatorRunner {
  /// Validates the input and returns validation results.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  static func validate(ruleName: String? = nil) throws -> SchemaValidationSummary {
    let config = try MdUtilsConfig.load()
    let rules: [SchemaRule]
    if let ruleName {
      guard let rule = config.schemaRules.first(where: { $0.name == ruleName }) else {
        throw ValidationError("Schema rule not found: \"\(ruleName)\"")
      }
      rules = [rule]
    } else {
      rules = config.schemaRules
    }

    let files = try SchemaFileScanner.markdownFiles()
    var results: [SchemaValidationResult] = []
    var loadedSchemas: [String: [String: Any]] = [:]

    for file in files {
      let relativePath = projectRelativePath(file)
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

      for rule in pathMatchedRules {
        let schemaPath = SchemaPaths.schemaFile(rule: rule, config: config)
        if let yamlError {
          results.append(errorResult(
            rule: rule,
            schemaPath: schemaPath,
            filePath: relativePath,
            path: "frontmatter",
            message: "invalid YAML: \(yamlError.localizedDescription)"
          ))
          continue
        }

        guard frontmatterPresence.hasFrontmatter else {
          if !rule.match.frontmatter.isEmpty {
            continue
          } else if rule.frontmatterRequired {
            results.append(errorResult(
              rule: rule,
              schemaPath: schemaPath,
              filePath: relativePath,
              path: "frontmatter",
              message: "required by rule \"\(rule.name)\""
            ))
          } else if rule.match.frontmatter.isEmpty {
            results.append(SchemaValidationResult(
              ruleName: rule.name,
              schemaPath: schemaPath.string,
              filePath: relativePath,
              status: .skipped,
              errors: [SchemaValidationErrorDetail(path: "frontmatter", message: "not present")]
            ))
          }
          continue
        }

        guard let parsedFrontmatter else { continue }
        guard frontmatterConditionsMatch(rule: rule, frontmatter: parsedFrontmatter) else { continue }

        let schemaKey = schemaPath.absolute().string
        let schema: [String: Any]
        if let loaded = loadedSchemas[schemaKey] {
          schema = loaded
        } else {
          schema = try loadSchema(path: schemaPath)
          loadedSchemas[schemaKey] = schema
        }

        let compatibleFrontmatter = jsonCompatibleValue(parsedFrontmatter)
        let validationResult = try JSONSchema.validate(compatibleFrontmatter, schema: schema)
        if validationResult.valid {
          results.append(SchemaValidationResult(
            ruleName: rule.name,
            schemaPath: schemaPath.string,
            filePath: relativePath,
            status: .ok,
            errors: []
          ))
        } else {
          let errors = validationResult.errors?.map { error in
            SchemaValidationErrorDetail(
              path: pointerDisplayPath(error.instanceLocation.path),
              message: error.description
            )
          } ?? [SchemaValidationErrorDetail(path: "frontmatter", message: "schema validation failed")]
          results.append(SchemaValidationResult(
            ruleName: rule.name,
            schemaPath: schemaPath.string,
            filePath: relativePath,
            status: .error,
            errors: errors
          ))
        }
      }
    }

    return SchemaValidationSummary(results: results, totalMarkdownFiles: files.count)
  }
  /// Loads the requested data from disk.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  private static func loadSchema(path: Path) throws -> [String: Any] {
    guard path.exists else {
      throw ValidationError("Schema file not found: \(path.string)")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path.string))
    guard let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ValidationError("Schema file must contain a JSON object: \(path.string)")
    }
    return schema
  }
  /// Returns whether a project-relative path matches a schema rule path condition.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  private static func rulePathConditionsMatch(rule: SchemaRule, relativePath: String) -> Bool {
    if rule.match.paths.isEmpty {
      return true
    }
    return rule.match.paths.contains { matchesGlob(relativePath, glob: $0) }
  }
  /// Returns whether parsed frontmatter satisfies a schema rule frontmatter condition.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  private static func frontmatterConditionsMatch(rule: SchemaRule, frontmatter: Any) -> Bool {
    guard !rule.match.frontmatter.isEmpty else { return true }
    guard let object = frontmatter as? [String: Any] else { return false }

    for (key, matcher) in rule.match.frontmatter {
      guard let value = object[key] as? [Any] else { return false }
      if !value.contains(where: { jsonValuesEqual($0, matcher.includes) }) {
        return false
      }
    }
    return true
  }
  /// Builds a validation result for an error that prevents schema validation.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  private static func errorResult(
    rule: SchemaRule,
    schemaPath: Path,
    filePath: String,
    path: String,
    message: String
  ) -> SchemaValidationResult {
    SchemaValidationResult(
      ruleName: rule.name,
      schemaPath: schemaPath.string,
      filePath: filePath,
      status: .error,
      errors: [SchemaValidationErrorDetail(path: path, message: message)]
    )
  }
}
/// Detects whether Markdown content contains a frontmatter block and returns its raw YAML.
///
/// See <doc:SchemaValidationCommands> for workflow details.
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
/// See <doc:SchemaValidationCommands> for workflow details.
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
/// See <doc:SchemaValidationCommands> for workflow details.
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
/// See <doc:SchemaValidationCommands> for workflow details.
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
/// See <doc:SchemaValidationCommands> for workflow details.
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
/// See <doc:SchemaValidationCommands> for workflow details.
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
/// Converts a JSON Pointer into a user-facing display path.
///
/// See <doc:SchemaValidationCommands> for workflow details.
func pointerDisplayPath(_ pointer: String) -> String {
  if pointer.isEmpty || pointer == "/" {
    return "frontmatter"
  }
  let trimmed = pointer.hasPrefix("/") ? String(pointer.dropFirst()) : pointer
  return trimmed.replacingOccurrences(of: "/", with: ".")
}
