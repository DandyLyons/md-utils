import Foundation
import Yams

/// Supported serialization formats for Markdown type definitions.
public enum MarkdownTypeDefinitionFormat: String, Codable, Equatable, Sendable {
  case yaml
  case json
}

/// Decodes YAML and JSON type definitions into the same portable model.
public enum MarkdownTypeDefinitionDecoder {
  public static func decode(
    _ content: String,
    format: MarkdownTypeDefinitionFormat,
    source: String? = nil
  ) throws -> MarkdownTypeDefinition {
    let object = try rootObject(content, format: format)
    try validateKeys(
      object,
      allowed: ["md-utils-type-schema", "name", "version", "frontmatter", "body", "context"],
      required: ["md-utils-type-schema", "name", "version", "frontmatter", "body", "context"],
      context: "type definition"
    )
    let schemaVersion = try requiredString(object, key: "md-utils-type-schema", context: "type definition")
    let name = try requiredString(object, key: "name", context: "type definition")
    let version = try requiredString(object, key: "version", context: "type definition")

    let frontmatter = try parseFrontmatter(object["frontmatter"])
    let body = try parseGroup(object["body"], domain: .body, typeName: name)
    let context = try parseGroup(object["context"], domain: .context, typeName: name)

    return MarkdownTypeDefinition(
      typeSchemaVersion: schemaVersion,
      name: MarkdownTypeName(rawValue: name),
      version: version,
      frontmatter: frontmatter,
      body: body,
      context: context,
      source: source
    )
  }

  private static func rootObject(
    _ content: String,
    format: MarkdownTypeDefinitionFormat
  ) throws -> [String: Any] {
    switch format {
    case .json:
      guard let data = content.data(using: .utf8) else {
        throw MarkdownTypeDefinitionError.invalidSerialization("Type definition is not UTF-8")
      }
      do {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          throw MarkdownTypeDefinitionError.notAnObject
        }
        return object
      } catch let error as MarkdownTypeDefinitionError {
        throw error
      } catch {
        throw MarkdownTypeDefinitionError.invalidSerialization(error.localizedDescription)
      }
    case .yaml:
      do {
        guard let node = try Yams.compose(yaml: content) else {
          throw MarkdownTypeDefinitionError.notAnObject
        }
        guard let object = try YAMLConversion.safeNodeToSwiftValue(node) as? [String: Any] else {
          throw MarkdownTypeDefinitionError.notAnObject
        }
        return object
      } catch let error as MarkdownTypeDefinitionError {
        throw error
      } catch {
        throw MarkdownTypeDefinitionError.invalidSerialization(error.localizedDescription)
      }
    }
  }

  private static func parseFrontmatter(_ value: Any?) throws -> MarkdownFrontmatterDefinition {
    guard let value else {
      return MarkdownFrontmatterDefinition()
    }
    guard let object = value as? [String: Any] else {
      throw MarkdownTypeDefinitionError.invalidField("frontmatter must be an object")
    }
    try validateKeys(
      object,
      allowed: ["presence", "schemas"],
      required: [],
      context: "frontmatter"
    )

    let presence: MarkdownFrontmatterPresence?
    if let rawPresence = object["presence"] {
      guard let string = rawPresence as? String,
            let parsed = MarkdownFrontmatterPresence(rawValue: string) else {
        throw MarkdownTypeDefinitionError.invalidField("frontmatter.presence must be required or optional")
      }
      presence = parsed
    } else {
      presence = nil
    }

    let rawSchemas: [Any]
    if let value = object["schemas"] {
      guard let schemas = value as? [Any] else {
        throw MarkdownTypeDefinitionError.invalidField("frontmatter.schemas must be an array")
      }
      rawSchemas = schemas
    } else {
      rawSchemas = []
    }
    let schemas = try rawSchemas.enumerated().map { index, rawSchema in
      guard let schemaObject = rawSchema as? [String: Any] else {
        throw MarkdownTypeDefinitionError.invalidField("frontmatter.schemas[\(index)] must be an object")
      }
      if let reference = schemaObject["ref"] as? String, reference.isEmpty == false {
        guard schemaObject.count == 1 else {
          throw MarkdownTypeDefinitionError.invalidField("frontmatter.schemas[\(index)] ref cannot be combined with other keys")
        }
        return MarkdownJSONSchemaSource.reference(reference)
      }
      if let inline = schemaObject["inline"] {
        guard schemaObject.count == 1 else {
          throw MarkdownTypeDefinitionError.invalidField("frontmatter.schemas[\(index)] inline cannot be combined with other keys")
        }
        let value = try JSONValue(any: inline)
        guard value.objectValue != nil else {
          throw MarkdownTypeDefinitionError.invalidField("frontmatter.schemas[\(index)].inline must be an object")
        }
        return MarkdownJSONSchemaSource.inline(value)
      }
      throw MarkdownTypeDefinitionError.invalidField("frontmatter.schemas[\(index)] requires ref or inline")
    }

    return MarkdownFrontmatterDefinition(presence: presence, schemas: schemas)
  }

  private static func parseGroup(
    _ value: Any?,
    domain: MarkdownDiagnosticDomain,
    typeName: String
  ) throws -> MarkdownConstraintGroup {
    guard let value else {
      return MarkdownConstraintGroup()
    }
    guard let object = value as? [String: Any] else {
      throw MarkdownTypeDefinitionError.invalidField("\(domain.rawValue) must be an object")
    }
    try validateKeys(
      object,
      allowed: ["requirements", "recommendations"],
      required: ["requirements", "recommendations"],
      context: domain.rawValue
    )
    let requirements = try parseConstraints(
      object["requirements"],
      key: "\(domain.rawValue).requirements",
      domain: domain,
      typeName: typeName
    )
    let recommendations = try parseConstraints(
      object["recommendations"],
      key: "\(domain.rawValue).recommendations",
      domain: domain,
      typeName: typeName
    )
    return MarkdownConstraintGroup(requirements: requirements, recommendations: recommendations)
  }

  private static func parseConstraints(
    _ value: Any?,
    key: String,
    domain: MarkdownDiagnosticDomain,
    typeName: String
  ) throws -> [MarkdownConstraint] {
    guard let values = value as? [Any] else {
      throw MarkdownTypeDefinitionError.invalidField("\(key) must be an array")
    }
    return try values.enumerated().map { index, value in
      guard let object = value as? [String: Any] else {
        throw MarkdownTypeDefinitionError.invalidField("\(key)[\(index)] must be an object")
      }
      let id = try requiredString(object, key: "id", context: "\(key)[\(index)]")
      let predicates = object.keys.filter { $0 != "id" }
      guard predicates.count == 1, let predicateName = predicates.first else {
        throw MarkdownTypeDefinitionError.invalidField("\(key)[\(index)] must contain exactly one predicate")
      }
      guard let predicateValue = object[predicateName] else {
        throw MarkdownTypeDefinitionError.invalidField("\(key)[\(index)] predicate is missing")
      }
      let predicate = try parsePredicate(
        name: predicateName,
        value: predicateValue,
        domain: domain,
        context: "type \(typeName) constraint \(id)"
      )
      return MarkdownConstraint(id: id, predicate: predicate)
    }
  }

  private static func parsePredicate(
    name: String,
    value: Any,
    domain: MarkdownDiagnosticDomain,
    context: String
  ) throws -> MarkdownPredicate {
    switch name {
    case "heading":
      guard domain == .body else {
        throw MarkdownTypeDefinitionError.invalidField("\(context): heading is only valid in body")
      }
      return .heading(try parseHeading(value, context: context))
    case "headingRelationship":
      guard domain == .body, let object = value as? [String: Any] else {
        throw MarkdownTypeDefinitionError.invalidField("\(context): headingRelationship must be a body object")
      }
      try validateKeys(
        object,
        allowed: ["parent", "child", "relationship"],
        required: ["parent", "child", "relationship"],
        context: "\(context) headingRelationship"
      )
      guard let parent = object["parent"], let child = object["child"] else {
        throw MarkdownTypeDefinitionError.invalidField("\(context): headingRelationship requires parent and child")
      }
      let relationshipString = try requiredString(object, key: "relationship", context: context)
      guard let relationship = MarkdownHeadingRelationship(rawValue: relationshipString) else {
        throw MarkdownTypeDefinitionError.invalidField("\(context): unsupported heading relationship \(relationshipString)")
      }
      return .headingRelationship(MarkdownHeadingRelationshipPredicate(
        parent: try parseHeading(parent, context: "\(context) parent"),
        child: try parseHeading(child, context: "\(context) child"),
        relationship: relationship
      ))
    case "section":
      guard domain == .body, let object = value as? [String: Any], let heading = object["heading"] else {
        throw MarkdownTypeDefinitionError.invalidField("\(context): section must be a body object with heading")
      }
      try validateKeys(
        object,
        allowed: ["heading", "content"],
        required: ["heading"],
        context: "\(context) section"
      )
      let content: MarkdownSectionContentRequirement
      if let rawContent = object["content"] as? String {
        guard let parsed = MarkdownSectionContentRequirement(rawValue: rawContent) else {
          throw MarkdownTypeDefinitionError.invalidField("\(context): section.content must be any or nonEmpty")
        }
        content = parsed
      } else {
        content = .any
      }
      return .section(MarkdownSectionPredicate(
        heading: try parseHeading(heading, context: "\(context) heading"),
        content: content
      ))
    case "path":
      guard domain == .context, let object = value as? [String: Any] else {
        throw MarkdownTypeDefinitionError.invalidField("\(context): path must be a context object")
      }
      try validateKeys(
        object,
        allowed: ["glob"],
        required: ["glob"],
        context: "\(context) path"
      )
      let glob = try requiredString(object, key: "glob", context: context)
      return .path(MarkdownPathPredicate(glob: glob))
    case "maxBodyLines":
      guard domain == .body, let maximum = nonnegativeInteger(value) else {
        throw MarkdownTypeDefinitionError.invalidField("\(context): maxBodyLines must be a nonnegative integer")
      }
      return .maxBodyLines(maximum)
    case "maxBodyWords":
      guard domain == .body, let maximum = nonnegativeInteger(value) else {
        throw MarkdownTypeDefinitionError.invalidField("\(context): maxBodyWords must be a nonnegative integer")
      }
      return .maxBodyWords(maximum)
    default:
      throw MarkdownTypeDefinitionError.invalidField("\(context): unsupported predicate \(name)")
    }
  }

  private static func parseHeading(_ value: Any, context: String) throws -> MarkdownHeadingPredicate {
    guard let object = value as? [String: Any] else {
      throw MarkdownTypeDefinitionError.invalidField("\(context): heading must be an object")
    }
    try validateKeys(
      object,
      allowed: ["text", "level"],
      required: ["text"],
      context: context
    )
    let text = try requiredString(object, key: "text", context: context)
    let level: Int?
    if let rawLevel = object["level"] {
      guard let parsed = nonnegativeInteger(rawLevel), (1...6).contains(parsed) else {
        throw MarkdownTypeDefinitionError.invalidField("\(context): heading level must be between 1 and 6")
      }
      level = parsed
    } else {
      level = nil
    }
    return MarkdownHeadingPredicate(text: text, level: level)
  }

  private static func requiredString(
    _ object: [String: Any],
    key: String,
    context: String
  ) throws -> String {
    guard let value = object[key] as? String, value.isEmpty == false else {
      throw MarkdownTypeDefinitionError.invalidField("\(context) requires a nonempty \(key)")
    }
    return value
  }

  private static func nonnegativeInteger(_ value: Any) -> Int? {
    if let value = value as? Int, value >= 0 {
      return value
    }
    if let value = value as? NSNumber, value.intValue >= 0, value.doubleValue == Double(value.intValue) {
      return value.intValue
    }
    return nil
  }

  private static func validateKeys(
    _ object: [String: Any],
    allowed: Set<String>,
    required: Set<String>,
    context: String
  ) throws {
    let unknown = Set(object.keys).subtracting(allowed).sorted()
    guard unknown.isEmpty else {
      throw MarkdownTypeDefinitionError.invalidField(
        "\(context) contains unsupported key(s): \(unknown.joined(separator: ", "))"
      )
    }
    let missing = required.subtracting(object.keys).sorted()
    guard missing.isEmpty else {
      throw MarkdownTypeDefinitionError.invalidField(
        "\(context) is missing required key(s): \(missing.joined(separator: ", "))"
      )
    }
  }
}

/// Errors raised while loading or compiling Markdown type definitions.
public enum MarkdownTypeDefinitionError: Error, Equatable, LocalizedError {
  case invalidSerialization(String)
  case notAnObject
  case invalidField(String)
  case unsupportedSchemaVersion(String)
  case duplicateType(String)
  case duplicateConstraint(type: String, id: String)
  case unresolvedSchema(type: String, reference: String)
  case schemaNotAnObject(type: String)
  case schemaReferenceCycle(type: String, resources: [String])
  case conflictingSchemaIdentifier(type: String, identifier: String)

  public var errorDescription: String? {
    switch self {
    case .invalidSerialization(let message):
      return "Invalid Markdown type serialization: \(message)"
    case .notAnObject:
      return "A Markdown type definition must be an object"
    case .invalidField(let message):
      return "Invalid Markdown type definition: \(message)"
    case .unsupportedSchemaVersion(let version):
      return "Unsupported md-utils-type-schema \(version)"
    case .duplicateType(let name):
      return "Duplicate Markdown type name \(name)"
    case .duplicateConstraint(let type, let id):
      return "Markdown type \(type) contains duplicate constraint id \(id)"
    case .unresolvedSchema(let type, let reference):
      return "Markdown type \(type) could not resolve schema \(reference)"
    case .schemaNotAnObject(let type):
      return "Markdown type \(type) contains a JSON Schema that is not an object"
    case .schemaReferenceCycle(let type, let resources):
      return "Markdown type \(type) contains a JSON Schema reference cycle: \(resources.joined(separator: " -> "))"
    case .conflictingSchemaIdentifier(let type, let identifier):
      return "Markdown type \(type) contains conflicting JSON Schemas with identifier \(identifier)"
    }
  }
}
