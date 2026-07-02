//
//  SchemaDescribe.swift
//  md-utils
//

import ArgumentParser
import Foundation
import PathKit

/// Adds Markdown document behavior to ``CLIEntry.SchemaCommands``.
///
/// See <doc:SchemaValidationCommands> for workflow details.
extension CLIEntry.SchemaCommands {
  /// Defines the `SchemaDescribe` command behavior.
  ///
  /// See <doc:SchemaValidationCommands> for workflow details.
  struct Describe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "describe",
      abstract: "Describe a configured schema rule and its JSON Schema"
    )

    @Argument(help: "Schema rule name to describe")
    var schemaName: String

    @Option(name: .long, help: "Output format: text or json")
    var format: SchemaDescribeOutputFormat = .text
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:SchemaValidationCommands> for workflow details.
    mutating func run() async throws {
      let description = try SchemaDescriptionBuilder.describe(ruleName: schemaName)
      switch format {
      case .text:
        print(SchemaDescriptionFormatter.render(description))
      case .json:
        try printAny(SchemaDescriptionJSONRenderer.render(description), format: .json)
      }
    }
  }
}

/// Supported output formats for the `schema describe` command.
enum SchemaDescribeOutputFormat: String, ExpressibleByArgument {
  case text
  case json
}

/// Complete data needed to describe one schema rule.
struct SchemaDescription {
  var rule: SchemaRule
  var schemaPath: Path
  var jsonSchema: [String: Any]
}

/// Loads configured schema rule details and the referenced JSON Schema.
enum SchemaDescriptionBuilder {
  /// Loads the requested schema rule and referenced JSON Schema from disk.
  static func describe(ruleName: String) throws -> SchemaDescription {
    let config = try MdUtilsConfig.load()
    guard let rule = config.schemaRules.first(where: { $0.name == ruleName }) else {
      throw ValidationError("Schema rule not found: \"\(ruleName)\"")
    }

    let schemaPath = SchemaPaths.schemaFile(rule: rule, config: config)
    let schema = try SchemaDocumentLoader.load(path: schemaPath)
    return SchemaDescription(rule: rule, schemaPath: schemaPath, jsonSchema: schema)
  }
}

/// Renders the machine-readable representation for a schema description.
enum SchemaDescriptionJSONRenderer {
  /// Returns a JSON-compatible object for command output.
  static func render(_ description: SchemaDescription) -> [String: Any] {
    let rule = description.rule
    return [
      "rule": [
        "name": rule.name,
        "schema": rule.schema,
        "schemaPath": description.schemaPath.string,
        "frontmatterRequired": rule.frontmatterRequired,
        "match": [
          "paths": rule.match.paths,
          "excludePaths": rule.match.excludePaths,
          "frontmatter": rule.match.frontmatter.mapValues { $0.jsonObject },
        ],
      ],
      "jsonSchema": description.jsonSchema,
    ]
  }
}

/// Renders concise human-readable schema descriptions.
enum SchemaDescriptionFormatter {
  /// Renders the value into its human-readable output representation.
  static func render(_ description: SchemaDescription) -> String {
    var lines: [String] = []
    let rule = description.rule

    lines.append("\(CLIStyle.metadata("Schema Rule Name:")) \(CLIStyle.schemaDescribeRuleName(rule.name))")
    lines.append("")
    lines.append(CLIStyle.schemaDescribeHeading("Schema Rule"))
    lines.append(contentsOf: ruleSummaryLines(rule, schemaPath: description.schemaPath))
    lines.append("")
    lines.append(CLIStyle.schemaDescribeHeading("Schema Definition"))

    let fields = JSONSchemaFieldSummarizer.fields(in: description.jsonSchema)
    if fields.isEmpty {
      lines.append(CLIStyle.muted("No top-level fields are defined."))
    } else {
      for field in fields {
        lines.append(CLIStyle.schemaDescribeFieldName(field.path))
        lines.append("\(CLIStyle.metadata("Type:")) \(field.typeAndConstraints)")
      }
    }

    return lines.joined(separator: "\n")
  }

  private static func ruleSummaryLines(_ rule: SchemaRule, schemaPath: Path) -> [String] {
    var lines: [String] = []

    if rule.match.paths.isEmpty {
      lines.append("Applies to Markdown files matched by frontmatter conditions.")
    } else {
      lines.append("Applies to Markdown files matching \(rule.match.paths.joined(separator: ", ")).")
    }
    if !rule.match.excludePaths.isEmpty {
      lines.append("Excludes \(rule.match.excludePaths.joined(separator: ", ")).")
    }
    if !rule.match.frontmatter.isEmpty {
      lines.append("Runs only when \(frontmatterMatchers(rule.match.frontmatter)).")
    }
    lines.append(rule.frontmatterRequired ? "Frontmatter is required." : "Files without frontmatter are skipped.")
    lines.append("Schema: \(CLIStyle.path(schemaPath.string))")

    return lines
  }

  private static func frontmatterMatchers(_ matchers: [String: FrontmatterMatcher]) -> String {
    matchers.keys.sorted().compactMap { key in
      guard let matcher = matchers[key] else { return nil }
      return "\(key) includes \(JSONSchemaFieldSummarizer.displayValue(matcher.includes))"
    }.joined(separator: "; ")
  }
}

/// One field summarized from a JSON Schema document.
struct JSONSchemaFieldSummary {
  var path: String
  var typeAndConstraints: String
}

/// Summarizes JSON Schema object properties into concise field descriptions.
enum JSONSchemaFieldSummarizer {
  /// Returns all fields defined by nested JSON Schema object properties.
  static func fields(in schema: [String: Any]) -> [JSONSchemaFieldSummary] {
    let required = stringArray(schema["required"])
    return fields(in: schema, prefix: nil, requiredFields: Set(required))
  }

  /// Returns a stable human-readable value for constraints and matchers.
  static func displayValue(_ value: Any) -> String {
    if let string = value as? String {
      return "\"\(string)\""
    }
    if let array = value as? [Any] {
      return "[\(array.map(displayValue).joined(separator: ", "))]"
    }
    if let object = value as? [String: Any] {
      let entries = object.keys.sorted().compactMap { key -> String? in
        guard let value = object[key] else { return nil }
        return "\"\(key)\": \(displayValue(value))"
      }
      return "{\(entries.joined(separator: ", "))}"
    }
    if value is NSNull {
      return "null"
    }
    return String(describing: value)
  }

  private static func fields(
    in schema: [String: Any],
    prefix: String?,
    requiredFields: Set<String>
  ) -> [JSONSchemaFieldSummary] {
    guard let properties = schema["properties"] as? [String: Any] else {
      return []
    }

    var summaries: [JSONSchemaFieldSummary] = []
    for name in properties.keys.sorted() {
      guard let property = properties[name] as? [String: Any] else { continue }
      let path = prefix.map { "\($0).\(name)" } ?? name
      let isRequired = requiredFields.contains(name)
      summaries.append(JSONSchemaFieldSummary(
        path: path,
        typeAndConstraints: typeAndConstraints(for: property, required: isRequired)
      ))
      summaries.append(contentsOf: nestedFields(in: property, path: path))
    }
    return summaries
  }

  private static func nestedFields(in schema: [String: Any], path: String) -> [JSONSchemaFieldSummary] {
    let type = schemaType(schema)
    if type == "object" || schema["properties"] != nil {
      return fields(in: schema, prefix: path, requiredFields: Set(stringArray(schema["required"])))
    }
    if type == "array", let items = schema["items"] as? [String: Any] {
      let itemPath = "\(path)[]"
      if items["properties"] != nil || schemaType(items) == "object" {
        return fields(in: items, prefix: itemPath, requiredFields: Set(stringArray(items["required"])))
      }
    }
    return []
  }

  private static func typeAndConstraints(for schema: [String: Any], required: Bool) -> String {
    var parts = [displayType(schema)]
    if required {
      parts.append(CLIStyle.warning("REQUIRED"))
    }
    parts.append(contentsOf: constraintParts(schema))
    return parts.joined(separator: ", ")
  }

  private static func displayType(_ schema: [String: Any]) -> String {
    if let ref = schema["$ref"] as? String {
      return "Reference \(ref)"
    }

    let type = schemaType(schema)
    if type == "array" {
      guard let items = schema["items"] as? [String: Any] else {
        return "Array"
      }
      return "Array<\(displayType(items))>"
    }
    if !type.isEmpty {
      return type.capitalized
    }
    if schema["enum"] != nil {
      return "Enum"
    }
    if schema["const"] != nil {
      return "Const"
    }
    return "Any"
  }

  private static func schemaType(_ schema: [String: Any]) -> String {
    if let type = schema["type"] as? String {
      return type
    }
    if let types = schema["type"] as? [String] {
      return types.joined(separator: " or ")
    }
    return ""
  }

  private static func constraintParts(_ schema: [String: Any]) -> [String] {
    var parts: [String] = []
    appendConstraint("minLength", from: schema, to: &parts)
    appendConstraint("maxLength", from: schema, to: &parts)
    appendConstraint("minimum", from: schema, to: &parts)
    appendConstraint("maximum", from: schema, to: &parts)
    appendConstraint("exclusiveMinimum", from: schema, to: &parts)
    appendConstraint("exclusiveMaximum", from: schema, to: &parts)
    appendConstraint("minItems", from: schema, to: &parts)
    appendConstraint("maxItems", from: schema, to: &parts)
    appendConstraint("pattern", from: schema, to: &parts)
    appendConstraint("format", from: schema, to: &parts)
    if let values = schema["enum"] as? [Any] {
      parts.append("enum [\(values.map(displayValue).joined(separator: ", "))]")
    }
    if let value = schema["const"] {
      parts.append("const \(displayValue(value))")
    }
    appendAdvancedConstraint("oneOf", from: schema, to: &parts)
    appendAdvancedConstraint("anyOf", from: schema, to: &parts)
    appendAdvancedConstraint("allOf", from: schema, to: &parts)
    return parts
  }

  private static func appendConstraint(_ name: String, from schema: [String: Any], to parts: inout [String]) {
    guard let value = schema[name] else { return }
    parts.append("\(name) \(displayValue(value))")
  }

  private static func appendAdvancedConstraint(_ name: String, from schema: [String: Any], to parts: inout [String]) {
    guard let values = schema[name] as? [Any] else { return }
    parts.append("\(name) with \(values.count) option(s)")
  }

  private static func stringArray(_ value: Any?) -> [String] {
    value as? [String] ?? []
  }
}
