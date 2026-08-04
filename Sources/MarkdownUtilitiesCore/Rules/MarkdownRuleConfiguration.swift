import Foundation

/// Versions of the md-utils project configuration understood by the rule normalizer.
/// Serialized rule configuration versions supported by the normalized codec.
///
/// See <doc:RuleConfigurationVersions>.
public enum MarkdownRuleConfigurationSchemaVersion {
  public static let legacy = "0.1.0"
  public static let current = "0.2.0"
  public static let supported = [legacy, current]
}

/// One versioned project configuration normalized into reusable rule definitions.
public struct MarkdownRuleConfiguration: Equatable, Sendable {
  public var configVersion: String
  public var schemaReference: String?
  public var schemaDirectory: String
  public var rules: [MarkdownRuleDefinition]

  public init(
    configVersion: String = MarkdownRuleConfigurationSchemaVersion.current,
    schemaReference: String? = nil,
    schemaDirectory: String = ".md-utils/schemas/",
    rules: [MarkdownRuleDefinition] = []
  ) {
    self.configVersion = configVersion
    self.schemaReference = schemaReference
    self.schemaDirectory = schemaDirectory
    self.rules = rules
  }
}

/// Decodes legacy and current JSON configuration into one rule model.
/// Decodes supported configuration versions into normalized rule definitions.
///
/// See <doc:RuleConfigurationVersions>.
public enum MarkdownRuleConfigurationDecoder {
  public static func decode(_ content: String, source: String? = nil) throws -> MarkdownRuleConfiguration {
    guard let data = content.data(using: .utf8) else {
      throw MarkdownRuleConfigurationError.invalidSerialization("Configuration is not UTF-8")
    }
    let dynamic: Any
    do {
      dynamic = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw MarkdownRuleConfigurationError.invalidSerialization(error.localizedDescription)
    }
    guard let object = dynamic as? [String: Any] else {
      throw MarkdownRuleConfigurationError.notAnObject
    }
    return try decode(object, source: source)
  }

  private static func decode(
    _ object: [String: Any],
    source: String?
  ) throws -> MarkdownRuleConfiguration {
    let version: String
    if let rawVersion = object["configVersion"] {
      guard let value = rawVersion as? String, value.isEmpty == false else {
        throw MarkdownRuleConfigurationError.invalidField("configVersion must be a nonempty string")
      }
      version = value
    } else {
      version = MarkdownRuleConfigurationSchemaVersion.legacy
    }
    guard MarkdownRuleConfigurationSchemaVersion.supported.contains(version) else {
      throw MarkdownRuleConfigurationError.unsupportedVersion(version)
    }

    let allowed = version == MarkdownRuleConfigurationSchemaVersion.legacy
      ? Set(["$schema", "configVersion", "schemaDirectory", "schemaRules"])
      : Set(["$schema", "configVersion", "schemaDirectory", "rules"])
    try validateKeys(object, allowed: allowed, context: "configuration")
    let schemaDirectory = object["schemaDirectory"] as? String ?? ".md-utils/schemas/"
    let rawRules: [[String: Any]]
    if version == MarkdownRuleConfigurationSchemaVersion.legacy {
      rawRules = object["schemaRules"] as? [[String: Any]] ?? []
    } else {
      rawRules = object["rules"] as? [[String: Any]] ?? []
    }
    let rules = try rawRules.enumerated().map { index, value in
      try parseRule(value, version: version, index: index, source: source)
    }
    let names = rules.map(\.name)
    guard Set(names).count == names.count else {
      throw MarkdownRuleConfigurationError.invalidField("Rule names must be unique")
    }
    return MarkdownRuleConfiguration(
      configVersion: version,
      schemaReference: object["$schema"] as? String,
      schemaDirectory: schemaDirectory,
      rules: rules
    )
  }

  private static func parseRule(
    _ object: [String: Any],
    version: String,
    index: Int,
    source: String?
  ) throws -> MarkdownRuleDefinition {
    let legacy = version == MarkdownRuleConfigurationSchemaVersion.legacy
    let allowed = legacy
      ? Set(["name", "schema", "frontmatterRequired", "match"])
      : Set(["name", "match", "checks"])
    try validateKeys(object, allowed: allowed, context: "rules[\(index)]")
    let name = try requiredString(object, key: "name", context: "rules[\(index)]")
    guard let match = object["match"] as? [String: Any] else {
      throw MarkdownRuleConfigurationError.invalidField("Rule \"\(name)\" requires a match object")
    }
    let applicability = try parseApplicability(match, ruleName: name)
    let checks: [MarkdownRuleCheck]
    if legacy {
      let schema = try requiredString(object, key: "schema", context: "Rule \"\(name)\"")
      let required = object["frontmatterRequired"] as? Bool ?? true
      checks = [MarkdownRuleCheck(
        id: "\(name).check[0]",
        predicate: .frontmatterSchema(
          source: .reference(schema),
          presence: required ? .required : .optional
        )
      )]
    } else {
      guard let rawChecks = object["checks"] as? [[String: Any]], rawChecks.isEmpty == false else {
        throw MarkdownRuleConfigurationError.invalidField("Rule \"\(name)\" requires at least one check")
      }
      checks = try rawChecks.enumerated().map { checkIndex, check in
        try parseCheck(check, ruleName: name, index: checkIndex)
      }
    }
    return MarkdownRuleDefinition(
      name: name,
      applicability: applicability,
      checks: checks,
      source: source
    )
  }

  private static func parseApplicability(
    _ object: [String: Any],
    ruleName: String
  ) throws -> MarkdownRuleApplicability {
    try validateKeys(
      object,
      allowed: ["paths", "excludePaths", "file", "frontmatter", "frontmatterQuery", "document"],
      context: "Rule \"\(ruleName)\" match"
    )
    let paths = try stringArray(object["paths"], context: "Rule \"\(ruleName)\" match.paths")
    let excludePaths = try stringArray(
      object["excludePaths"],
      context: "Rule \"\(ruleName)\" match.excludePaths"
    )
    var requirements: [MarkdownRuleRequirement] = []

    if let file = object["file"] as? [String: Any] {
      try validateKeys(
        file,
        allowed: ["pathRegex", "filenameEquals", "extensionIn", "modifiedAfter", "modifiedBefore"],
        context: "Rule \"\(ruleName)\" match.file"
      )
      if let value = file["pathRegex"] {
        requirements.append(.init(
          id: "\(ruleName).match.file.pathRegex",
          predicate: .pathRegularExpression(try nonemptyString(value, context: "file.pathRegex"))
        ))
      }
      if let value = file["filenameEquals"] {
        requirements.append(.init(
          id: "\(ruleName).match.file.filenameEquals",
          predicate: .filenameEquals(try nonemptyString(value, context: "file.filenameEquals"))
        ))
      }
      if let value = file["extensionIn"] {
        requirements.append(.init(
          id: "\(ruleName).match.file.extensionIn",
          predicate: .extensionIn(try stringArray(value, context: "file.extensionIn").map {
            $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
          })
        ))
      }
      if let value = file["modifiedAfter"] {
        requirements.append(.init(
          id: "\(ruleName).match.file.modifiedAfter",
          predicate: .modifiedAfter(try dateTime(value, context: "file.modifiedAfter"))
        ))
      }
      if let value = file["modifiedBefore"] {
        requirements.append(.init(
          id: "\(ruleName).match.file.modifiedBefore",
          predicate: .modifiedBefore(try dateTime(value, context: "file.modifiedBefore"))
        ))
      }
    } else if object["file"] != nil {
      throw MarkdownRuleConfigurationError.invalidField("Rule \"\(ruleName)\" match.file must be an object")
    }

    if let frontmatter = object["frontmatter"] as? [String: Any] {
      for key in frontmatter.keys.sorted() {
        guard let operators = frontmatter[key] as? [String: Any] else {
          throw MarkdownRuleConfigurationError.invalidField("Frontmatter matcher \"\(key)\" must be an object")
        }
        for operatorName in operators.keys.sorted() {
          guard let operand = operators[operatorName] else { continue }
          requirements.append(MarkdownRuleRequirement(
            id: "\(ruleName).match.frontmatter.\(key).\(operatorName)",
            predicate: .frontmatterField(
              key: key,
              operation: try frontmatterOperation(operatorName, operand: operand, key: key)
            )
          ))
        }
      }
    } else if object["frontmatter"] != nil {
      throw MarkdownRuleConfigurationError.invalidField("Rule \"\(ruleName)\" match.frontmatter must be an object")
    }

    if let query = object["frontmatterQuery"] as? [String: Any] {
      try validateKeys(query, allowed: ["jmespath"], context: "frontmatterQuery")
      if let value = query["jmespath"] {
        requirements.append(.init(
          id: "\(ruleName).match.frontmatterQuery.jmespath",
          predicate: .frontmatterJMESPath(try nonemptyString(value, context: "frontmatterQuery.jmespath"))
        ))
      }
    } else if object["frontmatterQuery"] != nil {
      throw MarkdownRuleConfigurationError.invalidField("Rule \"\(ruleName)\" frontmatterQuery must be an object")
    }

    if let document = object["document"] as? [String: Any] {
      try validateKeys(
        document,
        allowed: [
          "hasHeading", "headingRegex", "hasHeadingAtLevel", "hasSection", "bodyContains",
          "bodyRegex", "hasWikilink", "lineCount", "wordCount",
        ],
        context: "Rule \"\(ruleName)\" match.document"
      )
      for key in document.keys.sorted() {
        guard let value = document[key] else { continue }
        requirements.append(MarkdownRuleRequirement(
          id: "\(ruleName).match.document.\(key)",
          predicate: try documentPredicate(key, value: value)
        ))
      }
    } else if object["document"] != nil {
      throw MarkdownRuleConfigurationError.invalidField("Rule \"\(ruleName)\" match.document must be an object")
    }

    if paths.isEmpty && requirements.isEmpty {
      throw MarkdownRuleConfigurationError.invalidField("Rule \"\(ruleName)\" must define at least one match condition")
    }
    return MarkdownRuleApplicability(
      paths: paths,
      excludePaths: excludePaths,
      requirements: requirements
    )
  }

  private static func parseCheck(
    _ object: [String: Any],
    ruleName: String,
    index: Int
  ) throws -> MarkdownRuleCheck {
    let context = "Rule \"\(ruleName)\" check[\(index)]"
    let type = try requiredString(object, key: "type", context: context)
    let id = "\(ruleName).check[\(index)]"
    switch type {
    case "frontmatterSchema":
      try validateKeys(object, allowed: ["type", "schema", "frontmatterRequired"], context: context)
      let schema = try requiredString(object, key: "schema", context: context)
      let required = object["frontmatterRequired"] as? Bool ?? true
      return MarkdownRuleCheck(
        id: id,
        predicate: .frontmatterSchema(
          source: .reference(schema),
          presence: required ? .required : .optional
        )
      )
    case "requiredHeading":
      try validateKeys(object, allowed: ["type", "heading"], context: context)
      return MarkdownRuleCheck(
        id: id,
        predicate: .markdown(.heading(MarkdownHeadingPredicate(
          text: try requiredString(object, key: "heading", context: context)
        )))
      )
    case "maxBodyLines":
      try validateKeys(object, allowed: ["type", "max"], context: context)
      return MarkdownRuleCheck(id: id, predicate: .markdown(.maxBodyLines(try nonnegativeInteger(
        object["max"],
        context: "\(context).max"
      ))))
    case "maxBodyWords":
      try validateKeys(object, allowed: ["type", "max"], context: context)
      return MarkdownRuleCheck(id: id, predicate: .markdown(.maxBodyWords(try nonnegativeInteger(
        object["max"],
        context: "\(context).max"
      ))))
    default:
      throw MarkdownRuleConfigurationError.unsupportedFeature("Unsupported check type \"\(type)\"")
    }
  }

  private static func frontmatterOperation(
    _ name: String,
    operand: Any,
    key: String
  ) throws -> MarkdownFrontmatterRuleOperator {
    let context = "frontmatter.\(key).\(name)"
    switch name {
    case "equals": return .equals(try JSONValue(any: operand))
    case "doesntEqual": return .doesNotEqual(try JSONValue(any: operand))
    case "includes": return .includes(try JSONValue(any: operand))
    case "notIncludes": return .doesNotInclude(try JSONValue(any: operand))
    case "hasKey": try trueOperand(operand, context: context); return .hasKey
    case "doesntHaveKey": try trueOperand(operand, context: context); return .doesNotHaveKey
    case "regex": return .regularExpression(try nonemptyString(operand, context: context))
    case "startsWith": return .startsWith(try nonemptyString(operand, context: context))
    case "endsWith": return .endsWith(try nonemptyString(operand, context: context))
    case "contains": return .contains(try nonemptyString(operand, context: context))
    case "empty": try trueOperand(operand, context: context); return .empty
    case "emptyString": try trueOperand(operand, context: context); return .emptyString
    case "emptyArray": try trueOperand(operand, context: context); return .emptyArray
    case "emptyObject": try trueOperand(operand, context: context); return .emptyObject
    case "notEmpty": try trueOperand(operand, context: context); return .notEmpty
    case "in": return .isIn(try jsonArray(operand, context: context))
    case "notIn": return .isNotIn(try jsonArray(operand, context: context))
    case "greaterThan": return .greaterThan(try number(operand, context: context))
    case "greaterThanOrEqual": return .greaterThanOrEqual(try number(operand, context: context))
    case "lessThan": return .lessThan(try number(operand, context: context))
    case "lessThanOrEqual": return .lessThanOrEqual(try number(operand, context: context))
    case "after": return .after(try dateTime(operand, context: context))
    case "onOrAfter": return .onOrAfter(try dateTime(operand, context: context))
    case "before": return .before(try dateTime(operand, context: context))
    case "onOrBefore": return .onOrBefore(try dateTime(operand, context: context))
    case "between": return .between(try between(operand, context: context))
    case "typeIs":
      let value = try nonemptyString(operand, context: context)
      guard let type = MarkdownRuleJSONType(rawValue: value) else {
        throw MarkdownRuleConfigurationError.invalidField("\(context) has unsupported JSON type \"\(value)\"")
      }
      return .typeIs(type)
    default:
      throw MarkdownRuleConfigurationError.unsupportedFeature("Unsupported frontmatter operator \"\(name)\"")
    }
  }

  private static func documentPredicate(_ name: String, value: Any) throws -> MarkdownRulePredicate {
    switch name {
    case "hasHeading": return .heading(MarkdownHeadingPredicate(text: try nonemptyString(value, context: name)))
    case "headingRegex": return .headingRegularExpression(try nonemptyString(value, context: name))
    case "hasHeadingAtLevel":
      guard let object = value as? [String: Any] else {
        throw MarkdownRuleConfigurationError.invalidField("hasHeadingAtLevel must be an object")
      }
      try validateKeys(object, allowed: ["heading", "level"], context: name)
      let heading = try requiredString(object, key: "heading", context: name)
      let level = try nonnegativeInteger(object["level"], context: "hasHeadingAtLevel.level")
      guard (1...6).contains(level) else {
        throw MarkdownRuleConfigurationError.invalidField("hasHeadingAtLevel.level must be 1...6")
      }
      return .heading(MarkdownHeadingPredicate(text: heading, level: level))
    case "hasSection": return .section(try nonemptyString(value, context: name))
    case "bodyContains": return .bodyContains(try nonemptyString(value, context: name))
    case "bodyRegex": return .bodyRegularExpression(try nonemptyString(value, context: name))
    case "hasWikilink":
      if let bool = value as? Bool, bool { return .wikilink(target: nil) }
      return .wikilink(target: try nonemptyString(value, context: name))
    case "lineCount": return .bodyLineCount(try integerRange(value, context: name))
    case "wordCount": return .bodyWordCount(try integerRange(value, context: name))
    default: throw MarkdownRuleConfigurationError.unsupportedFeature("Unsupported document predicate \"\(name)\"")
    }
  }

  private static func integerRange(_ value: Any, context: String) throws -> MarkdownRuleIntegerRange {
    guard let object = value as? [String: Any] else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) must be an object")
    }
    try validateKeys(object, allowed: ["min", "max"], context: context)
    let minimum = try object["min"].map { try nonnegativeInteger($0, context: "\(context).min") }
    let maximum = try object["max"].map { try nonnegativeInteger($0, context: "\(context).max") }
    guard minimum != nil || maximum != nil else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) requires min or max")
    }
    if let minimum, let maximum, minimum > maximum {
      throw MarkdownRuleConfigurationError.invalidField("\(context) min cannot exceed max")
    }
    return MarkdownRuleIntegerRange(minimum: minimum, maximum: maximum)
  }

  private static func between(_ value: Any, context: String) throws -> MarkdownRuleBetweenRange {
    guard let object = value as? [String: Any], let from = object["from"], let through = object["to"] else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) requires from and to")
    }
    try validateKeys(object, allowed: ["from", "to"], context: context)
    if let fromNumber = numericValue(from), let throughNumber = numericValue(through) {
      guard fromNumber <= throughNumber else {
        throw MarkdownRuleConfigurationError.invalidField("\(context) from cannot exceed to")
      }
      return .number(from: fromNumber, through: throughNumber)
    }
    let fromDate = try dateTime(from, context: "\(context).from")
    let throughDate = try dateTime(through, context: "\(context).to")
    guard fromDate.date <= throughDate.date else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) from cannot exceed to")
    }
    return .dateTime(from: fromDate, through: throughDate)
  }

  private static func validateKeys(
    _ object: [String: Any],
    allowed: Set<String>,
    context: String
  ) throws {
    let unknown = Set(object.keys).subtracting(allowed).sorted()
    guard unknown.isEmpty else {
      throw MarkdownRuleConfigurationError.unsupportedFeature(
        "\(context) contains unsupported key(s): \(unknown.joined(separator: ", "))"
      )
    }
  }

  private static func requiredString(
    _ object: [String: Any],
    key: String,
    context: String
  ) throws -> String {
    guard let value = object[key] else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) requires \(key)")
    }
    return try nonemptyString(value, context: "\(context).\(key)")
  }

  private static func nonemptyString(_ value: Any, context: String) throws -> String {
    guard let value = value as? String, value.isEmpty == false else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) must be a nonempty string")
    }
    return value
  }

  private static func stringArray(_ value: Any?, context: String) throws -> [String] {
    guard let value else { return [] }
    guard let values = value as? [String], values.allSatisfy({ $0.isEmpty == false }) else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) must be an array of nonempty strings")
    }
    return values
  }

  private static func nonnegativeInteger(_ value: Any?, context: String) throws -> Int {
    guard let value, let integer = value as? Int, integer >= 0 else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) must be a nonnegative integer")
    }
    return integer
  }

  private static func number(_ value: Any, context: String) throws -> Double {
    guard let value = numericValue(value) else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) must be a number")
    }
    return value
  }

  private static func numericValue(_ value: Any) -> Double? {
    if let value = value as? Int { return Double(value) }
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    return nil
  }

  private static func jsonArray(_ value: Any, context: String) throws -> [JSONValue] {
    guard let values = value as? [Any], values.isEmpty == false else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) must be a nonempty array")
    }
    return try values.map { try JSONValue(any: $0) }
  }

  private static func dateTime(_ value: Any, context: String) throws -> MarkdownRuleDateTimeLiteral {
    guard let value = value as? String, let literal = MarkdownRuleDateTimeLiteral(value) else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) must be YYYY-MM-DD or RFC 3339")
    }
    return literal
  }

  private static func trueOperand(_ value: Any, context: String) throws {
    guard let value = value as? Bool, value else {
      throw MarkdownRuleConfigurationError.invalidField("\(context) must be true")
    }
  }
}

/// Encodes normalized rules as either supported project configuration version.
/// Encodes normalized rule definitions using a supported configuration version.
///
/// See <doc:RuleConfigurationVersions>.
public enum MarkdownRuleConfigurationEncoder {
  public static func encode(_ configuration: MarkdownRuleConfiguration) throws -> String {
    guard MarkdownRuleConfigurationSchemaVersion.supported.contains(configuration.configVersion) else {
      throw MarkdownRuleConfigurationError.unsupportedVersion(configuration.configVersion)
    }
    var object: [String: Any] = [
      "configVersion": configuration.configVersion,
      "schemaDirectory": configuration.schemaDirectory,
    ]
    if let schemaReference = configuration.schemaReference { object["$schema"] = schemaReference }
    let rules = try configuration.rules.map {
      try ruleObject($0, version: configuration.configVersion)
    }
    if configuration.configVersion == MarkdownRuleConfigurationSchemaVersion.legacy {
      object["schemaRules"] = rules
    } else {
      object["rules"] = rules
    }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    guard let value = String(data: data, encoding: .utf8) else {
      throw MarkdownRuleConfigurationError.invalidSerialization("Could not encode UTF-8 JSON")
    }
    return value + "\n"
  }

  /// Returns the JSON-compatible representation of one normalized rule.
  public static func ruleObject(
    _ rule: MarkdownRuleDefinition,
    version: String = MarkdownRuleConfigurationSchemaVersion.current
  ) throws -> [String: Any] {
    let match = try matchObject(rule.applicability)
    if version == MarkdownRuleConfigurationSchemaVersion.legacy {
      guard rule.checks.count == 1,
            case .frontmatterSchema(let source, let presence) = rule.checks[0].predicate,
            case .reference(let schema) = source else {
        throw MarkdownRuleConfigurationError.unsupportedFeature(
          "Legacy configuration supports exactly one frontmatterSchema check"
        )
      }
      return [
        "name": rule.name,
        "schema": schema,
        "frontmatterRequired": presence == .required,
        "match": match,
      ]
    }
    return [
      "name": rule.name,
      "match": match,
      "checks": try rule.checks.map(checkObject),
    ]
  }

  private static func matchObject(_ applicability: MarkdownRuleApplicability) throws -> [String: Any] {
    var object: [String: Any] = [:]
    if applicability.paths.isEmpty == false { object["paths"] = applicability.paths }
    if applicability.excludePaths.isEmpty == false { object["excludePaths"] = applicability.excludePaths }
    var file: [String: Any] = [:]
    var frontmatter: [String: [String: Any]] = [:]
    var query: [String: Any] = [:]
    var document: [String: Any] = [:]
    for requirement in applicability.requirements {
      switch requirement.predicate {
      case .pathRegularExpression(let value): file["pathRegex"] = value
      case .filenameEquals(let value): file["filenameEquals"] = value
      case .extensionIn(let value): file["extensionIn"] = value
      case .modifiedAfter(let value): file["modifiedAfter"] = value.rawValue
      case .modifiedBefore(let value): file["modifiedBefore"] = value.rawValue
      case .frontmatterField(let key, let operation):
        var operators = frontmatter[key] ?? [:]
        let pair = try frontmatterObject(operation)
        operators[pair.key] = pair.value
        frontmatter[key] = operators
      case .frontmatterJMESPath(let value): query["jmespath"] = value
      case .heading(let predicate):
        if let level = predicate.level {
          document["hasHeadingAtLevel"] = ["heading": predicate.text, "level": level]
        } else {
          document["hasHeading"] = predicate.text
        }
      case .headingRegularExpression(let value): document["headingRegex"] = value
      case .section(let value): document["hasSection"] = value
      case .bodyContains(let value): document["bodyContains"] = value
      case .bodyRegularExpression(let value): document["bodyRegex"] = value
      case .wikilink(let target): document["hasWikilink"] = target ?? true
      case .bodyLineCount(let value): document["lineCount"] = rangeObject(value)
      case .bodyWordCount(let value): document["wordCount"] = rangeObject(value)
      case .markdown:
        throw MarkdownRuleConfigurationError.unsupportedFeature(
          "Portable Markdown constraints are not representable in config 0.2.0 match syntax"
        )
      }
    }
    if file.isEmpty == false { object["file"] = file }
    if frontmatter.isEmpty == false { object["frontmatter"] = frontmatter }
    if query.isEmpty == false { object["frontmatterQuery"] = query }
    if document.isEmpty == false { object["document"] = document }
    return object
  }

  private static func checkObject(_ check: MarkdownRuleCheck) throws -> [String: Any] {
    switch check.predicate {
    case .frontmatterSchema(let source, let presence):
      guard case .reference(let schema) = source else {
        throw MarkdownRuleConfigurationError.unsupportedFeature("Inline schemas are not representable in config 0.2.0")
      }
      return [
        "type": "frontmatterSchema",
        "schema": schema,
        "frontmatterRequired": presence == .required,
      ]
    case .markdown(let predicate):
      switch predicate {
      case .heading(let value) where value.level == nil:
        return ["type": "requiredHeading", "heading": value.text]
      case .maxBodyLines(let value): return ["type": "maxBodyLines", "max": value]
      case .maxBodyWords(let value): return ["type": "maxBodyWords", "max": value]
      default:
        throw MarkdownRuleConfigurationError.unsupportedFeature(
          "Markdown predicate is not representable as a config 0.2.0 check"
        )
      }
    }
  }

  private static func frontmatterObject(
    _ operation: MarkdownFrontmatterRuleOperator
  ) throws -> (key: String, value: Any) {
    switch operation {
    case .equals(let value): return ("equals", value.foundationValue)
    case .doesNotEqual(let value): return ("doesntEqual", value.foundationValue)
    case .includes(let value): return ("includes", value.foundationValue)
    case .doesNotInclude(let value): return ("notIncludes", value.foundationValue)
    case .hasKey: return ("hasKey", true)
    case .doesNotHaveKey: return ("doesntHaveKey", true)
    case .regularExpression(let value): return ("regex", value)
    case .startsWith(let value): return ("startsWith", value)
    case .endsWith(let value): return ("endsWith", value)
    case .contains(let value): return ("contains", value)
    case .empty: return ("empty", true)
    case .emptyString: return ("emptyString", true)
    case .emptyArray: return ("emptyArray", true)
    case .emptyObject: return ("emptyObject", true)
    case .notEmpty: return ("notEmpty", true)
    case .isIn(let value): return ("in", value.map(\.foundationValue))
    case .isNotIn(let value): return ("notIn", value.map(\.foundationValue))
    case .greaterThan(let value): return ("greaterThan", value)
    case .greaterThanOrEqual(let value): return ("greaterThanOrEqual", value)
    case .lessThan(let value): return ("lessThan", value)
    case .lessThanOrEqual(let value): return ("lessThanOrEqual", value)
    case .after(let value): return ("after", value.rawValue)
    case .onOrAfter(let value): return ("onOrAfter", value.rawValue)
    case .before(let value): return ("before", value.rawValue)
    case .onOrBefore(let value): return ("onOrBefore", value.rawValue)
    case .between(let range):
      switch range {
      case .number(let from, let through): return ("between", ["from": from, "to": through])
      case .dateTime(let from, let through):
        return ("between", ["from": from.rawValue, "to": through.rawValue])
      }
    case .typeIs(let value): return ("typeIs", value.rawValue)
    }
  }

  private static func rangeObject(_ range: MarkdownRuleIntegerRange) -> [String: Int] {
    var object: [String: Int] = [:]
    if let minimum = range.minimum { object["min"] = minimum }
    if let maximum = range.maximum { object["max"] = maximum }
    return object
  }
}

/// Typed failures raised while decoding or encoding rule configuration.
public enum MarkdownRuleConfigurationError: Error, Equatable, LocalizedError {
  case invalidSerialization(String)
  case notAnObject
  case unsupportedVersion(String)
  case invalidField(String)
  case unsupportedFeature(String)

  public var errorDescription: String? {
    switch self {
    case .invalidSerialization(let message): return "Invalid md-utils configuration: \(message)"
    case .notAnObject: return "md-utils configuration must be a JSON object"
    case .unsupportedVersion(let version):
      return "Unsupported md-utils configVersion \"\(version)\"; supported versions: \(MarkdownRuleConfigurationSchemaVersion.supported.joined(separator: ", "))"
    case .invalidField(let message): return "Invalid md-utils configuration: \(message)"
    case .unsupportedFeature(let message): return "Unsupported md-utils rule feature: \(message)"
    }
  }
}
