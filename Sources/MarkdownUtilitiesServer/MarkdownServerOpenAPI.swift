import Foundation
import MarkdownUtilitiesCore
import OpenAPIKit
import Yams

/// Supported offline serialization formats for a generated OpenAPI document.
public enum MarkdownServerOpenAPIFormat: String, Codable, CaseIterable, Sendable {
  /// Deterministic, pretty-printed JSON.
  case json
  /// Deterministic YAML with lexicographically sorted mapping keys.
  case yaml
}

/// Stable categories reported when an endpoint plan cannot produce a valid contract.
public enum MarkdownServerOpenAPIDiagnosticCode: String, Codable, Sendable {
  /// A route references inconsistent or unavailable plan data.
  case invalidPlan = "openapi.plan.invalid"
  /// A resolved mdtype schema is incompatible with the OpenAPI 3.1 schema dialect.
  case unsupportedSchema = "openapi.schema.unsupported"
  /// The assembled document fails strict OpenAPI validation.
  case invalidDocument = "openapi.document.invalid"
  /// A valid document could not be serialized in the requested format.
  case serializationFailed = "openapi.serialization.failed"
}

/// One deterministic OpenAPI generation problem.
public struct MarkdownServerOpenAPIDiagnostic: Codable, Equatable, Sendable {
  /// Stable machine-readable category.
  public let code: MarkdownServerOpenAPIDiagnosticCode
  /// Endpoint-plan or generated-document location associated with the problem.
  public let location: String
  /// Human-readable explanation suitable for startup output.
  public let message: String

  /// Creates one OpenAPI generation diagnostic.
  public init(code: MarkdownServerOpenAPIDiagnosticCode, location: String, message: String) {
    self.code = code
    self.location = location
    self.message = message
  }
}

/// A deterministic failure to generate or serialize an OpenAPI description.
public struct MarkdownServerOpenAPIGenerationError: Error, Codable, Equatable, Sendable,
  LocalizedError
{
  /// Every detected problem in stable location order.
  public let diagnostics: [MarkdownServerOpenAPIDiagnostic]

  /// Creates a generation failure from one or more diagnostics.
  public init(diagnostics: [MarkdownServerOpenAPIDiagnostic]) {
    self.diagnostics = diagnostics.sorted {
      ($0.location, $0.code.rawValue, $0.message) < ($1.location, $1.code.rawValue, $1.message)
    }
  }

  /// Concise rendering of every generation problem.
  public var errorDescription: String? {
    diagnostics.map { "\($0.location): \($0.message)" }.joined(separator: "; ")
  }
}

/// One immutable OpenAPI 3.1.1 description generated from an ``EndpointPlan``.
public struct MarkdownServerOpenAPIDocument: Codable, Equatable, Sendable {
  /// Complete JSON-compatible document value shared by JSON and YAML serializers.
  public let value: JSONValue

  /// Creates a document from an already validated JSON-compatible value.
  public init(value: JSONValue) {
    self.value = value
  }

  /// Serializes the document deterministically.
  ///
  /// - Parameter format: JSON or YAML output format.
  /// - Returns: UTF-8 bytes, including a final newline.
  /// - Throws: ``MarkdownServerOpenAPIGenerationError`` when serialization fails.
  public func serialized(format: MarkdownServerOpenAPIFormat) throws -> Data {
    do {
      switch format {
      case .json:
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
      case .yaml:
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = true
        var yaml = try encoder.encode(value)
        if yaml.hasSuffix("\n") == false { yaml.append("\n") }
        guard let data = yaml.data(using: .utf8) else {
          throw EncodingError.invalidValue(
            yaml,
            .init(codingPath: [], debugDescription: "YAML output is not UTF-8")
          )
        }
        return data
      }
    } catch let error as MarkdownServerOpenAPIGenerationError {
      throw error
    } catch {
      throw MarkdownServerOpenAPIGenerationError(diagnostics: [
        MarkdownServerOpenAPIDiagnostic(
          code: .serializationFailed,
          location: "document",
          message: error.localizedDescription
        )
      ])
    }
  }
}

/// Generates a complete OpenAPI 3.1.1 description from immutable endpoint-plan data.
public enum MarkdownServerOpenAPIGenerator {
  /// OpenAPI version emitted by this package release.
  public static let specificationVersion = "3.1.1"

  /// Builds and strictly validates one deterministic OpenAPI document.
  ///
  /// Resolved mdtype schemas are preserved as authored within resource frontmatter
  /// components. Invalid rule-selected records retain the generic unconstrained envelope.
  ///
  /// - Parameter plan: Sole source of routes, operations, resources, and referenced schemas.
  /// - Returns: An immutable document ready for JSON or YAML serialization.
  /// - Throws: ``MarkdownServerOpenAPIGenerationError`` for plan or schema incompatibility.
  public static func generate(from plan: EndpointPlan) throws -> MarkdownServerOpenAPIDocument {
    var diagnostics: [MarkdownServerOpenAPIDiagnostic] = []
    var resources: [String: PlannedMarkdownResource] = [:]
    for resource in plan.resources {
      if resources.updateValue(resource, forKey: resource.name) != nil {
        diagnostics.append(.init(
          code: .invalidPlan,
          location: "resources.\(resource.name)",
          message: "Endpoint plan contains a duplicate resource name"
        ))
      }
    }
    var typeSchemas: [MarkdownTypeName: ResolvedMarkdownTypeFrontmatterSchema] = [:]
    for (typeIndex, schema) in plan.typeSchemas.enumerated() {
      if typeSchemas.updateValue(schema, forKey: schema.name) != nil {
        diagnostics.append(.init(
          code: .invalidPlan,
          location: "typeSchemas[\(typeIndex)]",
          message: "Endpoint plan contains duplicate schemas for type \"\(schema.name.rawValue)\""
        ))
      }
      for (schemaIndex, value) in schema.schemas.enumerated() {
        do {
          let data = try JSONEncoder().encode(value)
          let decoded = try JSONDecoder().decode(OpenAPIKit.JSONSchema.self, from: data)
          if decoded.warnings.isEmpty == false {
            throw SchemaWarning(description: decoded.warnings.map(\.localizedDescription).joined(separator: "; "))
          }
        } catch {
          diagnostics.append(.init(
            code: .unsupportedSchema,
            location: "typeSchemas[\(typeIndex)].schemas[\(schemaIndex)]",
            message: "Type \"\(schema.name.rawValue)\" uses an unsupported schema: \(error.localizedDescription)"
          ))
        }
      }
    }
    for resource in plan.resources {
      let referencedType: MarkdownTypeName?
      switch resource.selection {
      case .rule:
        referencedType = nil
      case .type(let name, _), .ruleWithExpectedType(_, let name):
        referencedType = name
      }
      if let referencedType, typeSchemas[referencedType] == nil {
        diagnostics.append(.init(
          code: .invalidPlan,
          location: "resources.\(resource.name).selection",
          message: "Resource references unavailable type schema \"\(referencedType.rawValue)\""
        ))
      }
    }
    var paths: [String: JSONValue] = [:]

    for route in plan.routes {
      guard route.method == .get else {
        diagnostics.append(.init(
          code: .invalidPlan,
          location: "routes.\(route.operationID).method",
          message: "OpenAPI generation does not support method \"\(route.method.rawValue)\""
        ))
        continue
      }
      let resource = route.resourceName.flatMap { resources[$0] }
      let requiresResource = route.kind == .collection || route.kind == .item
      if requiresResource && resource == nil {
        diagnostics.append(.init(
          code: .invalidPlan,
          location: "routes.\(route.operationID).resourceName",
          message: "Route references an unavailable resource"
        ))
        continue
      }
      if requiresResource == false && route.resourceName != nil {
        diagnostics.append(.init(
          code: .invalidPlan,
          location: "routes.\(route.operationID).resourceName",
          message: "Server-wide route must not reference a resource"
        ))
        continue
      }
      if paths[route.path.rawValue] != nil {
        diagnostics.append(.init(
          code: .invalidPlan,
          location: "routes.\(route.operationID).path",
          message: "Endpoint plan contains more than one GET operation for \"\(route.path.rawValue)\""
        ))
        continue
      }
      paths[route.path.rawValue] = object([
        "get": operation(for: route, resource: resource, typeSchemas: typeSchemas),
      ])
    }

    if diagnostics.isEmpty == false {
      throw MarkdownServerOpenAPIGenerationError(diagnostics: diagnostics)
    }

    let value = object([
      "openapi": string(specificationVersion),
      "jsonSchemaDialect": string("https://json-schema.org/draft/2020-12/schema"),
      "info": object([
        "title": string("md-utils Server API"),
        "version": string("1"),
      ]),
      "paths": .object(paths),
      "components": object([
        "schemas": .object(componentSchemas(typeSchemas: plan.typeSchemas)),
      ]),
      "x-md-utils-server-config-version": string(plan.serverConfigVersion),
    ])
    let document = MarkdownServerOpenAPIDocument(value: value)
    try validate(document)
    return document
  }

  private static func validate(_ document: MarkdownServerOpenAPIDocument) throws {
    do {
      let data = try document.serialized(format: .json)
      let decoded = try JSONDecoder().decode(OpenAPI.Document.self, from: data)
      try decoded.validate(strict: true)
    } catch let error as MarkdownServerOpenAPIGenerationError {
      throw error
    } catch {
      throw MarkdownServerOpenAPIGenerationError(diagnostics: [
        .init(
          code: .invalidDocument,
          location: "document",
          message: error.localizedDescription
        )
      ])
    }
  }

  private static func operation(
    for route: EndpointRouteDescription,
    resource: PlannedMarkdownResource?,
    typeSchemas: [MarkdownTypeName: ResolvedMarkdownTypeFrontmatterSchema]
  ) -> JSONValue {
    var value: [String: JSONValue] = [
      "operationId": string(route.operationID),
      "responses": responses(for: route, resource: resource, typeSchemas: typeSchemas),
    ]
    if let resource {
      value["tags"] = array([string(resource.name)])
    }
    switch route.kind {
    case .collection:
      value["summary"] = string("List \(resource?.name ?? "Markdown records")")
    case .item:
      value["summary"] = string("Get one \(resource?.name ?? "Markdown record") record")
      value["parameters"] = array([pathParameter(
        name: "id",
        description: "Primary resource identity"
      )])
    case .logicalPath:
      value["summary"] = string("Get one canonical record by logical path")
      value["parameters"] = array([pathParameter(
        name: "path",
        description: "Collection-relative logical path, including nested path components"
      )])
      value["x-md-utils-catch-all"] = .boolean(true)
    case .openAPI:
      value["summary"] = string("Get the active OpenAPI description")
    }
    if case .ruleWithExpectedType(_, let expectedType) = resource?.selection,
       typeSchemas[expectedType] != nil
    {
      value["x-md-utils-expected-frontmatter-schema"] = reference(
        typeComponentName(expectedType)
      )
    }
    return .object(value)
  }

  private static func responses(
    for route: EndpointRouteDescription,
    resource: PlannedMarkdownResource?,
    typeSchemas: [MarkdownTypeName: ResolvedMarkdownTypeFrontmatterSchema]
  ) -> JSONValue {
    switch route.kind {
    case .collection:
      return object([
        "200": response(
          description: "Selected Markdown records, including invalid rule-selected items",
          schema: object([
            "type": string("array"),
            "items": recordSchema(for: resource, typeSchemas: typeSchemas),
          ])
        ),
      ])
    case .item:
      return object([
        "200": response(
          description: "The unambiguous selected Markdown record",
          schema: recordSchema(for: resource, typeSchemas: typeSchemas)
        ),
        "400": errorResponse("The identity is missing or invalid"),
        "404": errorResponse("No selected record has the requested identity"),
        "409": errorResponse("Several selected records share the requested identity"),
      ])
    case .logicalPath:
      return object([
        "200": response(
          description: "The unambiguous canonical Markdown record",
          schema: reference("GenericMarkdownRecord")
        ),
        "400": errorResponse("The logical path is invalid"),
        "404": errorResponse("No canonical record has the requested logical path"),
        "409": errorResponse("Several canonical records share the requested logical path"),
      ])
    case .openAPI:
      return object([
        "200": response(
          description: "The active OpenAPI 3.1.1 description",
          schema: object(["type": string("object"), "additionalProperties": .boolean(true)])
        ),
      ])
    }
  }

  private static func recordSchema(
    for resource: PlannedMarkdownResource?,
    typeSchemas: [MarkdownTypeName: ResolvedMarkdownTypeFrontmatterSchema]
  ) -> JSONValue {
    guard let resource,
          case .type(let typeName, _) = resource.selection,
          let schema = typeSchemas[typeName],
          schema.schemas.isEmpty == false
    else { return reference("GenericMarkdownRecord") }

    var properties: [String: JSONValue] = [
      "frontmatter": reference(typeComponentName(typeName)),
    ]
    var typed: [String: JSONValue] = [
      "type": string("object"),
      "properties": .object(properties),
    ]
    if schema.presence == .required {
      typed["required"] = array([string("frontmatter")])
    } else {
      properties["frontmatter"] = object([
        "anyOf": array([reference(typeComponentName(typeName)), object(["type": string("null")])]),
      ])
      typed["properties"] = .object(properties)
    }
    return object([
      "allOf": array([reference("GenericMarkdownRecord"), .object(typed)]),
    ])
  }

  private static func componentSchemas(
    typeSchemas: [ResolvedMarkdownTypeFrontmatterSchema]
  ) -> [String: JSONValue] {
    var schemas = genericComponentSchemas()
    for schema in typeSchemas {
      let combined: JSONValue
      if schema.schemas.isEmpty {
        combined = object(["type": string("object")])
      } else if schema.schemas.count == 1 {
        combined = schema.schemas[0]
      } else {
        combined = object(["allOf": .array(schema.schemas)])
      }
      schemas[typeComponentName(schema.name)] = combined
    }
    return schemas
  }

  private static func genericComponentSchemas() -> [String: JSONValue] {
    let stringOrNull = object([
      "type": array([string("string"), string("null")]),
    ])
    return [
      "GenericMarkdownRecord": object([
        "type": string("object"),
        "required": strings(["identityStatus", "memberships", "valid", "body", "diagnostics"]),
        "properties": object([
          "canonicalIdentity": stringOrNull,
          "identityStatus": enumSchema(["available", "missing", "invalid", "duplicate"]),
          "logicalPath": stringOrNull,
          "revision": stringOrNull,
          "memberships": object([
            "type": string("array"),
            "items": reference("GenericMarkdownResourceMembership"),
          ]),
          "valid": object(["type": string("boolean")]),
          "frontmatter": object([
            "type": array([string("object"), string("null")]),
            "additionalProperties": .boolean(true),
          ]),
          "body": object(["type": string("string")]),
          "diagnostics": object([
            "type": string("array"),
            "items": reference("MarkdownServerRecordDiagnostic"),
          ]),
        ]),
        "additionalProperties": .boolean(false),
      ]),
      "GenericMarkdownResourceMembership": object([
        "type": string("object"),
        "required": strings([
          "resourceName", "selectionMode", "identityStatus", "assessedTypes", "valid",
        ]),
        "properties": object([
          "resourceName": object(["type": string("string")]),
          "selectionMode": enumSchema(["rule", "type", "ruleWithExpectedType"]),
          "identity": stringOrNull,
          "identityStatus": enumSchema(["available", "missing", "invalid", "duplicate"]),
          "ruleAssessment": nullableReference("GenericMarkdownRuleAssessment"),
          "selectedType": stringOrNull,
          "assessedTypes": object([
            "type": string("array"),
            "items": reference("GenericMarkdownTypeAssessment"),
          ]),
          "valid": object(["type": string("boolean")]),
        ]),
        "additionalProperties": .boolean(false),
      ]),
      "GenericMarkdownRuleAssessment": object([
        "type": string("object"),
        "required": strings(["name", "applicable", "passes"]),
        "properties": object([
          "name": object(["type": string("string")]),
          "applicable": object(["type": string("boolean")]),
          "passes": object(["type": string("boolean")]),
        ]),
        "additionalProperties": .boolean(false),
      ]),
      "GenericMarkdownTypeAssessment": object([
        "type": string("object"),
        "required": strings(["name", "version", "conforms"]),
        "properties": object([
          "name": object(["type": string("string")]),
          "version": object(["type": string("string")]),
          "conforms": object(["type": string("boolean")]),
        ]),
        "additionalProperties": .boolean(false),
      ]),
      "MarkdownServerRecordDiagnostic": object([
        "type": string("object"),
        "required": strings(["code", "severity", "source", "location", "message", "paths"]),
        "properties": object([
          "code": object(["type": string("string")]),
          "severity": enumSchema(["error", "advisory"]),
          "source": enumSchema(["parsing", "identity", "rule", "type"]),
          "location": object(["type": string("string")]),
          "message": object(["type": string("string")]),
          "constraintID": stringOrNull,
          "ruleName": stringOrNull,
          "typeName": stringOrNull,
          "identity": stringOrNull,
          "paths": object([
            "type": string("array"),
            "items": object(["type": string("string")]),
          ]),
        ]),
        "additionalProperties": .boolean(false),
      ]),
      "MarkdownServerHTTPErrorEnvelope": object([
        "type": string("object"),
        "required": strings(["error"]),
        "properties": object(["error": reference("MarkdownServerHTTPError")]),
        "additionalProperties": .boolean(false),
      ]),
      "MarkdownServerHTTPError": object([
        "type": string("object"),
        "required": strings(["code", "message"]),
        "properties": object([
          "code": object(["type": string("string")]),
          "message": object(["type": string("string")]),
          "candidates": object([
            "type": array([string("array"), string("null")]),
            "items": reference("GenericMarkdownRecord"),
          ]),
        ]),
        "additionalProperties": .boolean(false),
      ]),
    ]
  }

  private static func response(description: String, schema: JSONValue) -> JSONValue {
    object([
      "description": string(description),
      "content": object([
        "application/json": object(["schema": schema]),
      ]),
    ])
  }

  private static func errorResponse(_ description: String) -> JSONValue {
    response(description: description, schema: reference("MarkdownServerHTTPErrorEnvelope"))
  }

  private static func pathParameter(name: String, description: String) -> JSONValue {
    object([
      "name": string(name),
      "in": string("path"),
      "required": .boolean(true),
      "description": string(description),
      "schema": object(["type": string("string")]),
    ])
  }

  private static func typeComponentName(_ name: MarkdownTypeName) -> String {
    let encoded = name.rawValue.utf8.map { String(format: "%02X", $0) }.joined()
    return "MarkdownType_\(encoded)_Frontmatter"
  }

  private static func reference(_ component: String) -> JSONValue {
    object(["$ref": string("#/components/schemas/\(component)")])
  }

  private static func nullableReference(_ component: String) -> JSONValue {
    object(["anyOf": array([reference(component), object(["type": string("null")])])])
  }

  private static func enumSchema(_ values: [String]) -> JSONValue {
    object(["type": string("string"), "enum": strings(values)])
  }

  private static func object(_ value: [String: JSONValue]) -> JSONValue { .object(value) }
  private static func array(_ value: [JSONValue]) -> JSONValue { .array(value) }
  private static func string(_ value: String) -> JSONValue { .string(value) }
  private static func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }
}

private struct SchemaWarning: LocalizedError {
  let description: String

  var errorDescription: String? { description }
}
